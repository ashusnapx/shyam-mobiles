# Moving Shyam Mobiles from Supabase to Firebase

Status: plan, 2026-11-03. Owner decision: everything moves to Google/Firebase (Firestore, Firebase Auth, Cloud
Functions 2nd gen in TypeScript, Cloud Storage, FCM, plus Analytics, Crashlytics, Remote Config and App Check).
This file is the contract for the engineers doing the move. When Phase 2 ends, `docs/SPEC.md` takes over the
sections marked here and this file stays as the migration record. Security and privacy controls (App Check, MFA,
IAM, DPDP) live in **[`docs/SECURITY.md`](SECURITY.md)**. Where the two differ, SECURITY.md wins.

## 0. Decisions at a glance

| # | Decision | Why |
|---|---|---|
| D1 | Everything in **asia-south1** (Mumbai): Firestore, Functions, the Storage bucket | It is the closest region to Singrauli. A Firestore location can never be changed. |
| D2 | **Clients write only simple documents** directly, under Security Rules: their own profile fields, addresses, cart, wishlist, notification read marks and devices, plus staff's simple config documents. **Every money, stock or state change goes through a callable Function** that runs a Firestore transaction. | This is the same split as today (RLS for simple rows, RPCs for the rest). Rules cannot count, loop or lock. |
| D3 | **Catalog index documents** (`catalogIndex/public`, `catalogIndex/staff`) replace the `product_cards` view, full-text search and `admin_catalogue`. A trigger keeps them up to date, and the app searches, filters and sorts them on the phone. | One read powers home, search, rails, wishlist and offer pages. It works offline and handles Hindi. No composite-index explosion. |
| D4 | **PhonePe only.** Razorpay is removed at cut-over, along with payment links, EMI lines, saved cards and dispute alerts. | Production holds only demo money. The PhonePe parity table (§5) drops these features or defers them to the dashboard. |
| D5 | Sign-in is **Google + phone OTP** only. Password and email sign-in go. Staff rights come from the **custom claim `role`**. The owner claims the shop once, by verified phone. | Fewer providers to secure. Claims are checked in both Rules and Functions. |
| D6 | **Functional core, imperative shell** in Functions: pure services (pricing, state machines, notification copy, GST) are unit-tested without Firestore. Handlers validate with zod, check auth, and run `load → decide → write` inside a transaction. | The rules stay testable and are not tied to Firestore. Interfaces exist only where a real fake is needed (the payment gateway). |
| D7 | App: **repository interfaces per domain** behind Riverpod providers. One compile-time switch, `BACKEND=supabase\|firebase`, picks the implementation. The Supabase implementations wrap today's code until Phase 2 deletes them. | The app keeps working at every step. A single switch avoids an untested mix of backends. |
| D8 | **Notifications** are written by Firestore triggers from a pure `notices(before, after)` function. A second trigger pushes data-only FCM messages through the Admin SDK, with the same payload keys as today's `send-push`. | No pg_net, no Vault, no service-account JSON. `lib/core/push.dart` keeps working unchanged. |
| D9 | One **scheduled** job (expire unpaid orders, every 5 min). Cleanup uses **Firestore TTL policies**. | This fits in Cloud Scheduler's 3 free jobs per billing account. |
| D10 | Node **22** runtime (`nodejs22`), `firebase-functions` 7, `firebase-admin` 14, zod 4, vitest 5, TypeScript **6.0** (typescript-eslint 8 supports < 6.1, so not TS 7), `@firebase/rules-unit-testing` **5.0.1** (pinned: 6.x needs Node ≥ 24.12). | Node 22 is the newest version the Firebase docs list. Deprecation is due 2027-04-30, so move to `nodejs24` before then. |

## 1. Inventory: Supabase → Firebase

### Tables and views

| Supabase | Firebase | Notes |
|---|---|---|
| `profiles` | `users/{uid}` | The client creates it at first sign-in (Rules: only `fullName`, `photoUrl`, and `phone` = token phone). The server writes `role`. |
| `admins`, `is_admin()` | custom claim `role: 'owner'\|'staff'`, mirrored in `users/{uid}.role` | The claim is used by Rules and Functions. The field lets the server find staff to notify. |
| `categories`, `brands` | `categories/{slug}`, `brands/{slug}` | The slug is the doc id, which makes it unique for free. Staff write under Rules. |
| `products` + `product_images` | `products/{slug}` with `images[]` embedded | The slug is immutable after create. Images are at most 12 per product. |
| `variants` | `variants/{autoId}` (top level) | Cart and order lines point at variants. Denormalised fields: `productId`, `productActive`, `productName`. |
| `product_cards` view, `products.search` tsvector + GIN | `catalogIndex/public` (active only) and `catalogIndex/staff` (everything, with stock) | **No clean equivalent.** See D3 and §3. |
| `wishlist` | `users/{uid}/wishlist/{productId}` `{productId, addedAt, waitVariant: variantId\|'*'\|null}` | `waitVariant` is the back-in-stock mark (§6). Removing the heart deletes the doc, which stops the alert. |
| `cart_items` | `carts/{uid}` `{lines: {variantId: {qty, addedAt}}}` | Rules cap it at 20 lines. qty 1..5 is checked by `quoteOrder`/`placeOrder` (Rules cannot iterate map values). |
| `addresses` | `users/{uid}/addresses/{a0..a9}`, `users/{uid}.defaultAddressId` | The 10 fixed ids cap the count. One default field means there is always exactly one default. |
| `orders` + `order_items` + `order_events` | `orders/{autoId}` with `items[]` (≤ 10) and `events[]` embedded | Read in one go. Item id = variantId. |
| `order_number_seq`, `repair_number_seq` | `counters/orders`, `counters/repairs` (incremented in the same transaction) | SM100001 / RP100001 continue. |
| `payment_events` | dropped | PhonePe settles from its status API. The settle state machine is idempotent. |
| `repair_bookings` + `repair_events` | `repairs/{autoId}` with `events[]` and `quote{}` embedded | |
| `store_settings` | `settings/store` (operations) and `settings/business` (legal identity, new) | Public read, staff write under Rules. |
| `collections` + `collection_products` | `collections/{slug}` `{productIds[] ≤ 500}` | |
| `promotions` + `promotion_targets` | `promotions/{autoId}` with `targets[]`. Lookup docs `promoCodes/{CODE}`. Mirrors `publicOffers/{id}` and `users/{uid}/coupons/{id}` | Customers never read `promotions`, because hidden and personal codes must not be listable. |
| `promotion_redemptions` | `redemptions/{orderId}` `{promotionId, uid, discountPaise, active}` | |
| `coupon_attempts` | `rateLimits/{uid}` `{couponFails: Timestamp[]}` | Written outside the order transaction, so a failed checkout now counts too (fixes today's shortcut). |
| `banners` | `banners/{autoId}` | |
| `referral_codes`, `referrals` | `referralCodes/{CODE}` `{uid}`, `referrals/{refereeUid}` | The doc ids enforce one code per person and one referral per referee. |
| `feedback` | `feedback/{id}`: id `order_{orderId}` / `repair_{repairId}` / auto | The id enforces one rating per order or repair (was a partial unique index). |
| `notifications` | `users/{uid}/notifications/{id}` | TTL on `expireAt` (90 days). |
| `device_tokens` | `devices/{token}` `{uid, platform, updatedAt, expireAt}` | TTL at 270 days. |
| `refunds`, `order_items.refund_id` | `orders/{id}/refunds/{refundId}`, `items[].refundId` | |
| (PhonePe plan) `phonepe_orders` | `orders/{id}/payments/{merchantOrderId}` | Server only. |
| `payment_links`, `razorpay_customers`, `disputes` | dropped (D4) | |
| `private.password_sign_in_domains` | dropped | There is no password provider. |
| bucket `product-images` | Storage `product-images/{key}` (same keys), `invoices/{uid}/{orderId}.pdf` (Phase 2) | |

### RPCs, triggers, functions, jobs, integrations

| Supabase | Firebase | Owner |
|---|---|---|
| `quote_order`, `place_order`, `private.price_lines`, `evaluate_promotion`, `covers` | callables `quoteOrder`, `placeOrder`. Pure `orders/pricing.ts` | C |
| `cancel_order`, `admin_update_order`, `admin_set_imeis`, `restock_order` | `cancelOrder`, `adminUpdateOrder`, `adminSetImeis`. Internal `restock()` | C |
| `mark_order_paid`, `mark_payment_failed`, `mark_order_refunded`, `settle_refund` | `orders/settlement.ts`: `settleOnlinePayment()`, `settleRefund()` (called by payments) | C |
| `expire_unpaid_orders` + pg_cron `*/5` | `onSchedule('every 5 minutes')` `expireUnpaidOrders` | C |
| `admin_dashboard` | client `count()`/`sum()` aggregation queries (staff Rules) plus `catalogIndex/staff` | C |
| `available_offers`, `offers_for_product`, `offer_products` | reads of `publicOffers` and `users/{uid}/coupons`, plus a pure Dart `offerOpenFor()`. `quoteOrder` stays the source of truth | C |
| `admin_save_promotion`, `admin_promotions`, `sync_promotion_banner` | `savePromotion` (writes promotion, `promoCodes`, mirrors and banner in one transaction). Staff read `promotions` | C |
| `my_referral`, `apply_referral_code`, trigger `reward_referral` | `myReferral`, `applyReferralCode`. The reward is paid inside `adminUpdateOrder`'s transaction on → delivered | C |
| `admin_catalogue`, product/variant/image writes, `product-images` policies | `saveProduct`, `saveVariant`, `setProductImages`, `updateVariants` (the catalogue's guarded stock, price and visibility edits), `setFeatured`, `deleteProduct` callables. Client search over `catalogIndex/staff`. Storage Rules | B |
| `cancel_repair`, `approve_repair_quote`, `decline_repair_quote`, repair insert (RLS), `admin_update_repair`, `admin_set_repair_quote`, `repair_booking_*` triggers, `REPAIR_LIMIT` trigger | `bookRepair`, `cancelRepair`, `approveRepairQuote`, `declineRepairQuote`, `adminUpdateRepair`, `adminSetRepairQuote` | D |
| `send_feedback` | `sendFeedback`. Staff update `status`/`adminNote` under Rules | D |
| `notify_order_change`, `notify_order_event`, `notify_repair_event`, `notify_personal_coupon`, `notify_feedback`, `notify_low_stock`, `notification_image`, `inr`/`clip`/copy helpers | `notifications/notices.ts` (pure) + `copy.ts`. Triggers on `orders`, `repairs`, `feedback`, `users/{uid}/coupons`, `variants`, `orders/{id}/refunds` | D |
| `push_notification` (pg_net + Vault) + Edge Function `send-push` | `onDocumentCreated('users/{uid}/notifications/{id}')` → `messaging().sendEach()` | D |
| `unread_notifications`, `mark_notifications_read`, `register_device` | client `count()` query, batch update of `readAt` (Rules), client write of `devices/{token}` | D / A |
| Edge Functions `create-payment`, `verify-payment`, `razorpay-webhook`, `refund-payment` | `createPayment`, `verifyPayment`, `phonepeWebhook` (HTTP), `startRefund` | D |
| Edge Functions `payment-link`, `emi-plans`, `send-sms`, `reset-password` | dropped (D4, Firebase sends the OTP SMS, and reset-password is being reverted) | — |
| Edge Function `delete-account` | `deleteAccount` callable | A |
| `handle_new_user`, `custom_access_token_hook`, `clear_must_change_password`, `account_by_phone` | the client creates `users/{uid}` under Rules. The rest is dropped (no passwords) | A |
| `set_updated_at` triggers | `updatedAt: serverTimestamp()` set by every write helper and checked in Rules (`request.time`) | all |
| `addresses_before_write`, `cart_items_before_insert` (advisory locks + counts) | fixed address ids + `defaultAddressId`, and Rules `lines.size() <= 20` | A / C |
| pg_cron `notifications-cleanup`, `job-run-details-cleanup` | TTL policies on `expireAt` (notifications, devices, rateLimits) | A |
| Integrations: Razorpay, MSG91 + DLT, Resend SMTP, Supabase Vault | removed. Phone OTP SMS comes from Firebase. Secrets live in Secret Manager (`defineSecret`) | — |
| Integrations kept: FCM, Google sign-in, Play Install Referrer, App Links (`firebase/hosting/open.html`) | unchanged. Firebase Dynamic Links shut down on 2025-08-25, and this app never used them | — |

### No clean equivalent, and the replacement chosen

| Postgres feature | Replacement |
|---|---|
| Full-text search (`tsvector`, prefix tsquery, Hindi-safe) | `catalogIndex/public`: compact entries (name, brand, category, variant names, price, stock flag, cover, ids). A pure Dart `searchCards(index, params)` reuses today's `prefixTsQuery` word splitting. Description text is no longer searched (product names carry brand and model). Upgrade at more than about 1,500 products: shard the index by category. Past about 5,000: Typesense or Firestore Enterprise text search. |
| Row locks, `FOR UPDATE`, advisory locks | Firestore transactions in the Admin SDK lock what they read. `users/{uid}` is read and written by `placeOrder` and `applyReferralCode` as the **per-user serialization point** (was `pg_advisory_xact_lock('orders:'‖uid)`). The promotion doc read in the transaction stops two checkouts from taking the last use. |
| CHECK constraints, domains, enums | zod schemas in `shared/validation.ts` for every callable input, and `assert*()` invariants before every write (for example, total = subtotal + fee − discount). The same regexes in `firestore.rules` for client-written docs. Shared test vectors keep Rules, zod and Dart in step. |
| Unique and partial unique indexes | Doc ids (slugs, codes, `order_{id}` feedback, fixed address ids) or checks inside transactions (SKU query, `order.pendingRefundId`). |
| Sequences | Counter docs incremented in the same transaction (≤ 1 write/s per counter, far above shop volume). |
| FK cascades / `set null` | Products are hidden, never hard-deleted (`deleteProduct` refuses once any order references it). `deleteAccount` anonymises orders, repairs and feedback (`uid: null`) and deletes the rest. |
| pg_net + Vault | Firestore trigger + Admin SDK FCM. Secret Manager. |
| Column-level grants | Rules `request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])`. |

## 2. Target architecture

### App (Flutter)

Layers, top to bottom. Each layer depends only on the one below:

1. **Presentation**: `screens/`, `widgets/` (unchanged).
2. **Application state**: Riverpod providers and notifiers in `data/<feature>.dart` (for example `CartNotifier`). They depend on repository interfaces, never on Firebase or Supabase types.
3. **Domain**: models in `lib/core/models/` (pure Dart, as today) and pure functions (`best_offer.dart`, `offerOpenFor`, `searchCards`, GST math, cart rules).
4. **Data**: one `abstract interface class` per boundary, plus a Firebase implementation (and a Supabase one until Phase 2).

Interfaces exist only at real boundaries (Phase 0 wrote them; each sits in its feature's `data/` folder with its provider): `AuthRepository`, `ProfileRepository` (profile, addresses, delete account), `CatalogRepository` (customer reads), `WishlistRepository`, `SettingsRepository` (`settings/store`), `CatalogAdminRepository` (the staff catalogue and product edits), `PhotoStore` (Storage uploads), `CartRepository`, `OrdersRepository` (quote, place, cancel, staff updates, dashboard), `OffersRepository` (offers, home banners, referrals), `OffersAdminRepository` (staff promotions, groups, banners), `RepairsRepository`, `FeedbackRepository`, `NotificationsRepository`, `PaymentGateway` (PhonePe SDK, D's `features/payments/data/`), `PushService` (`core/push.dart`), `Telemetry` (`core/telemetry.dart`: Analytics + Crashlytics). Customer and staff sides get separate interfaces. Formatters, pure rules, widgets and the router get no interface.

Per-feature layout, which keeps today's convention:

```
lib/features/cart/data/
  cart_repository.dart            # interface + cartRepositoryProvider (the DI seam)
  cart_repository_firebase.dart   # Firestore/Functions implementation; maps docs → domain models
  cart_repository_supabase.dart   # today's queries moved here unchanged; deleted in Phase 2
  cart.dart                       # CartNotifier etc., now ref.watch(cartRepositoryProvider)
lib/core/
  backend.dart     # enum Backend { supabase, firebase } from --dart-define=BACKEND (default supabase until cut-over)
  firebase.dart    # init (firebase_options.dart), emulator wiring, firestore/functions(region asia-south1)/storage/auth providers
  callable.dart    # callFunction(functions, name, data, replayProtected); errors.dart reads details.reason
app/test/fakes/    # one fake per interface; widget tests override the providers with these
```

- DI: `Provider<CartRepository>((ref) => backend == Backend.firebase ? FirebaseCartRepository(...) : SupabaseCartRepository(...))`. Tests use `ProviderScope(overrides: [cartRepositoryProvider.overrideWithValue(FakeCartRepository())])`.
- Errors: callables throw `HttpsError(code, message, {reason: 'OUT_OF_STOCK', detail})`. `lib/core/errors.dart` keeps its `_codes` table and reads `details.reason`, so the business codes are unchanged.
- Offline: Firestore's on-device cache (on by default for Android, 40 MB) and `snapshots()` streams replace `savedOrFetch` for settings, banners and the catalog index. The cached copy shows first, then the server copy. Writes that matter (`placeOrder`, payments) need a connection and say so.
- Config: `flutterfire configure --project=shyam-mobiles --platforms=android` writes `lib/firebase_options.dart` and `android/app/google-services.json` (public by design, committed). This replaces the `FIREBASE_*` dart-defines.
- Packages (pub.dev, 2026-10-23): `firebase_core` 5.1, `firebase_auth` 7.0, `cloud_firestore` 7.1, `cloud_functions` 7.0, `firebase_storage` 14.0, `firebase_messaging` 17.0, `firebase_analytics` 13.0, `firebase_crashlytics` 6.0, `firebase_remote_config` 7.0, `firebase_app_check` 0.5, `google_sign_in` 7.2, `phonepe_payment_sdk` 3.0.2. Test-only: `fake_cloud_firestore` 4.5, `firebase_auth_mocks` 0.16. Removed in Phase 2: `supabase_flutter`, `razorpay_flutter`, `flutter_secure_storage` (Firebase Auth keeps its own session).

### Backend (`firebase/` at the repo root)

```
firebase/
  firebase.json  .firebaserc (default: shyam-mobiles)  .nvmrc (22)
  firestore.rules  firestore.indexes.json  storage.rules
  test-vectors/          # JSON cases ported from pgTAP/api_e2e; read by functions tests AND app tests
  seed/                  # dev.json, seed.ts (emulator), import-supabase.ts, copy-photos.ts (one-off)
  functions/
    package.json (engines node 22, type module)  tsconfig.json (strict, noUncheckedIndexedAccess)
    eslint.config.mjs (typescript-eslint strict)  vitest.config.ts
    src/
      index.ts           # FROZEN: import './shared/options.js'; export * from './<domain>/index.js' (one line each)
      shared/            # money.ts (Paise brand, integer-only helpers), errors.ts (fail(reason, detail)),
                         # auth.ts (requireUser, requireStaff, requireOwner), validation.ts (zod: phone, name, cleanText…),
                         # time.ts (IST day/month, FY), db.ts (typed refs + converters), gst.ts (Phase 2)
      model/             # Firestore document types (§3): the data contract, one file per collection
      account/  catalog/  orders/  offers/  referrals/  repairs/  feedback/  notifications/  payments/  invoices/
                         # each: handlers.ts (callable/HTTP/trigger: parse → guard → transaction),
                         #       service.ts or named pure modules (pricing.ts, state.ts, notices.ts),
                         #       repository.ts (Firestore reads/writes taking a Transaction), contract.ts (zod in/out)
    test/
      unit/              # services and pure modules; no emulator; vectors
      rules/             # @firebase/rules-unit-testing on the Firestore + Storage emulators
      integration/       # callables + triggers on the full emulator suite (port of scripts/api_e2e.py)
```

- Layering rule: handlers may import services and repositories. Services import only `shared/` and `model/` (no `firebase-admin`). Repositories import `firebase-admin/firestore`. ESLint `no-restricted-imports` enforces this.
- Callables: `callable(contract, handler, options?)` from `shared/callable.ts`, never a bare `onCall`. It applies `shared/options.ts` (region, `setGlobalOptions`): App Check enforced on every project but the emulator's `demo-` one, `cors: false`, `maxInstances: 10`, a 30 s timeout, `REPLAY_PROTECTED` for the SECURITY §2.1 list; plus `shared/log.ts` (PII-safe logger, `audit()`) and `shared/rateLimit.ts`. Webhook: `onRequest` (no App Check). Defaults: `memory: '256MiB'`, `concurrency: 80`, `maxInstances: 10`, `minInstances: 0`.
- Money: `type Paise = number & { readonly __paise: true }`. Every constructor asserts `Number.isSafeInteger(n) && n >= 0`. Percentages use integer math (`Math.floor(v * pct / 100)`). `ORDER_TOO_LARGE` keeps the 2³¹−1 cap. GST rates are integer basis points (`1800` = 18%). Floats appear only at the Analytics boundary (`value: paise / 100`).
- Tests come first: Phase 0 ports the money, coupon and referral cases from `supabase/tests/*.test.sql` (offers, best_offer, orders, payments, refunds) and `scripts/api_e2e.py` into `test-vectors/*.json`. They must pass against `pricing.ts` before any handler is written.

## 3. Data model

Conventions: camelCase fields. Money is `*Paise: int`. Timestamps are Firestore `Timestamp`. IST calendar dates are `'YYYY-MM-DD'` strings. Enums are lowercase strings. Every doc carries `createdAt`/`updatedAt`. **S** = only the server writes, **C** = the client writes under Rules, **St** = staff write under Rules.

```ts
users/{uid}            { fullName: string|null (is_name, ≤80) C, photoUrl?: string C, phone?: '+91…' C(create, = token),
                         role?: 'owner'|'staff' S, defaultAddressId?: 'a0'..'a9' C, referralCode?: string S,
                         referralRewards?: { [yyyymm]: int } S,
                         consent: { noticeVersion, acceptedAt, analytics: bool } C (SECURITY §4.2),
                         prefs: { backInStock: bool = true, offers: bool = true, crashReports: bool = true } C }
users/{uid}/wishlist/{productId}  { productId, addedAt, waitVariant: variantId|'*'|null } C (SECURITY §4.5 retention: with the account)
users/{uid}/addresses/{a0..a9}  { name, phone, line1, line2?, landmark?, city, district?, state, stateCode ('23'), pincode, label } C
users/{uid}/notifications/{id}  { kind, title ≤80, body ≤300, link (app route), orderId?, repairId?, imagePath?,
                                  readAt: Timestamp|null (C: only this field), createdAt, expireAt } S
users/{uid}/coupons/{promotionId}  public fields of a personal promotion (mirror) S
carts/{uid}            { lines: { [variantId]: { qty: 1..5, addedAt } } (≤ 20 keys) } C
devices/{fcmToken}     { uid, platform: 'android'|'ios', updatedAt, expireAt } C (uid == auth.uid)

categories/{slug}      { name, kind: 'phone'|'accessory', sort } St
brands/{slug}          { name } St
products/{slug}        { name, brandId, brandName, categoryId, categoryKind, description ≤5000, specs: [{label,value}],
                         gstRateBp: int (0..2800, default 1800), hsnCode: '^[0-9]{4,8}$' (Phase 2),
                         isActive, isFeatured, images: [{ path, color?: string, sort }] (≤ 12) } S (saveProduct)
variants/{id}          { productId, productName, productActive, sku (unique), name, attributes {ram?,storage?,color?,colorHex?},
                         pricePaise > 0, mrpPaise ≥ price, stock 0..1e6, isActive, sort, lastStockChange: 'order'|'staff'|'refund',
                         restockSeq: int (+1 whenever stock goes 0 → > 0; set only by catalog/stock.ts applyStockChange) } S
collections/{slug}     { name, productIds: string[] ≤ 500 } St
catalogIndex/public    { cards: { [productId]: { n: name, s: slug, b: brandId, bn: brandName, c: categoryId, k: kind,
                         v: variant names joined, p: minPricePaise, m: mrpPaise, i: inStock, f: featured, cv: coverPath,
                         col: collectionIds[], t: createdAt millis } }, updatedAt } S (trigger)
catalogIndex/staff     same plus hidden products and per-variant [id, sku, name, pricePaise, mrpPaise, stock, isActive] S
banners/{id}           { title, subtitle, ctaLabel, link (app route), imagePath?, tone 0..5, startsAt, endsAt?, sort,
                         isActive, promotionId? } St (promotion banners: S via savePromotion)
settings/store         { deliveryFeePaise, freeDeliveryMinPaise, codEnabled, codMaxPaise, onlinePaymentEnabled,
                         storeHours, mapPin?: {lat,lng}, mapsUrl?, storePhotos: string[] ≤ 8, repairNote, returnsPolicy,
                         referral: { enabled, friendPaise, rewardPaise, minOrderPaise, monthlyCap } } St
settings/business      { tradeName: 'Shyam Online Shop', brandName: 'Shyam Mobiles', legalName, gstin: '23BXEPG0619P2ZG',
                         stateCode: '23' (must equal gstin[0..2]), phone: '+917987559272', email?, address: { line1:
                         'Rajeev Complex', city: 'Waidhan', district: 'Singrauli', state: 'Madhya Pradesh', pincode: '486886' },
                         businessTypes: ['retailer','wholesaler','distributor','services'], invoicePrefix: 'SOS' } St

promotions/{id}        { title, description, code: string|null, kind: 'percent'|'flat'|'free_delivery', value, maxDiscountPaise?,
                         minSubtotalPaise, appliesTo: 'order'|'items', targets: [{type:'product'|'category'|'brand'|'collection', id}],
                         startsAt, endsAt?, usageLimit?, perUserLimit? (savePromotion defaults it to 1, as the SQL did; null = no limit), firstOrderOnly, onlineOnly, isPublic, uid?, isActive,
                         showBanner, usesActive: int S, discountTotalPaise: int S } S (savePromotion)
promoCodes/{CODE}      { promotionId } S        publicOffers/{id} { public fields, usedUp: bool } S
redemptions/{orderId}  { promotionId, uid|null, discountPaise, active (false only on cancel/expiry, never on refund) } S      rateLimits/{uid} { couponFails: Timestamp[], expireAt } S
referralCodes/{CODE}   { uid } S      referrals/{refereeUid} { referrerUid, status: 'pending'|'rewarded'|'void', rewardedAt? } S

orders/{id}            { number: 'SM100001', uid|null, status, paymentMethod: 'online'|'cod', paymentStatus: 'pending'|'paid'|'failed'|'refunded',
                         subtotalPaise, deliveryFeePaise, discountPaise, totalPaise, promotion?: {id,title,code,kind}, couponCode?,
                         address: {…snapshot incl. stateCode}, buyer?: { gstin, legalName } (Phase 2),
                         items: [{ id: variantId, productId, productName, variantName, imagePath?, unitPricePaise, qty, gstRateBp,
                                   hsnCode?, discountPaise, imeis: string[], refundId? }],
                         events: [{ status, note?, by: 'customer'|'staff'|'system', byUid?, at }],
                         reservedUntil?, cancelledBy?: 'customer'|'staff'|'expiry', courier?, trackingNumber?,
                         payment?: { gateway: 'phonepe', merchantOrderId, transactionId?, paidAt? }, pendingRefundId?,
                         invoice?: { number, issuedAt, pdfPath, taxablePaise, cgstPaise, sgstPaise, igstPaise } } S
orders/{id}/payments/{merchantOrderId}  { state: 'pending'|'completed'|'failed', amountPaise, token, expireAt, transactionId? } S
orders/{id}/refunds/{refundId}          { amountPaise, fullRefund, restock, status: 'pending'|'processed'|'failed', gatewayRefundId?,
                                          failure?, createdBy } S
repairs/{id}           { number: 'RP100001', uid|null, deviceBrand, deviceModel, issue, description, preferredDate: 'YYYY-MM-DD',
                         slot, contactPhone, status, quote: { paise|null, status: 'none'|'pending'|'approved'|'declined', decidedAt? },
                         events: [{ status, quoteStatus?, quotePaise?, note?, by, byUid?, at }] } S
feedback/{id}          { uid|null, kind, rating?, message ≤1000, orderId?, repairId?, productId?, screen?, appVersion?,
                         status: 'new'|'seen'|'resolved' (St), adminNote? (St) } S
counters/{orders|repairs|invoice-2026-27}  { next: int } S
```

`cancelledBy` replaces today's "`reserved_until` null means a deliberate cancel" trick. `settings/store` loses `storePhone`/`storeAddress`: they now live in `settings/business`, the single source used by invoices, the policy pages (`firebase/hosting/`) and the app's call and WhatsApp buttons. **The proprietor's PAN is never stored, logged or derived as its own field anywhere.** The GSTIN is the only tax identifier we keep.

### Denormalised fields and how they stay in sync

| Copy | Source | Kept in sync by |
|---|---|---|
| `products.brandName`, `categoryKind`; `variants.productName`, `productActive` | brands, categories, products | `saveProduct` writes product and variants in one transaction. A trigger on `brands/*`/`categories/*` rewrites the affected products (rare). |
| `catalogIndex/public`, `catalogIndex/staff` entries | products, variants, collections | `onDocumentWritten` triggers recompute **one product's entry** from source docs and set that map key (idempotent, so safe on retry). A unit test fails if the seed catalogue ×2 passes 700 KB. |
| `orders.items[]`, `address`, `promotion` | catalog, address, promotion at checkout | Never synced: they are history. |
| `publicOffers/*`, `users/{uid}/coupons/*`, promotion banners, `promoCodes/*` | `promotions/*` | Written in the same transaction as the promotion (`savePromotion`, `applyReferralCode`, referral reward). `usedUp` flips in `placeOrder`/cancel/expiry. |
| `promotions.usesActive`, `discountTotalPaise` | redemptions | ± in the same transaction as the order placement, cancel or expiry. |
| `users.role` | custom claim | `claimOwner`/`setRole` set both. The app refreshes its ID token when the field changes. |

### Composite indexes (`firestore.indexes.json`)

`orders (uid ↑, createdAt ↓)`, `orders (uid ↑, status ↑)` (first-order and pending checks in transactions), `orders (status ↑, createdAt ↓)`, `orders (status ↑, reservedUntil ↑)` (expiry), `repairs (uid ↑, createdAt ↓)`, `repairs (uid ↑, status ↑)` (open-repairs cap), `repairs (status ↑, preferredDate ↑)`, `feedback (status ↑, createdAt ↓)`, `feedback (uid ↑, createdAt ↓)`, `variants (productId ↑, isActive ↑, productActive ↑, sort ↑)`, `variants (productId ↑, sort ↑)` (staff), `banners (isActive ↑, sort ↑)`, `redemptions (promotionId ↑, uid ↑, active ↑)`, **collection group** `wishlist (productId ↑, waitVariant ↑)` (back-in-stock). Equality-only queries (devices by uid, staff by role) use the automatic single-field indexes. TTL policies: `notifications.expireAt` (collection group), `devices.expireAt`, `rateLimits.expireAt`.

### Where each invariant is enforced now

| Invariant (SQL today) | Firebase | Where |
|---|---|---|
| Stock never negative (CHECK + `FOR UPDATE`) | `placeOrder` transaction reads every variant and fails with `OUT_OF_STOCK` (detail: variant ids). `setStock`/`saveProduct` take 0..1e6. Clients can never write `variants`. | Function + Rules |
| The client never sends prices. Totals: total = subtotal + fee − discount, discount = Σ line discounts ≤ subtotal − ₹1 | `pricing.ts` computes everything from docs. `assertOrderTotals()` runs before every order write. Rules deny all client writes to `orders`. | Function + Rules |
| One offer per order, never the worse one (`best_offer`) | `pricing.ts` returns one promotion, comparing the code's saving with the best automatic sale's. `COUPON_BETTER_OFFER` comes from quote only. | Function |
| Coupon total limit, per-user limit, first order only, online only, minimum, window | Same transaction: the promotion doc (locked), a redemptions query, and an orders query (`uid`, status ≠ cancelled). | Function |
| Coupon rate limit (10 failed codes / 10 min) | `rateLimits/{uid}`, written outside the order transaction. | Function |
| Referral: enabled, once per referee, not self, before the first order, reward once on the first delivered qualifying order, monthly cap (IST month) | `applyReferralCode` transaction (doc id = refereeUid, create-only). Reward inside `adminUpdateOrder` (→ delivered) with `users/{referrer}.referralRewards[yyyymm]`. | Function |
| COD needs `codEnabled` and total ≤ `codMaxPaise`. ≤ 2 unpaid online orders (`PENDING_LIMIT`). ≤ 10 lines, qty 1..5 | `placeOrder` (orders query inside the transaction). | Function |
| Cart ≤ 20 lines. Addresses ≤ 10, one default | `lines.size() <= 20`. Ids `a0`..`a9`. `defaultAddressId`. | Rules |
| Order state machine (incl. COD delivered → paid, cancelled+paid → refunded) | `orders/state.ts` transition table, used by `cancelOrder`, `adminUpdateOrder`, expiry and settlement. Restock on cancel. | Function |
| Repair state machine. Quote must be approved before in_progress/ready. `QUOTE_CHANGED`. ≤ 3 open per customer. Date today..+30 (IST) | `repairs/state.ts`. `bookRepair` transaction (open-repairs query). | Function |
| Payment idempotency. A late payment revives an expired order only if stock allows, else "needs refund" | `settleOnlinePayment` transaction: attempt state + order `paymentStatus` guard. COMPLETED counts only when the amount equals `totalPaise`. | Function |
| One refund in flight per order. Refund id = gateway idempotency key | `order.pendingRefundId` checked and set in the transaction. A retry asks the refund status first. | Function |
| Feedback once per order or repair, ≤ 10 per day, must link your own order or repair | Deterministic ids. `sendFeedback` transaction. | Function |
| Unique slugs, SKUs, coupon and referral codes, numbers | Doc ids / SKU query in the transaction / `promoCodes` / `referralCodes` / counters. | Function (+ Rules for slugs) |
| Input rules (phone, pincode, clean text, names, IMEIs, slugs, SKUs, routes) | zod for callables. The same regexes in Rules for C/St docs. Dart validators in `core/input.dart`. All three run `test-vectors/input.json`. | Both |
| Staff only | Claim `role` in Rules (`isStaff()`) and `requireStaff()` in callables. | Both |
| Hidden or personal codes not listable | `promotions` readable by staff only. `publicOffers` holds public offers only. Personal coupons sit under the owner's path. | Rules |

Rules sketch (the full file is deny-by-default and its tests port `rls.test.sql` and `attacks.test.sql`):

```
function isStaff() { return request.auth != null && request.auth.token.role in ['owner', 'staff']; }
function isMe(uid) { return request.auth != null && request.auth.uid == uid; }
match /orders/{id}  { allow read: if isStaff() || isMe(resource.data.uid); allow write: if false; }
match /variants/{id} { allow read: if isStaff() || (resource.data.isActive && resource.data.productActive); allow write: if false; }
match /carts/{uid}  { allow read, delete: if isMe(uid);
                      allow create, update: if isMe(uid) && request.resource.data.keys().hasOnly(['lines', 'updatedAt'])
                                             && request.resource.data.lines.size() <= 20; }
match /users/{uid}/notifications/{n} { allow read, delete: if isMe(uid);
                      allow update: if isMe(uid) && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['readAt']); }
```

List queries must carry the constraints Rules check, because Rules are not filters. Product-page variants query `isActive == true && productActive == true`. A cart whose item was hidden simply gets that line back missing, which is today's behaviour.

## 4. Auth

- **Providers:** Google and Phone in production. Email/password exists only in the Auth emulator, for the dev login buttons (`DEV_LOGIN`, emulator builds only).
- **Google:** `google_sign_in` 7 `authenticate()` → `GoogleAuthProvider.credential(idToken:)` → `signInWithCredential`. `displayName` → `fullName` when it passes `is_name` (else null, then we ask). `photoURL` → `photoUrl` (the avatar; phone users keep the generated avatar from `core/theme/generative.dart`).
- **Phone OTP:** `verifyPhoneNumber('+91' + 10 digits)`. Android auto-retrieval (SMS Retriever) and Play Integrity silent checks apply, with the reCAPTCHA fallback on phones without Play services. The OTP screen reuses `verify_code_screen.dart`/`otp_field.dart`. There is a 60 s resend timer, and `too-many-requests`/`quota-exceeded` errors are mapped in `errors.dart`.
- **Name capture:** a router guard sends any signed-in user whose `users/{uid}` is missing or has no `fullName` to a one-field Name screen, which creates or updates the doc. Google users usually skip it.
- **Staff:** custom claim `role`. Staff powers apply only in **Google + TOTP** sessions, because Firebase MFA does not support phone as the first factor (SECURITY §2.2). **First admin:** `claimOwner` succeeds once, only when no owner exists yet and the caller is signed in with Google + TOTP and has a linked, *verified* phone equal to `settings/business.phone` (+917987559272). Account shows "Set up as shop owner" only in that case. The owner then adds or removes staff by phone with `setRole` (a small Admin → Staff screen). No service-account keys ever sit on a laptop.
- **Account deletion:** `deleteAccount` keeps today's guard (`ACTIVE_ORDERS`: open orders or repairs, or a cancelled paid order not yet refunded). It sets `uid: null` on orders (kept for GST records), deletes the user's repairs and feedback, runs `recursiveDelete(users/{uid})` (addresses, notifications, coupons, wishlist), deletes `carts`, `devices`, `rateLimits` and `referralCodes`, then calls `auth.deleteUser`. The web route and data export are in SECURITY §4.6–4.7.
- **App Check:** Play Integrity in release and the debug provider in debug builds (debug tokens registered in the console). Ship with it unenforced and watch the App Check metrics for 7 days. Then enforce on Firestore, Storage and callables (`enforceAppCheck: true`). The webhook stays open: it has its own header check.
- **SMS abuse:** upgrade Auth to Identity Platform (free under 50k MAU) to get the **SMS region policy: allow India only**. App Check plus Firebase's per-IP limits cover the rest.
- **Test numbers** (console → Phone → test numbers, no SMS sent): `+91 99999 99999` / `123456` (dev), a demo customer and a demo staff number for `DEMO_BUILD`, and one kept permanently for the Play review account. Remove the rest before launch. The emulator accepts any number and shows the code in its UI and REST API.
- **Decisions in Phase 1 (A):** (1) *Staff TOTP on the emulator:* the Auth emulator can't do TOTP, so on the `demo-` project only an email/password (dev login) session counts as a staff session, in both `requireStaff` and Rules (`aud` must start with `demo-`); details in `firebase/README.md` "Staff on the emulator". (2) *App Check:* one switch, `ENFORCE_APP_CHECK` in `shared/options.ts`, false until the owner's 7-day watch ends; replay protection is on from the start; the flip is in `firebase/README.md` "Turning on App Check". (3) *Addresses* moved from C's Rules section to A's (with the account they belong to); `stateCode` must be the GST code of `state` (Rules), so the place of supply can't be faked. (4) `deleteAccount` deletes repairs and feedback and anonymises orders and their redemptions (SECURITY §4.6 wins over §1's "anonymises repairs"); staff accounts can't be removed through `adminDeleteAccount` (`setRole(null)` first). (5) Analytics and crash-report choices live on the phone (Telemetry), since collection must stop before any sign-in; `users.consent` stays the notice record.
- SPEC rule 8 (session in secure storage) is retired: Firebase Auth keeps its refresh token in app-private storage, and it can be revoked server-side (`revokeRefreshTokens`).

## 5. Money and payments

- **`quoteOrder({couponCode?, paymentMethod?})`** returns the same shape as `quote_order` (camelCase): subtotal, fee, discount, total, promotion, `couponError`, `couponErrorDetail`. It writes nothing except a failed-code entry in `rateLimits`.
- **`placeOrder({addressId, paymentMethod: 'online'|'cod', couponCode?, buyerGstin?})` → `{orderId}`.** One transaction, in this order: read `users/{uid}` (serialization), `carts/{uid}`, the variants, the address, `settings/store`, the code's `promoCodes` → promotion, the running automatic sales, the redemption, pending-order and first-order queries, and `counters/orders`. Then `pricing.ts` decides (a pure port of `price_lines` + `evaluate_promotion` + the discount split: by line total, rounding down, remainder to the largest line, ties to the lowest variant id). Then the writes: the order (with `reservedUntil` = now + 15 min for online), stock decrements (`lastStockChange: 'order'`), the redemption, promotion counters and mirrors, the cleared cart lines, and the counter.
- **`cancelOrder`, `adminUpdateOrder`, `adminSetImeis`, `expireUnpaidOrders`** port their SQL one for one (restock, COD delivered → paid, the cancelled+paid → refunded "Mark refunded", tracking-only edits adding a timeline note). Expiry processes each expired order in its own transaction.
- **Gateway: PhonePe Standard Checkout only.** It follows the PhonePe engineer's plan (`phonepe-plan.md`), mapped to Firestore:
  - `createPayment({orderId})` → `{merchantId, token, orderId: phonepeOrderId, env}`. Owner check, `pending_payment`, not expired. One attempt doc per merchantOrderId (`SM100001-xxxxxxxx`), at most one pending: an open one is checked with PhonePe first and its token handed out again. Amount = `totalPaise`. `expireAfter` = the time left on the hold, clamped to 300–3600 s.
  - `verifyPayment({orderId})`: the app always calls it after the SDK returns, whatever the SDK said. It asks PhonePe's order status API and runs `settleOnlinePayment`.
  - `phonepeWebhook` (`onRequest`): constant-time compare of `Authorization` with SHA-256(`user:password`). The body only names the order. The status is fetched again and settled. Idempotent.
  - `startRefund({orderId, itemIds?, restock?})` (staff): amounts come from the order (`admin_start_refund` rules). Refund doc id = `merchantRefundId`. A retry asks the refund status first. `pg.refund.completed/failed` webhooks and polling call `settleRefund`. Staff "Mark refunded" stays for cash and UPI refunds.
  - Contract between C and D: D owns `src/payments/**` (`gateway.ts` interface `{createOrder, orderStatus, refund, refundStatus}`, `phonepe.ts`, a fake for tests). C owns `orders/settlement.ts` and exports `settleOnlinePayment(tx, orderId, {merchantOrderId, transactionId, amountPaise, state})` and `settleRefund(tx, orderId, refundId, {state, gatewayRefundId, failure})`. Secrets: `PHONEPE_CLIENT_ID`, `PHONEPE_CLIENT_SECRET`, `PHONEPE_CLIENT_VERSION`, `PHONEPE_MERCHANT_ID`, `PHONEPE_WEBHOOK_USER`, `PHONEPE_WEBHOOK_PASSWORD` (`defineSecret`). Param `PHONEPE_ENV` = `SANDBOX`|`PRODUCTION`.
  - App: `PaymentGateway` interface with a `PhonePePaymentGateway` implementation (SDK init + `startTransaction`). `MainActivity` → `FlutterFragmentActivity`, plus the PhonePe maven repo and the `-keep com.phonepe.**` rule (from the plan).
- **Razorpay is not kept.** Instant refunds, payment links (until PhonePe grants Payment Links API access; staff use the PhonePe Business dashboard meanwhile), the EMI line, saved cards and dispute alerts (watch the dashboard's chargeback section) all go. `settings/store.onlinePaymentEnabled` is the server-enforced kill switch.

### Commerce decisions made in Phase 1 (engineer C)

The questions Phase 0 left open, settled in `src/orders`, `src/offers`, `src/referrals`:

- **Refunded total:** no field on the order. The processed docs under `orders/{id}/refunds` are the record; `settleRefund` and D's `planRefund` sum them inside their transactions (an order has at most a handful).
- **Refund pending state:** `settleRefund` with `state: 'pending'` records the gateway's `gatewayRefundId` and stays pending. That id is what "one refund in flight" (`REFUND_IN_PROGRESS`) keys on; a pending refund without it is retried with the same id.
- **Late payment reviving an expired order:** stock is taken again and the coupon use comes back (redemption active, `usesActive` +1), even past the usage limit, because the customer paid the discounted total. A cancel by the customer or staff is never revived: the order stays cancelled + paid (needs refund).
- **`expireUnpaidOrders` output:** `{expired: n}`, logged by the schedule. Each order expires in its own transaction (≤ 100 per run).
- **Mark refunded while a PhonePe refund is in flight:** refused with `REFUND_IN_PROGRESS` while `pendingRefundId` is set.
- **Failed codes at `placeOrder`:** they count toward the coupon rate limit (recorded in `rateLimits/{uid}.couponFails` after the checkout rolls back). A wrong referral code counts toward `applyReferralCode`'s limit the same way.
- **Per-user serialisation:** `rateLimits/{uid}` is read and written by `placeOrder` and `applyReferralCode` (their rate limits), which serialises them per user in place of writing `users/{uid}`.
- **`promoCodes` never client-readable:** Rules deny it, with `redemptions`, `referralCodes`, `counters` and `orders/*/payments`. Staff read `promotions` and `referrals`; everyone reads `publicOffers`; a customer reads only their own `users/{uid}/coupons`.
- **Per-user offer data:** not mirrored. The app derives it from the customer's own orders (readable under Rules): placed-an-order = any order not cancelled, uses of P = their non-cancelled orders whose `promotion.id` is P. `publicOffers.usedUp` covers the shop-wide limit. `quoteOrder` stays the source of truth.
- **Promotion ids:** UUIDs (`savePromotion`, referral coupons), so `/offers/{id}` banner links, `validation.ts bannerLink`, `input.json` and `app/lib/core/links.dart` keep their UUID pattern unchanged. A promotion's banner is `banners/{promotionId}`.
- **`adminSetImeis`:** the contract passes `imeis` through and the handler checks it against the line's qty after the staff and order checks, so the reason carries "need N distinct 15-digit IMEIs". `[]` clears.
- **`placeOrder` idempotency:** the cart is the key. The order and the emptied cart commit in one transaction, so a retried call after a lost reply fails `CART_EMPTY` instead of placing a second order; App Check's one-use token stops replays.
- **`deletePromotion`:** refused (`INVALID_PROMOTION`, detail `in use`) while any order that isn't cancelled used it; switch it off instead.

### GST tax invoices (Phase 2)

- **Product fields:** `hsnCode` (store 8 digits). Per Notification 78/2020-CT, shops with turnover up to ₹5 crore print at least 4 digits on B2B invoices. Defaults for the seed: smartphones `85171300`, other mobile phones `85171400`, chargers `85044030`, earphones/headsets `85183000`, power banks `85076000`, cables `85444299`, memory cards `85235100`, plastic cases `39269099`, screen guards `39199090`/`70071900`. All at **18%** (`gstRateBp: 1800`): mobile phones stayed at 18% through the 22 Sept 2025 rate rationalisation. Staff can edit both per product, and every value is reviewed by the shop's CA before go-live.
- **When:** the invoice is issued when an order moves to `shipped` (removal of goods), for COD and online alike. A trigger allocates the number in a transaction only if `order.invoice` is absent, renders the PDF, uploads it to `invoices/{uid}/{orderId}.pdf`, and sets `order.invoice`. The customer and staff download it from the order screen (Storage Rules: owner or staff).
- **Number:** `SOS/26-27/00001`, 15 characters. CGST Rule 46(b) allows at most 16 characters of letters, digits, `-` and `/`, unique per financial year. `counters/invoice-<FY>`, with the FY running April–March in IST.
- **Place of supply** is the delivery address state. Addresses already pick from the 36 states (`address_form.dart`), and `stateCode` is added from a shared GST state-code table (Dart + TS). State code 23 (= supplier `settings/business.stateCode`) gives **CGST + SGST**; any other state gives **IGST**.
- **Back-calculation**, integer paise, per line. Line value V = unitPrice × qty − line discount (GST-inclusive; the discount is shown on the invoice, so it lowers the taxable value). Rate r in basis points. `taxable = floor((2·V·10000 + (10000 + r)) / (2·(10000 + r)))` (round half up to the paisa), `tax = V − taxable`. Intra-state: `cgst = floor(tax / 2)`, `sgst = tax − cgst`. Inter-state: `igst = tax`. Delivery becomes its own line at the principal (highest-value) line's rate, as part of a composite supply. Invoice total = Σ lines = `order.totalPaise` exactly, and a unit test asserts this over all vectors.
- **B2B:** an optional "GSTIN for business purchase" at checkout (format + mod-36 checksum in zod and Dart) and a legal name, stored as `order.buyer`. They are printed so the buyer can claim input tax credit.
- **PDF:** `pdfkit` with bundled Noto Sans and Noto Sans Devanagari. A golden test covers a Hindi buyer name. Content: Rule 46 fields from `settings/business` and the order, reverse charge "No", an authorised-signatory line. Out of scope, flagged for the CA: e-invoicing (IRN, only above ₹5 crore turnover), credit notes for post-delivery refunds, and repair (SAC 9987) invoices.

## 6. Notifications, referrals, expiry, feedback, telemetry

- **Notices:** `notifications/notices.ts` exports pure `orderNotices(before, after)`, `repairNotices(...)`, `feedbackNotices(...)`, `couponNotice(...)`, `stockNotice(...)` and `refundNotice(...)`. They return `{recipient: uid|'staff', kind, title, body, link, orderId?, repairId?, imagePath?}[]`, with every kind, title and body ported verbatim from `20261030000400/0500/0510/0600` (staff are never told about their own action: `events[].byUid`). The vectors come from `notifications.test.sql` and `notification_images.test.sql`. Triggers: `onDocumentWritten` on `orders/{id}`, `repairs/{id}`, `feedback/{id}`, `orders/{id}/refunds/{rid}`. `onDocumentCreated` on `users/{uid}/coupons/{id}`. `onDocumentUpdated` on `variants/{id}` (low stock only when `lastStockChange == 'order'` and stock crosses ≤ 3 or hits 0). Ids are deterministic (`<sourceId>_<eventIndex>_<kind>_<recipient>`) and written with `create()`, so retries never duplicate (`retry: true`).
- **Push:** `onDocumentCreated('users/{uid}/notifications/{id}')` (`retry: false`: a missed push is acceptable because the in-app copy exists) → devices by uid → `sendEach` data-only, `android.priority: 'high'`, data `{id, kind, title, body, link, image_path}` (today's keys). Unregistered tokens are deleted. The app builds the image URL from Storage instead of the Supabase URL (`publicImageUrl`).
- **Back-in-stock alerts** (owner feature, engineer D):
  - *Marking.* Hearting a sold-out item writes `users/{uid}/wishlist/{productId}` with `waitVariant` set to the selected variant when that variant is sold out, or `'*'` when every variant is. Hearting an in-stock item leaves it `null`. The app says "Saved. We'll tell you when it's back in stock." The product page's sold-out bar (`_SoldOutBar`) gets a **Notify me** action that does the same, adding to the wishlist or setting the mark on an existing entry. Rules: owner only, keys `productId`/`addedAt`/`waitVariant`, `waitVariant` a variant id, `'*'` or null.
  - *Restock.* Every stock change goes through B's `catalog/stock.ts` `applyStockChange(tx, …)`, which sets `lastStockChange` and bumps `restockSeq` when stock goes 0 → > 0. This covers `setStock`, `saveProduct`, and C's restocks on cancel, expiry and refund.
  - *Notify.* `onDocumentUpdated('variants/{id}')` (D) fires when `before.stock == 0 && after.stock > 0` and the variant and product are active. It pages the collection-group query `wishlist where productId == P and waitVariant in [variantId, '*']` 200 at a time with `BulkWriter`. For each match it skips users with `prefs.backInStock == false`, writes the notification `users/{uid}/notifications/bis_{variantId}_{restockSeq}` with `create()`, so one restock never notifies anyone twice, retries included. In the same batch it clears `waitVariant` to `null`.
  - *Content.* Kind `back_in_stock`, title "Back in stock: {productName}", body "{variantName} is available again. Tap to buy before it sells out.", `imagePath` the product cover. The link is `/product/{slug}?variant={variantId}`; D adds the `variant` query parameter to the product route, and B reviews. The existing push trigger sends it like any order update.
  - Removing the heart deletes the doc, so the alert stops. A re-stock before the trigger runs is fine: the next 0 → > 0 bumps `restockSeq` again.
- **Referral reward** on delivery happens in the `adminUpdateOrder` transaction (§3), not in a trigger, so it is exactly once.
- **Expiry:** `onSchedule({schedule: 'every 5 minutes', timeZone: 'Asia/Kolkata'})`. Cleanup is TTL only.
- **Feedback:** `sendFeedback` (ownership, 10 per day, re-rating replaces and resets to `new`). Staff mark seen or resolved and add a note under field-limited Rules.
- **Phase 1 decisions (D):**
  - Payments keep their pure `flows.ts` and `PaymentError`; `handlers.ts` maps it to the `fail()` shape. `PAYMENT_IN_PROGRESS` (a second tap while the PhonePe order is being made) reaches the app as `GATEWAY_ERROR`; `REFUND_NOT_ALLOWED`/`REFUND_REFUSED` keep their staff copy in the message.
  - D writes `refunds/{id}.gatewayRefundId` when PhonePe accepts a refund (pending); `settleRefund` is called only for completed/failed. A pending refund with that id makes the next Refund tap `REFUND_IN_PROGRESS`; one without it is retried with the same id (settlement.json). Refund docs carry `itemIds`.
  - Repairs: quotes may be ₹0 (as the SQL allowed). A booking date outside IST today..+30 is `BAD_REQUEST` (detail `preferredDate`). No staff walk-in booking callable (not in the contract).
  - Notification ids: `<sourceId>_<key>_<kind>_<uid>`, key = event index, `p<n>` for a payment/tracking change, `r<refundId>`, `s<eventId>` for stock; one atomic batch of `create()`s per trigger run. Feedback keys on the doc's update time, so a re-rating notifies again. Back-in-stock ids are `bis_<variantId>_<restockSeq>` under each user; opted-out users keep their mark.
- **Analytics** (GA4, through `Telemetry`): `view_item_list` (home rails, search results), `search`, `view_item`, `add_to_wishlist`, `add_to_cart`, `remove_from_cart`, `view_cart`, `begin_checkout`, `add_shipping_info`, `add_payment_info`, `purchase` (after COD placement or `verifyPayment` = paid; `transaction_id` = order number, `value` in rupees, `coupon`), `view_promotion`/`select_promotion` (banners), `login`/`sign_up` (`method`: google|phone), plus custom `book_repair`, `apply_referral`, `send_feedback`. Collection is **opt-in** (SECURITY §4.2–4.3). There is no user id, no PII, and `search` sends a result count rather than the term. Google signals and ad personalisation are off.
- **Crashlytics:** `FlutterError.onError` and `PlatformDispatcher.onError` go to Crashlytics. Unexpected errors behind `friendlyError` are logged as non-fatal. There is no user identifier. Custom keys come from an allowlist: `build`, `backend`, `route`. Release builds use `--obfuscate --split-debug-info`, and the Dart symbols are uploaded with `firebase crashlytics:symbols:upload`.
- **Remote Config** is for client-only presentation, never for business rules (those live in `settings/store`, enforced by the server): `min_supported_build` (force-update screen) and `notice_banner` (maintenance text). Fetch interval 12 h, with in-app defaults.

## 7. Phases and the work split

| Engineer | Owns (files/folders) |
|---|---|
| **A, Platform and identity** | `firebase/firebase.json`, `.firebaserc`, `functions/{package.json,tsconfig.json,eslint.config.mjs,vitest.config.ts}`, `src/index.ts`, `src/shared/**`, `src/model/users.ts`, `src/account/**`, Rules sections `users`/`devices`, CI. App: `lib/core/{backend,firebase,callable}.dart`, `firebase_options.dart`, `features/auth/**`, `features/account/data/**`, `core/push.dart` (registration), Telemetry, Remote Config, App Check. Phase 2: Supabase removal. |
| **B, Catalog and storage** | `src/catalog/**` (incl. `stock.ts` `applyStockChange`, the only stock writer, used by C), `src/model/{catalog,settings}.ts`, `storage.rules`, Rules sections `catalog`/`settings`/`banners`/`collections`, `firebase/seed/**`. App: `features/catalog/data/**`, `wishlist/data/**`, `admin/data/{catalogue,photos,rules}.dart` + product, banner and settings admin repositories, the `publicImageUrl` change. |
| **C, Commerce (money)** | `src/orders/**`, `src/offers/**`, `src/referrals/**`, `src/model/{orders,offers}.ts`, Rules sections `carts`/`addresses`/`orders`/`offers`, `test-vectors/{pricing,offers,referrals,orders-state}.json`. App: `features/{cart,checkout,orders,offers}/data/**`, `admin/data/{admin,offers_admin}.dart` (orders and offers parts). |
| **D, Payments and service** | `src/payments/**` (PhonePe), `src/notifications/**` (incl. `backInStock.ts`), `src/repairs/**`, `src/feedback/**`, `src/invoices/**` (Phase 2), `src/model/{repairs,feedback,notifications}.ts`, Rules sections `repairs`/`feedback`/`notifications`/`wishlist`, the collection-group `wishlist` index, vectors `{repairs-state,notifications,gst}.json`. App: `features/{payments,repairs,feedback,notifications}/data/**`, `PaymentGateway`, back-in-stock: `wishlist_repository` `notifyWhenBack()`, the product page **Notify me** action and the snackbar copy, the `?variant=` route param (B reviews the catalog and wishlist files). |

Shared files: `firestore.rules` is one file split into commented sections. Each owner edits only their section, and A reviews. `src/index.ts` gets one `export *` line per domain in Phase 0 and is never touched again. `firestore.indexes.json` changes come only with the query that needs them.

**Phase 0: contracts (3 days, everyone, A leads).** (1) This document reviewed. (2) `src/model/*.ts` (the §3 shapes as TS types) and `src/<domain>/contract.ts` (zod in/out for every callable named in §1). (3) Dart repository interfaces with method signatures, plus fakes in `app/test/fakes/`. (4) The error reasons stay the current `_codes` keys. (5) `test-vectors/*.json` ported from pgTAP/api_e2e, cases first and code later. (6) `firebase/` scaffold that builds, lints and deploys an empty `health` callable to the emulator. (7) The owner actions in §9, in parallel.

**Phase 1: build on the emulators (about 3 weeks, in parallel).** Every engineer starts with a behaviour-neutral refactor: today's Supabase queries move into `*_repository_supabase.dart` behind the interface, and `flutter test` stays green on `BACKEND=supabase`. Then each domain lands as functions, then Rules, then tests (unit → rules → integration), then the Firebase repository, run with `BACKEND=firebase USE_EMULATORS=true`. Milestones: **M1** sign-in + browse (A, B; end of week 1, others build on the seed). **M2** cart + COD checkout + orders + offers (C). **M3** PhonePe sandbox payment and refund on a real phone (D + C). **M4** notifications/push, repairs, feedback, **back-in-stock alerts** (D; needs B's `applyStockChange`). **M5** admin parity: every admin screen works on Firebase (B, C, D).

**Cut-over (end of Phase 1; the app works at every step).**
1. The emulator integration suite (the `api_e2e.py` port) and all app tests pass with `BACKEND=firebase`.
2. `firebase deploy --only firestore:rules,firestore:indexes,storage,functions` to `shyam-mobiles`. Set the secrets and the PhonePe sandbox webhook URL.
3. Data: production holds only demo data and brand photos. `seed/import-supabase.ts` reads the production catalogue, offers, banners and settings through PostgREST with the secret key (in `~/.config/shyam-mobiles/supabase-prod.env`, never committed) and writes them with the Admin SDK, keeping slugs as ids. `seed/copy-photos.ts` copies every referenced object from the public Supabase bucket to Firebase Storage under the same keys. Users, orders and repairs are not migrated (demo only). Staff sign in again and claim the owner role.
4. The default flips to `BACKEND=firebase`. The release goes to Play internal testing, then a full manual pass (FLOWS.md), then production. Rollback is the previous Supabase build's AAB. The Supabase project is paused (not deleted) for 30 days.

**Phase 2: GST invoices + removal (about 2 weeks, in parallel).** D builds invoices (B adds HSN to product edit, C the checkout GSTIN field; the CA reviews sample PDFs before it is switched on). A removes Supabase: `supabase/`, `scripts/{api_e2e,dev_setup,demo_deploy,launch}.py` (replaced by `firebase/` scripts), `seed_photos.py` (retargeted to Storage), every `*_repository_supabase.dart`, `core/supabase.dart`, `backend.dart`, the `supabase_flutter`/`razorpay_flutter`/`flutter_secure_storage` dependencies, `SUPABASE_*`/`RAZORPAY_*` env keys, the CI backend job, `docs/RAZORPAY.md`. SPEC.md (Stack, Security rules, Data model, RPC contract → "Callable contract", Notifications), COSTS.md and LAUNCH.md are rewritten. Then the Supabase project is deleted and Pro cancelled.

## 8. Local development (8 GB RAM Mac)

- **Node:** nvm has v20.18.1 (still the default, for other tools) and v22.23.4; run `nvm use` in `firebase/functions`. `firebase-tools` 15 accepts Node ≥ 20, but `firebase-admin` 14 and vitest 5 need Node ≥ 22 and the deploy runtime is `nodejs22`. `firebase/.nvmrc` pins 22.
- **CLI:** `npm i -g firebase-tools` under Node 22 (15.34.2, installed) and `firebase login` (the owner's step). Java 22 is already installed; CLI 15's Firestore emulator needs Java ≥ 21.
- **Emulator suite replaces Colima + the Supabase stack:** `firebase emulators:start --only auth,firestore,functions,storage --project demo-shyam-mobiles --import .emulator-data --export-on-exit`. The `demo-` project id means nothing real can be touched and no credentials are needed. Ports: auth 9099, firestore 8080, functions 5001, storage 9199, UI 4000. Run with `JAVA_TOOL_OPTIONS=-Xmx512m` for the Firestore JVM. The expected total is about 1–1.3 GB, against the 3 GB Colima VM today. `npm run seed:emulator` loads `seed/dev.json`, the two dev logins and the brand photos. `colima delete` after Phase 2.
- **App against the emulators:** `flutter run --dart-define=BACKEND=firebase --dart-define=USE_EMULATORS=true`. On a USB phone, `adb reverse tcp:9099 tcp:9099` (same for 8080, 5001, 9199) lets the app use `127.0.0.1`. The emulator image uses `10.0.2.2`.
- **One heavy command at a time:** never run emulators, `flutter test` and a Gradle build together. Scripts: `npm test` (vitest, no emulator, one fork via `vitest.config.ts`; vitest 5 has no `poolOptions`), `npm run test:rules` (`firebase emulators:exec --only firestore,storage "vitest run test/rules"`), `npm run test:int` (`firebase emulators:exec --only auth,firestore,functions,storage "vitest run test/integration"`), `flutter test test/features/<one>`.
- **CI:** GitHub Actions job `firebase`: Node 22, Java 21, `npm ci`, lint, `tsc --noEmit`, unit, then rules and integration through `emulators:exec`. The `app` job stays as it is.

## 9. Costs, and what the owner does

| Item | Today (Supabase) | Firebase Blaze |
|---|---|---|
| Platform base | Supabase Pro $25/mo ≈ ₹2,200 | ₹0 (pay as you go) |
| Phone OTP SMS | MSG91 ₹0.30/SMS + DLT ≈ ₹5,900/yr (not live yet) | **$0.07 per SMS to India (≈ ₹6.2 at ₹88/$), first 10 SMS a day free** (Identity Platform pricing, checked 2026-11-03). No DLT registration by the shop: Google sends from its own sender (confirm on the first test SMS). |
| Auth MAU | in Pro | ₹0 up to 50,000 MAU after the Identity Platform upgrade |
| Firestore | in Pro | Free daily: 50k reads, 20k writes, 20k deletes. Free total: 1 GiB stored, 10 GiB/month egress. Launch stays inside it. "Growing" is estimated under $1/mo. |
| Functions | in Pro | 2M invocations/month free plus compute free tier. Expected ₹0. Set an Artifact Registry cleanup policy (`firebase functions:artifacts:setpolicy`). |
| Cloud Scheduler | pg_cron | 1 job, inside the 3 free jobs per billing account ($0.10/job/month after) |
| Storage (asia-south1) | in Pro | **No free tier outside US regions** for new buckets. About 1 GB of photos costs pennies; image egress is about $1–6/mo at 10–50 GB (re-check the Cloud Storage price list). |
| FCM, Analytics, Crashlytics, Remote Config, App Check (Play Integrity, 10,000 calls/day standard tier) | — | ₹0 |
| Secret Manager | Edge secrets | 6 secrets at a few cents a month |

SMS is now the one cost that grows. Sessions persist until sign-out, so a phone user pays one SMS per new device, not per visit. **Lever:** if SMS spend passes ₹3,000/month, move phone OTP to MSG91 (₹0.30) through a custom-token function. Google sign-in is shown first. The total is about ₹250–1,000/mo at launch against ₹2,200 today, before PhonePe fees (D updates COSTS.md with the PhonePe rate card).

**Owner actions, in order:**
1. Firebase console → project `shyam-mobiles` (the one FCM uses) → **Upgrade to Blaze** → link a billing account → Billing → Budgets & alerts → budget **₹1,000/month**, alerts at 50/90/100% to your email. Alerts do not stop spending.
2. Build → **Firestore** → Create database → Standard edition, **location asia-south1 (Mumbai)**, production mode. *The location cannot be changed later.* Then turn on daily backups (7-day retention) before the first real order.
3. Build → **Storage** → Get started → location **asia-south1**.
4. Build → **Authentication** → Sign-in method → enable **Google** (support email) and **Phone**. Add the test numbers from §4. Settings → **Upgrade to Identity Platform** (free under 50k MAU) → **SMS region policy: allow India only**.
5. Project settings → Android app → **add SHA-1 and SHA-256** for (a) the debug key (`keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`), (b) the upload key, and (c) **Play App Signing** (Play Console → Test and release → App integrity → App signing key certificate).
6. Play Console → App integrity → **Play Integrity API → link the Cloud project**. Firebase → **App Check** → register the Android app with Play Integrity.
7. Enable **Analytics** (GA4, turn off Google signals) and **Crashlytics**. Update the privacy policy (`firebase/hosting/`) and the Play **Data safety** form (crash logs, app interactions).
8. On the Mac: `nvm install 22`, `npm i -g firebase-tools`, `firebase login`, then `firebase use shyam-mobiles` in `firebase/`.
9. PhonePe Business dashboard: paste the test, then live, Client ID, Client Secret, Client Version and Merchant ID into `firebase functions:secrets:set …` (engineer D runs it with you). Set the webhook URL to the `phonepeWebhook` URL printed by deploy, with a username and password you choose.
10. After the first deploy: sign in on the app with **7987559272** and tap **Set up as shop owner**. Then add staff in Admin → Staff.
11. After cut-over is stable: pause, then 30 days later delete, the Supabase project and cancel Pro. Leave the Razorpay account dormant.

## 10. Risks and mitigations

Security and privacy risks, and their controls, are in [`docs/SECURITY.md`](SECURITY.md) (threat model §1, checklist §5).

| Risk | Mitigation |
|---|---|
| SMS price ($0.07) and SMS pumping | Google first, persistent sessions, 60 s resend timer, India-only region policy, App Check, budget alert. MSG91 custom-token fallback (§9). |
| Pricing or coupon regressions in the port | Vectors from pgTAP/api_e2e land before code. Property test: totals identity and discount split sum. Quote and place share one `pricing.ts`. |
| Catalog index outgrows 1 MiB | CI size test at 2× the seed. Warning log at 700 KB. Planned shard by category, then Typesense. |
| Hot documents (counters, catalog index) | Expected ≪ 1 write/s. Counters only inside transactions. Index triggers are idempotent and retried. |
| Triggers run at least once | Deterministic notification ids with `create()`. Invoice number allocated only if absent. Push not retried. |
| Rules, zod and Dart validators drift apart | One `test-vectors/input.json` run by all three suites. |
| Admin SDK bypasses Rules | Every server write goes through services with zod input, `assert*()` invariants and integration tests. |
| A Rules gap leaks data | Deny-by-default. The rules tests port `rls.test.sql`/`attacks.test.sql` (cross-user reads, staff-only collections, field-limited updates). |
| Cold starts at checkout | 2nd gen concurrency (80) keeps one warm instance per burst. Set `minInstances: 1` on `placeOrder`/`quoteOrder` only if p95 > 2 s (≈ $5/mo). |
| Region or provider lock-in, data loss | Region fixed by D1. Daily Firestore backups before launch. Seed and import scripts rebuild the catalogue. |
| GST compliance (HSN, rates, delivery line, signature) | Editable per product. The shop's CA signs off on sample invoices before Phase 2 goes live. E-invoicing (IRN) and credit notes are flagged as out of scope. |
| Hindi text in invoice PDFs | Noto Sans Devanagari with a golden test. |
| Data-only pushes dropped by aggressive OEM battery savers | As today: the in-app notification is the record. Add a `notification` block if field reports show misses. |
| Node 22 deprecation (2027-04-30). rules-unit-testing 6 needs Node 24.12 | Move to `nodejs24` and rules-unit-testing 6 together once the Firebase docs list Node 24, before April 2027. |
| Four engineers colliding | Phase 0 contracts, folder ownership above, Rules sections, `index.ts` frozen after Phase 0. |

## Sources (checked 2026-11-03)

- Identity Platform pricing (SMS India $0.07, 10/day free): https://cloud.google.com/identity-platform/pricing · SMS regions: https://cloud.google.com/identity-platform/docs/admin/sms-regions
- Firestore quotas and limits: https://firebase.google.com/docs/firestore/quotas · pricing: https://cloud.google.com/firestore/pricing
- Storage bucket changes (Blaze required, Always Free only in US-CENTRAL1/US-EAST1/US-WEST1): https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024
- Runtime support (nodejs20 decommissioned 2026-10-30, nodejs22 deprecates 2027-04-30): https://cloud.google.com/functions/docs/runtime-support · Firebase: https://firebase.google.com/docs/functions/manage-functions
- Cloud Scheduler pricing (3 free jobs per billing account): https://cloud.google.com/scheduler/pricing · App Check / Play Integrity quota: https://firebase.google.com/docs/app-check
- npm/pub.dev versions: registry.npmjs.org and pub.dev APIs (firebase-tools 15.34.2, firebase-functions 7.4.0, firebase-admin 14.5.0, @firebase/rules-unit-testing 6.0.0 needs Node ≥ 24.12, 5.0.1 needs Node ≥ 20)
- GST: CGST Rule 46 (invoice serial ≤ 16 characters, unique per FY); Notification 78/2020-CT (HSN digits): https://www.gstcouncil.gov.in/sites/default/files/2024-05/notfctn-78-central-tax-english-2020.pdf; phone and accessory rates at 18% after 22 Sept 2025: https://tallysolutions.com/gst/mobile-phones-and-accessories-hsn-code-gst-rate/, https://cleartax.in/s/gst-mobile-phones
- PhonePe PG v2 details: the PhonePe engineer's plan (`phonepe-plan.md`, 2026-11-03)
