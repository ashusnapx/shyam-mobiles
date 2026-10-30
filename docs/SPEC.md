# Shyam Mobiles — v1 spec

Single source of truth for everyone building v1. If code and this file disagree, fix one of them in the same change.

## Product

Android app for Shyam Mobiles, a phone shop. iOS comes later from the same Flutter codebase; v1 is designed, tested and shipped on Android only (minSdk 24, edge-to-edge, predictive back, Credential Manager sign-in, UPI intent payments).

- Customers: browse and search new phones and accessories, wishlist, cart, checkout (Razorpay or cash on delivery), track orders, book repairs.
- Staff: the same app shows an **Admin** tab when the signed-in user is in `admins`. Admins manage products/stock/images, move orders through fulfilment (with IMEIs), and handle repair bookings.
- Both: a notification for every step of an order, payment, repair, coupon and (staff) feedback and stock, in the app and, once Firebase keys are in, on the phone (see **Notifications**).

Not in v1 (on purpose): guest cart, reviews, store pickup, courier API, GST invoice PDF, Hindi UI, refurbished phones. The schema leaves room for each.

## Stack

| Layer | Choice |
|---|---|
| App | Flutter 3.47 (Dart 3.13), `material_ui` (Material, moved out of the SDK), Riverpod (`flutter_riverpod`), `go_router`, Material 3 with custom theme |
| Icons | `phosphor_flutter`, only this set; regular weight by default, fill for the selected state |
| Backend | Supabase: Postgres + row-level security, Auth, Storage, Edge Functions (Deno/TypeScript), `pg_cron` |
| Payments | Razorpay Standard Checkout (`razorpay_flutter`) + cash on delivery |
| Auth | Phone OTP, email OTP (6-digit code, no passwords, no magic-link deep links), Google (native `google_sign_in` + `signInWithIdToken`) |
| Infra / local dev | Supabase CLI migrations as code, local stack on Colima (Docker), Deno 2 for function tests |
| CI | GitHub Actions: `flutter analyze` + `flutter test`, `supabase test db`, `deno test` on every push |
| Store builds | Codemagic (macOS runners; this Mac has no full Xcode): signed AAB + IPA, uploads to Play and TestFlight |
| Monitoring (before launch) | Play Console Android vitals for crashes and ANRs (no SDK); Supabase logs and advisors for the backend |

## Money and numbers

- All money is **integer paise** (`*_paise` columns, `int` in Dart). Never use floats for money.
- Prices include GST. `gst_rate` is stored per product for future invoices, and copied to each order line.
- Delivery is free when the subtotal minus any discount is at or above `free_delivery_min_paise`, else `delivery_fee_paise`. COD needs `cod_enabled` and a **total** (subtotal + delivery − discount) at or below `cod_max_paise`. Every order satisfies `subtotal = Σ unit_price × qty`, `total = subtotal + delivery_fee − discount` and `discount = Σ line discount_paise` (see Offers).
- The display format is `₹1,29,999` (Indian grouping, no decimals unless paise != 0): `formatInr(int paise)` in `lib/core/format.dart`.

## Security rules (non-negotiable)

1. RLS is on for every table. Default deny. Every policy is tested in `supabase/tests`. Table privileges are explicit grants (`supabase/migrations/20261028000300_grants.sql`): `anon` has none on per-user tables, so reading them signed out fails with `42501` instead of returning no rows.
2. The client never sends a price or total. `place_order` computes everything from DB rows.
3. Clients never `update` `orders`, `order_items`, `payment_events` or `admins` directly. State changes go through RPCs that validate transitions.
4. Admin rights come only from the `admins` table, which no client role can write. `public.is_admin()` is the only check.
5. Every `security definer` function sets `search_path = ''` and uses fully-qualified names; `execute` is revoked from `public`/`anon` and granted only to the roles that need it.
6. Secrets (Razorpay key secret, webhook secret, Supabase secret key) live only in Edge Function secrets. The app binary holds only the Supabase URL, the publishable key (`sb_publishable_…`) and the Razorpay key id, all of which are public by design. No legacy `anon`/`service_role` JWT keys anywhere.
7. Razorpay signatures are verified with HMAC-SHA256 and a constant-time compare. The webhook verifies the raw body and dedupes on `x-razorpay-event-id`.
8. The app stores the auth session in `flutter_secure_storage` (Keychain/Keystore), not SharedPreferences.
9. Stock changes are atomic, take row locks, and never go negative (check constraint).
10. Account deletion works in the app (store requirement). Orders are kept for tax records with `user_id` set to null.
11. Sign-in is passwordless, enforced: an Auth access token hook (`private.custom_access_token_hook`) refuses every token from the password grant, refreshes included, and email and phone confirmations are on, so nobody can pre-register someone else's email or phone with a password. Only accounts on a domain in `private.password_sign_in_domains` may use one (the local dev logins; empty in production).

## Data model

Exact DDL: `supabase/migrations/20261028000000_schema.sql`. Summary:

- `profiles(id → auth.users, full_name, phone)`: created by a trigger on signup.
- `admins(user_id)`: staff list, service-role writes only.
- `categories(slug, name, kind 'phone'|'accessory', sort)`, `brands(slug, name)`.
- `products(slug, name, brand_id, category_id, description, specs jsonb (ordered array of {label, value}), gst_rate, is_active, is_featured, search tsvector)`.
- `product_images(product_id, path, sort)`: `path` is an object key in the public `product-images` bucket.
- `variants(product_id, sku, name, attributes jsonb, price_paise, mrp_paise, stock, is_active)`. Every product has ≥1 variant; cart/order lines point at variants.
- `product_cards` (view, `security_invoker`): one row per active product with `min_price_paise`, `mrp_paise` (of the cheapest variant), `in_stock`, `cover_path`, `brand_name`, `category_slug`. Listing/search screens read this.
- `wishlist(user_id, product_id)`, `cart_items(user_id, variant_id, qty 1..5)`: max 20 lines per user (`CART_LIMIT`), `addresses(user_id, name, phone, line1, line2, landmark, city, district, state, pincode, label 'home'|'work'|'other', is_default)`: max 10 per user, one default.
- `orders(number 'SM100001', user_id, status, payment_method, payment_status, subtotal/delivery_fee/discount/total paise, promotion_id, coupon_code, address jsonb snapshot, razorpay_order_id, razorpay_payment_id, courier, tracking_number, reserved_until)`.
- `order_items(order_id, variant_id, product_name, variant_name, unit_price_paise, qty, gst_rate, discount_paise, imeis text[])`: snapshot of what was sold.
- Offers tables (`collections`, `promotions`, `banners`, referrals…) and the new `store_settings` referral columns: see **Offers** below and `supabase/migrations/20261030000000_offers.sql`.
- `order_events(order_id, status, note, created_at)`: timeline shown to the customer.
- `payment_events(razorpay_event_id unique, type, payload)`: webhook audit + idempotency.
- `repair_bookings(number 'RP100001', user_id, device_brand, device_model, issue, description, preferred_date, slot, contact_phone, status, quote_paise, quote_status, quote_decided_at, admin_note)`: a customer has at most 3 open (not completed/cancelled) bookings (`REPAIR_LIMIT`); staff booking walk-ins are exempt. `quote_status`: `none` (no quote; exactly when `quote_paise` is null), `pending` (waiting for the customer), `approved`, `declined`; `quote_decided_at` is when the customer (or staff for them) answered. `admin_note` is legacy (copied into `repair_events`; no longer written).
- `repair_events(booking_id, status, quote_status, quote_paise, note, created_at)`: the repair timeline, shown to the customer and staff. A status change has `quote_status` null; a quote event (sent, approved, declined) has both `quote_status` and the amount; `note` is staff's note or the customer's decline reason. Written only by the RPCs and the booking insert trigger.
- `notifications(user_id, kind, title ≤ 80, body ≤ 300, link (app route), order_id, repair_id, read_at, created_at)` and `device_tokens(token pk, user_id, platform, updated_at)`: see **Notifications**.
- `store_settings` (single row): `delivery_fee_paise`, `free_delivery_min_paise`, `cod_enabled`, `cod_max_paise`, `store_phone`, `store_address`, `store_lat`/`store_lng` (the shop's map pin, both or neither; directions go to it, else to the address), `store_maps_url` (https, ≤500: the shop's Google Maps listing, linked to as "Photos, reviews & hours on Google Maps"; seeded with the `?cid=` link of "Shyam Mobile Center"), `store_photos text[]` (≤8 object keys `store/<millis>.<ext>` in the `product-images` bucket, in display order), `store_hours`, `repair_note`, `returns_policy` (placeholder text the owner must edit before launch).

### Input rules (enforced in the database; app limits are only a convenience)

- Phones: `+91` and 10 ASCII digits starting 6–9, nothing else (no spaces, no other digit scripts). Pincode: 6 ASCII digits, not starting 0. IMEIs: a flat list of distinct 15-digit values, one per unit of the line (or none yet).
- Typed text (`public.is_clean_text`): no control or invisible formatting characters (zero-width space, LRM/RLM, bidi overrides and isolates, word joiner, BOM, soft hyphen) and not whitespace-only; newlines only in multi-line fields (descriptions, notes, store address, repair note, returns policy). ZWJ/ZWNJ are allowed (Hindi typing uses them). Person and place names (profile name, address name, city, district, state) also need a letter in any script (`public.is_name`), so `😀😀` or `12345` is refused; a junk display name from sign-up is stored as null instead of failing the sign-up.
- Lengths as in the DDL, plus: slugs `[a-z0-9-]{1,160}`, SKUs ASCII `[A-Za-z0-9._/-]` up to 60 (no Unicode look-alikes), store address and repair note ≤ 300, image keys `<folder>/<name>.webp|jpg|jpeg|png`, shop photos `store/<millis>.<ext>`, Razorpay ids `[A-Za-z0-9_]{1,64}`, specs ≤ 20 kB, attributes ≤ 1 kB with `color_hex` as `#RRGGBB`.
- Numbers: prices > 0 (int paise), MRP ≥ price, stock 0–1,000,000, qty 1–5, GST 0–28, fees and limits ≥ 0. SQL-looking text is just text: every write is parameterised and stored verbatim.

### State machines

```
order.status:   pending_payment ─┬─> confirmed ─> packed ─> shipped ─> delivered
                                 └─> cancelled (expiry / user / admin)
                confirmed|packed ─> cancelled          delivered ─> refunded (admin, after refund)
payment_status: pending ─> paid ─> refunded ;  pending ─> failed (stays retryable until expiry)
repair.status:  requested ─> confirmed ─> in_progress ─> ready ─> completed ; any open ─> cancelled (staff)
                requested|confirmed ─> cancelled (customer)
quote_status:   none ─> pending ─> approved | declined ;  any ─> pending (staff send or change the quote)
                in_progress and ready need quote_status = approved
```

- COD orders start `confirmed` with `payment_status = pending`. They become `paid` when the admin marks them `delivered`.
- Razorpay orders start `pending_payment` and hold their stock until `reserved_until` (now + 15 min). A `pg_cron` job cancels expired ones and puts the stock back.
- If a payment lands on an order that already expired, `mark_order_paid` tries to re-reserve the stock. If it can't, the order stays `cancelled` with `payment_status = paid`, and the admin dashboard lists it as **needs refund**.
- Customers book repairs with a plain `insert` of `user_id, device_brand, device_model, issue, description, preferred_date, slot, contact_phone` (RLS: own `user_id`, `status = requested`, no `quote_paise`/`admin_note`, `preferred_date` from today to today + 30 in IST; `id`, `number` and timestamps are never client-set) and cancel via `cancel_repair`. Nobody updates `repair_bookings` directly (no UPDATE grant): staff move a booking with `admin_update_repair` and quote with `admin_set_repair_quote`; the customer answers a quote with `approve_repair_quote` / `decline_repair_quote`. Every change writes a `repair_events` row. Staff may quote while a booking is requested, confirmed or in repair; changing it mid-repair makes it pending again, so the repair can't be marked ready until the customer approves the new price. After a decline staff quote again or cancel; the customer can still cancel while requested/confirmed. A quote given in person or on the phone is recorded by staff with `p_approved` ("Agreed with the store.").

## RPC contract (called by the app via `supabase.rpc`)

Errors are raised exceptions with `errcode 'P0001'` and `message` = a bare code (detail, if any, in `details`). Codes: `CART_EMPTY`, `ADDRESS_NOT_FOUND`, `OUT_OF_STOCK`, `COD_UNAVAILABLE`, `NOT_FOUND`, `INVALID_TRANSITION`, `FORBIDDEN`, `INVALID_IMEIS`, `ADDRESS_LIMIT` (address insert trigger: max 10 per user), `CART_LIMIT` (cart insert trigger: max 20 lines; `place_order`: max 10 lines), `REPAIR_LIMIT` (repair insert trigger: max 3 open), `QUOTE_NOT_APPROVED` (a repair can't start or be ready before the customer approves the current quote), `QUOTE_CHANGED` (the customer approved an amount that is no longer the quote), `BAD_REQUEST`, `PENDING_LIMIT`, `ORDER_TOO_LARGE`, plus the Offers codes (`COUPON_*`, `REFERRAL_*`, `INVALID_PROMOTION`, `CODE_TAKEN`; see Offers → Errors). Calling a function your role may not execute gives `42501`.

| Function | Caller | Does |
|---|---|---|
| `is_admin() → bool` | authenticated | Whether the caller is staff. |
| `place_order(p_address_id uuid, p_payment_method payment_method, p_coupon_code text default null) → uuid` | authenticated | Reads the caller's cart, locks its lines and variants (only those locked lines are ordered: a line added while it runs stays in the cart), checks stock and active flags, prices it with the shared Offers pricing (code or best automatic sale; a bad code raises its `COUPON_*` error), applies the COD rules to the discounted total, creates the order, items and first event, decrements stock, clears the cart. Errors: `CART_EMPTY`, `ADDRESS_NOT_FOUND`, `OUT_OF_STOCK` (also for inactive variants/products; `details` = comma-separated variant ids), `COD_UNAVAILABLE` (COD disabled or total > `cod_max_paise`), `CART_LIMIT` (more than 10 lines), `PENDING_LIMIT` (an online order while the caller already has 2 unpaid online orders whose hold hasn't expired; COD is not capped), `ORDER_TOO_LARGE` (subtotal + delivery beyond what int paise can hold, ₹2,14,74,836.47), `COUPON_*`. Writes `discount_paise`, `promotion_id`, `coupon_code`, each line's `discount_paise` and the redemption. `address` snapshot keys: `name, phone, line1, line2, landmark, city, district, state, pincode` (`district` may be null). |
| `cancel_order(p_order_id uuid) → void` | authenticated (owner) | Allowed while `pending_payment` or `confirmed`. Restocks. A paid order cancelled here shows up as **needs refund**. |
| `cancel_repair(p_booking_id uuid) → void` | authenticated (owner) | Allowed while `requested` or `confirmed`. Event note "Cancelled by you." |
| `approve_repair_quote(p_booking_id uuid, p_quote_paise int) → void` | authenticated (owner) | Only while `quote_status = pending` and the booking is requested/confirmed/in_progress (else `INVALID_TRANSITION`; not the caller's: `NOT_FOUND`). `p_quote_paise` is the amount the customer saw; anything else is `QUOTE_CHANGED`. Sets `approved`, `quote_decided_at`, writes the event. |
| `decline_repair_quote(p_booking_id uuid, p_reason text default null) → void` | authenticated (owner) | Same rules, no amount check. Sets `declined`; the reason (≤500, optional) is the event's note. |
| `admin_update_repair(p_booking_id uuid, p_status repair_status, p_note text default null) → void` | admin | Transitions: requested→confirmed→in_progress→ready→completed, and requested/confirmed/in_progress/ready→cancelled; anything else `INVALID_TRANSITION` (detail `from -> to`). in_progress and ready need an approved quote (`QUOTE_NOT_APPROVED`, detail = the quote status). `p_status` = current status only adds `p_note` as an event (no note: nothing happens). A cancel without a note gets "Cancelled by the store." |
| `admin_set_repair_quote(p_booking_id uuid, p_quote_paise int, p_note text default null, p_approved boolean default false) → void` | admin | Sends or changes the quote (0..₹10,00,000, else `BAD_REQUEST`) while requested/confirmed/in_progress (else `INVALID_TRANSITION`). Sets `pending`, or `approved` with `p_approved` (the customer agreed in person or on the phone; note defaults to "Agreed with the store."). Writes the quote event. |
| `admin_update_order(p_order_id uuid, p_status order_status, p_note text, p_courier text, p_tracking_number text) → void` | admin | Validates the transition, writes an event, restocks on cancel, marks COD paid on delivered; `refunded` also sets `payment_status = refunded`. On a cancelled order that was paid (needs refund), `p_status = refunded` only sets `payment_status = refunded` (status stays `cancelled`, so its coupon use stays given back) with the note "Refund issued…": for refunds the webhook didn't report (partial, cash, UPI); unpaid: `INVALID_TRANSITION`. `p_status` = current status just updates courier/tracking (null keeps the old value) and adds a note event: `p_note`, or "Courier and tracking updated: <courier> · <tracking>" when they changed. |
| `admin_set_imeis(p_order_item_id uuid, p_imeis text[]) → void` | admin | A one-dimensional array; count must equal qty; each value 15 digits; no duplicates. Else `INVALID_IMEIS`. |
| `admin_catalogue(p_query text, p_category_id uuid, p_brand_id uuid, p_stock text all/low/out, p_visibility text all/shown/hidden, p_sort text name/stock/price/updated, p_offset int, p_limit int 1..100) → json` | admin | One page of the admin catalogue: `{rows: [{variant_id, product_id, product_name, variant_name, sku, price_paise, mrp_paise, stock, variant_active, product_active, featured, category_id, brand_id, updated_at, cover_path}], summary}`; `summary` = `{skus, units, value_at_price_paise, value_at_mrp_paise, low, out, total_skus}` over every matching row, on the first page (`p_offset = 0`) only, else null. Search matches product name, variant name or SKU (plain text, no wildcards). Errors `FORBIDDEN`, `BAD_REQUEST`. |
| `send_feedback(p_kind feedback_kind general/order/repair/product/bug, p_rating int 1..5 or null, p_message text ≤ 1000, p_order_id, p_repair_id, p_product_id, p_screen text (route it was sent from), p_app_version text) → uuid` | authenticated | Saves feedback: a rating, a comment, or both. The order or repair must be the caller's. Rating the same order or repair again replaces it and marks it new. At most 10 a day (`FEEDBACK_LIMIT`); order/repair/product feedback without its id is `BAD_REQUEST`. Deleting the order, repair or product later keeps the feedback, unlinked. Customers read their own rows; staff read all and update `status` (new/seen/resolved) and `admin_note` on the `feedback` table. |
| `admin_dashboard() → json` | admin | `{orders_today, revenue_today_paise, open_orders, low_stock, open_repairs, repairs_awaiting_approval, needs_refund}`, all integers. Today = IST calendar day, orders in confirmed/packed/shipped/delivered. `open_orders`: confirmed/packed/shipped. `low_stock`: active products with an active variant at stock ≤ 3 (what the Products low-stock list shows). `open_repairs`: not completed/cancelled. `repairs_awaiting_approval`: open with `quote_status = pending`. `needs_refund`: `status = cancelled and payment_status = paid`. |
| `mark_order_paid(p_order_id uuid, p_razorpay_payment_id text) → void` | service_role only | Idempotent. Used by the Edge Functions. A late payment revives an *expired* order if stock allows; a customer/admin-cancelled order is never revived (→ needs refund). |
| `mark_payment_failed(p_order_id uuid) → void` | service_role only | From the `payment.failed` webhook: `pending → failed`, order stays payable until expiry. |
| `mark_order_refunded(p_razorpay_payment_id text) → void` | service_role only | From the `refund.processed` webhook (full refunds only): `payment_status = refunded`. |
| `expire_unpaid_orders() → int` | `pg_cron`, every 5 min | Cancels `pending_payment` orders past `reserved_until`, restocks. |
| `unread_notifications() → int` | authenticated | The caller's unread count (the bell). |
| `mark_notifications_read(p_ids uuid[] default null) → void` | authenticated | Sets `read_at` on those of the caller's notifications (null: all of them). Someone else's ids are ignored. |
| `register_device(p_token text) → void` | authenticated | Saves this phone's FCM token for the caller (20–1000 of `[A-Za-z0-9_:-]`, else `BAD_REQUEST`; signed out: `FORBIDDEN`). A token another account had moves to the caller; each user keeps their newest 10. |
| `quote_order`, `available_offers`, `offers_for_product`, `offer_products`, `my_referral`, `apply_referral_code`, `admin_save_promotion`, `admin_promotions` | see Offers → RPCs | |

## Edge Functions (`supabase/functions/*`)

All are `POST`. User functions keep the platform `verify_jwt` check and verify the user JWT again in code (`@supabase/server`, JWKS). A request with no `Authorization` header is refused by the platform with a 401 whose body is `{"msg": "..."}`, not the shape below; treat every 401 as `UNAUTHORIZED`. Errors: JSON `{"error": "<CODE>", "message": "<short human text>"}` with a matching status: 400 `BAD_REQUEST`/`BAD_SIGNATURE`, 401 `UNAUTHORIZED`/`BAD_SIGNATURE` (webhook), 404 `NOT_FOUND`, 409 `ORDER_NOT_PAYABLE`/`ORDER_EXPIRED`/`PAYMENT_MISMATCH`/`ACTIVE_ORDERS`, 502 `GATEWAY_ERROR` (Razorpay unreachable or erroring), 500 `INTERNAL`.

| Function | Auth | Body → Response |
|---|---|---|
| `create-payment` | user JWT | `{order_id}` → `{key_id, razorpay_order_id, amount, currency, order_number, reserved_until}` (`reserved_until`: ISO 8601 UTC, when the stock hold ends; set Razorpay's checkout `timeout` from it). Reuses an existing `razorpay_order_id`. Refuses unless the order is the caller's, `pending_payment`, `razorpay`, and not expired. |
| `verify-payment` | user JWT | `{razorpay_order_id, razorpay_payment_id, razorpay_signature}` → `{order_id, status}`. Checks the HMAC, fetches the payment from Razorpay (order id, amount = total, status captured/authorized), then calls `mark_order_paid`. `status` is the order status afterwards (`confirmed`, or `cancelled` if it was paid too late). |
| `razorpay-webhook` | none (`verify_jwt = false`), HMAC instead | Handles `payment.captured`, `order.paid`, `payment.failed`, `refund.processed`. Verifies `x-razorpay-signature` over the raw body (401 if bad), dedupes on `x-razorpay-event-id` via `payment_events`, checks amount = order total. `refund.processed` counts as full only when the event's payment has `amount_refunded ≥ amount`; anything else (a partial refund, missing totals) is left for staff. Returns 200 on duplicates, unknown events/orders and business refusals; 500 only on infrastructure errors (Razorpay retries). |
| `delete-account` | user JWT | `{}` → 204. Returns 409 `ACTIVE_ORDERS` if any order is not delivered/cancelled/refunded, any cancelled order is still owed a refund (`payment_status = paid`), or any repair is not completed/cancelled. Otherwise deletes the auth user (cascades the profile, cart, wishlist, addresses; orders keep `user_id = null`). |

| `send-push` | none (`verify_jwt = false`), `x-push-secret` = `PUSH_SECRET` instead | Called by the database (pg_net) for each new notification of a user with a phone: `{id, kind, title, body, link, tokens[≤20]}` → `{sent, failed, removed}`. One FCM HTTP v1 message per token (notification title/body, data `{link, kind, id}`), with a service-account access token cached for its hour. A 404 from FCM (app gone) deletes that token. Without `FCM_SERVICE_ACCOUNT` it sends nothing and logs that push is off (200 `{sent: 0, off: true}`). 401 bad secret, 400 bad body. |

Secrets: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `FCM_SERVICE_ACCOUNT` (the Firebase service-account key JSON) and `PUSH_SECRET` (+ the built-in `SUPABASE_URL`, `SUPABASE_SECRET_KEYS`, `SUPABASE_JWKS`, read by `@supabase/server`).

## App structure (`app/`)

```
lib/
  main.dart, app.dart
  core/
    env.dart            String.fromEnvironment: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, RAZORPAY_KEY_ID, GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID, POLICIES_URL, LINK_HOST,
                        FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID (all four, or push stays off)
    push.dart           phone notifications (FCM) behind those keys
    supabase.dart       init with secure session storage; `supabaseProvider`
    router.dart         go_router, auth + admin redirects, bottom-nav shell
    theme/              tokens + ThemeData (light + dark)
    format.dart         formatInr, dates
    errors.dart         maps Postgrest/Auth/Functions exceptions + RPC error codes to user-facing copy
    models/             Dart models matching the schema (fromJson/toJson)
    widgets/            shared UI: AppButton, PriceTag, ProductImage, EmptyState, ErrorView, skeletons, QtyStepper
  features/<feature>/   data (repository + providers) and screens; one folder per feature
    auth, catalog, wishlist, cart, checkout, orders, account, repairs, admin
```

Run config: `flutter run --dart-define-from-file=env/dev.json` (`env/*.json` is gitignored except `env/example.json`).

### Navigation

Bottom nav (shell): **Home · Search · Repairs · Cart · Account**, plus **Admin** as a sixth tab only for admins.

```
/                     home: pinned brand bar + search, one carousel (offer banners, then featured), a row of
                      categories, a one-line repair strip, rails (deals, featured phones, recently viewed), a grid, the shop
/search?q=&category=&brand=&sort=   listing + filters (also used for category pages)
/product/:slug        gallery, variant picker, price/MRP/discount, stock, specs, add to cart, buy now
/cart                 lines, qty stepper, coupon, quote_order totals, checkout CTA
/offers, /offers/:id  offers & coupons (public); one offer: terms, code, time left, its products
/checkout             address select/add, payment method, summary, place order → Razorpay sheet
/checkout/result/:orderId   success / pending / failed with retry
/orders, /orders/:id  list + detail with timeline, cancel
/notifications        signed in: everything that happened, Today / Yesterday / Earlier; the bell on Home and the admin dashboard
/repairs              my bookings + "Book a repair"; /repairs/new form; /repairs/:id
/account              profile, addresses, wishlist, offers, store contact, sign out, delete account; /account/refer
/sign-in              phone | email tabs + Google; /sign-in/verify code entry
/admin                dashboard; /admin/catalogue (every variant: inline and bulk stock/price/visibility edits);
                      /admin/products(/:id); /admin/orders(/:id); /admin/repairs(/:id); /admin/settings;
                      /admin/offers (/new?copy=<id>, /:id); /admin/groups(/new, /:id); /admin/banners(/new, /:id)
```

Lists that grow load a page at a time as you scroll (`lib/core/paging.dart`: `range` pages, a spinner row, "Couldn't
load more. Try again", pull-to-refresh starts over): orders, notifications, wishlist, an offer's products, and in admin the orders,
products and the catalogue (50 a page through `admin_catalogue`, totals from its summary).

Share links: `https://<LINK_HOST>/open?p=<slug>|o=<offer id>&ref=<code>` (product page, offer detail, Refer & earn
share sheets; the signed-in sharer's referral code is added when referrals are on). Android claims them as App Links
(and `shyammobiles://open?…`); the router sends `/open` to the product, offer or home and keeps `ref` on the phone
until someone signs in, then `apply_referral_code` once if `can_enter_code` (REFERRAL_* refusals drop it quietly).
Without the app, `site/open.html` offers the app (intent://) or Play with the link as the install referrer, which the
app follows on its first launch.

Browsing needs no sign-in. Cart, wishlist, checkout, orders, repairs and account redirect to `/sign-in?from=<path>` and come back after login.

## UX bar

- Every screen that loads data has a skeleton, an empty state and an error state with retry. Lists pull to refresh.
- Optimistic cart/wishlist updates that roll back on error.
- Motion (`core/widgets/motion.dart`): totals, prices and stats roll to new values; cards dip and spring back under the finger; Home sections rise in once as they scroll into view; the gallery and the carousel's photos drift slower than the page; the feather mark's dots ripple out once on sign-in and order placed. All off when the phone asks for less motion; parallax, the ripple and the sign-in drift off on low-RAM phones. Colours for slides, bands and category tiles come from `core/theme/generative.dart` (seeded, so an item keeps its colours).
- Tap targets ≥ 48dp, semantic labels on icon buttons, text scales to 1.3× without clipping, WCAG AA contrast in both themes.
- Haptics on add-to-cart and order success. No modal dialogs for success; use inline states or snackbars.
- The Razorpay sheet is prefilled with the account's phone/email.
- Copy is short and plain. Errors say what to do next.

## Photos and slow networks

- `product_images.color` (null or a colour name matching `variants.attributes->>'color'`): picking a colour shows its photos plus the untagged ones; untagged photos show for every colour. Product photos display in a square frame on white, so every product lines up; seeded photos are trimmed and padded to square.

- Product page gallery: full-width square on white (contain, small even inset), zoom in place by pinch, double-tap or the Zoom button (a one-time "Pinch or double-tap to zoom" hint; a zoomed photo pans under one finger), tap for a full-screen black viewer ("2 of 5", Previous / Next, swipe down, Close or back), thumbnail strip with Previous / Next. A sold-out colour or memory can still be picked to see its photos and price: the sticky bar then says "Out of stock" and offers "See <x> in stock". The chosen colour's photos come first, then the untagged ones; a colour with none shows all. Admin tags each photo with a colour (or "Any colour") in the product editor and when uploading.
- Product page rails: "Fits this phone" (phones: accessories whose specs hold `{"label":"Fits","value":<short or full name>}`), "Similar products" (same category, nearest price, up to 8). Home: "Recently viewed" (last 10 opened on this phone, shared_preferences).
- Admin uploads (products and shop) are straightened, stripped of EXIF/GPS, and stored as WebP: `<folder>/<millis>.webp` (≤1600 px, q80) plus `<folder>/<millis>@thumb.webp` (≤480 px, q70); the DB stores the full path, `thumbPathFor` derives the thumb. Uploads are cached for a year (keys are never reused).
- Data saver (automatic, no setting: on for a low-RAM phone, mobile data until measured, or a measured latency above 800 ms): thumbnails everywhere, full photos on tap, no carousel auto-advance, search pages of 12. Home and store settings are kept on the phone and shown instantly when offline.

## v1 additions from competitive research (docs/COMPETITIVE.md)

- **WhatsApp everywhere:** "Ask on WhatsApp" on product, order and repair screens (prefilled `https://wa.me/<store>?text=` with the product/order/repair reference). Staff get "Send update on WhatsApp" on admin order/repair detail (to the customer's number, prefilled with the status).
- **Visible refunds:** paid orders cancelled by the customer or store get a timeline note promising the refund; `refund.processed` adds "Refund issued…".
- **Genuine-product proof:** order detail shows IMEIs once packed, with "Check it: dial *#06# on the phone and match the box label".
- **Returns & warranty:** `store_settings.returns_policy` shown from the product page and the account screen; editable in admin settings.
- **Find the shop:** the home "Visit the store" card shows the shop photos (swipeable, tap for full screen) and, with the account store card, links to Directions (the exact pin) and to the Google Maps listing. Staff set the pin in Admin → Settings by pasting a Google Maps link or "lat, lng" (a pasted place link also becomes `store_maps_url`); photos are added, reordered and removed there and save straight away (removing one deletes the file too: no order references shop photos). We only link out to Google Maps: showing its ratings or reviews in the app would need the Places API (API key, billing, Google attribution rules), so it is deliberately not used and nothing is fetched or copied from Google.
- **No surprise money:** cart shows "No platform, COD or packing fees"; checkout says EMI bank charges, if any, are shown by Razorpay before you pay; repair quotes say "Work starts only after you approve this price".
- **Less sign-in friction:** "Use email instead" link on the code screen after 30 s; add-to-cart/buy-now resumes automatically after sign-in (`from=/product/<slug>?add=<variantId>` or `&buy=<variantId>`).

## Offers: coupons, sales, groups, referrals, banners

One engine. A **promotion** is either a **coupon** (has a `code`) or an **automatic sale** (no code). **One offer per
order**: a valid typed code wins, else the best automatic sale the customer qualifies for (largest saving; tie →
earliest `ends_at`, then id). All pricing goes through one SQL function, used by both `quote_order` (preview) and
`place_order` (charge), so the cart and the charge can never disagree. Migration `20261030000000_offers.sql`
(production already has the 2026-10-28 files: never edit those).

### Tables

- `collections (id, slug unique ^[a-z0-9-]{1,60}$, name 2..60, created_at)` and `collection_products (collection_id,
  product_id, pk both)`: admin-made product groups ("Diwali picks", "Under ₹999") that offers can target. Anyone can
  read them.
- `promotions`: `title` 2..60 (shown to customers), `description` ≤ 300 (terms line), `code` null or unique
  `^[A-Z0-9]{4,20}$` (stored uppercase; null = automatic sale), `kind` (`percent` | `flat` | `free_delivery`),
  `value` int (percent 1..90; flat paise ≥ 100; free_delivery 0), `max_discount_paise` (percent only, null = no cap),
  `min_subtotal_paise` ≥ 0 (on eligible lines), `applies_to` (`order` | `items`), `starts_at` (default now),
  `ends_at` null or > starts_at, `usage_limit` null or ≥ 1 (whole shop), `per_user_limit` null or ≥ 1 (default 1;
  null = unlimited, the usual choice for a sale), `first_order_only`, `online_only` (Razorpay only), `is_public`
  (listed in Offers; hidden codes work only when typed, e.g. a wholesale code sent on WhatsApp), `user_id` null (a
  **personal** coupon only that user can see or use: referrals; requires a code), `is_active` (pause), `show_banner`
  (only for public, non-personal ones: a banner prints the code), `created_at`, `updated_at`. Staff delete only a
  promotion with no use on a non-cancelled order (RLS: deleting a used one deletes no row; pause or end it instead).
- `promotion_targets (promotion_id, target_type product|category|brand|collection, target_id, pk all three)`. A line
  is eligible when its product, its category, its brand, or a collection containing it is targeted. `applies_to =
  items` needs at least one target (admin RPC refuses otherwise); `order` keeps none.
- `promotion_redemptions (order_id pk → orders on delete cascade, promotion_id, user_id, discount_paise, created_at)`,
  one per order that got a promotion (code or sale; `discount_paise` is 0 for free delivery). Uses are counted over
  orders that are **not cancelled** (a cancelled or expired order gives the use back).
- `coupon_attempts (user_id, at)`: failed code lookups (`COUPON_NOT_FOUND`); 10 in 10 minutes → `COUPON_RATE_LIMIT`
  for every code until the oldest is 10 minutes old. Only `quote_order` lookups are counted (a `place_order` refusal
  rolls its own attempt back); the app always quotes a code before placing.
- `orders` + `discount_paise ≥ 0` (0 or ≤ subtotal − 100), `promotion_id` (on delete set null), `coupon_code` (the code
  used; null for a sale); the total check is `total = subtotal + delivery_fee − discount`. `order_items` +
  `discount_paise` 0..line total (its share; Σ lines = order discount; for GST invoices and refunds).
- `banners (title 2..60, subtitle ≤ 120 default '', cta_label 1..20 default 'Shop now', link ≤ 200 (an app route:
  `^/(search|product/|offers|repairs)[A-Za-z0-9/?=&%._~+-]*$`, so no URLs or spaces), image_path null
  (`^banners/[A-Za-z0-9_@-]{1,80}\.webp$` in product-images), tone 0..2 (index into the app's heroGradients),
  starts_at, ends_at null or > starts_at, sort, is_active, promotion_id null unique → promotions on delete cascade,
  created_at, updated_at)`. A trigger keeps one banner per promotion with `show_banner`: title, subtitle (the
  description on one line), same window and `is_active`, link `/offers/<id>`, CTA "Use code X" (codes up to 11
  characters, else "View offer") or "Shop the sale"; staff edits to its image, tone and sort survive; turning
  `show_banner` off deletes it. Anyone can read running, active banners; staff read and write all (RLS).
- Referrals: `store_settings` + `referral_enabled` (default false), `referral_friend_paise` (20000),
  `referral_reward_paise` (20000), `referral_min_order_paise` (199900), `referral_monthly_cap` (10); readable by
  anyone like the rest of `store_settings`. `referral_codes (user_id pk, code unique ^[A-Z0-9]{6,10}$)` made lazily
  (8 characters); `referrals (referee_id pk, referrer_id, status pending|rewarded|void, created_at, rewarded_at)`.

Promotions, targets, collections, collection_products and banners: staff write (RLS + explicit grants, like the
rest). Redemptions, referral codes and referrals: staff read only; only the RPCs and triggers write them; nobody reads
`coupon_attempts`. Customers never read `promotions` directly: they go through the RPCs below, so hidden and personal
codes can't be listed.

### Pricing (`private.price_lines`, shared)

1. Lines = the caller's cart lines (locked ones in `place_order`); subtotal = Σ unit × qty.
2. Pick the promotion (code if given and valid, else best automatic). Eligible lines per `applies_to`/targets.
3. `eligible < min_subtotal` → not applicable. Discount: percent → ⌊eligible × value / 100⌋ capped at
   `max_discount_paise`; flat → min(value, eligible); free_delivery → 0 (fee becomes 0). Never more than
   subtotal − 100 (an order always costs at least ₹1 before delivery).
4. Delivery is free when **subtotal − discount** ≥ `free_delivery_min_paise`. COD limit applies to the final total.
   A promotion applies only when it lowers the total (saving = what the order costs without it − with it > 0; a
   discount that drops the order under the free-delivery minimum can bring the fee back): a typed code that wouldn't
   → `COUPON_NOT_APPLICABLE`, a sale that wouldn't is skipped.
5. Split the discount over eligible lines in proportion to line totals, rounding down; the remainder goes to the
   largest line (ties by lowest variant id), spilling to the next largest only if it would pass that line's total.
6. Checks, for codes and sales alike: active, started, not ended, owner (personal), total uses < usage_limit, caller's
   uses < per_user_limit, first_order_only → caller has no non-cancelled order, online_only → method razorpay (a
   quote with no method yet counts as online), eligible lines exist, min subtotal met. `place_order` locks the
   promotion row(s) `for update` before counting uses (with the caller's checkout lock, two checkouts can't both take
   the last use).

### RPCs

Offer rows (`available_offers`, `offers_for_product`, `apply_referral_code`): `{id, title, description, code, kind,
value, max_discount_paise, min_subtotal_paise, starts_at, ends_at, applies_to, automatic, online_only,
first_order_only}`.

| Function | Caller | Does |
|---|---|---|
| `quote_order(p_coupon_code text default null, p_payment_method payment_method default null) → json` | authenticated | Prices the current cart without placing anything: `{subtotal_paise, delivery_fee_paise, discount_paise, total_paise, promotion: {id, title, code, kind} or null, coupon_error: code or null, coupon_error_detail: text or null}` (`coupon_error_detail` = the minimum in paise for `COUPON_MIN_ORDER`). A bad code returns `coupon_error` and falls back to the best automatic sale. Codes are trimmed, spaces removed, uppercased. `CART_EMPTY` on an empty cart. Stock is not checked here (`place_order` does). |
| `place_order(p_address_id, p_payment_method, p_coupon_code text default null) → uuid` | authenticated | As before, priced by the shared function; a bad code **raises** its error (`details` = the minimum for `COUPON_MIN_ORDER`). Writes discount, promotion_id, coupon_code, line discounts and the redemption. |
| `available_offers() → json` | anon, authenticated | Offer rows the caller may use now: running, public ones plus their personal coupons, with uses left; signed in, also leaves out ones they've used up and first-order ones once they have an order. Personal first, then by `ends_at`. Hidden codes never appear. |
| `offers_for_product(p_product_id uuid) → json` | anon, authenticated | Same rows, only offers that would cover this product (for the product page chip). |
| `offer_products(p_promotion_id uuid) → setof product_cards` | anon, authenticated | Products an `items` offer covers (all active products for `order`); for `/offers/:id`. Empty for a paused or ended offer; hidden ones show nothing but to staff, personal ones only to their owner (and staff). PostgREST filters/order/limit work on it. |
| `my_referral() → json` | authenticated | `{enabled, code, friend_paise, reward_paise, min_order_paise, joined, rewarded, can_enter_code}`; makes the code on first call. `joined`/`rewarded`: friends who used the code / were rewarded. `can_enter_code`: enabled, not referred yet, no non-cancelled order. |
| `apply_referral_code(p_code text) → json` | authenticated | Links the caller to a referrer and returns their welcome coupon as an offer row (personal, flat `referral_friend_paise`, min `referral_min_order_paise`, first order only, one use, 90 days, code `FRIEND…`). Errors, checked in this order: `REFERRAL_OFF`, `REFERRAL_USED` (already referred), `REFERRAL_TOO_LATE` (has a non-cancelled order), `REFERRAL_INVALID`, `REFERRAL_SELF`. |
| `admin_save_promotion(p json) → uuid` | admin | Insert (no `id`) or update (`id`) a promotion with its targets in one transaction. `p` = promotion columns plus `targets: [{target_type, target_id}]`; keys left out keep their value (on insert: the column default), so `{id, is_active: false}` pauses; `targets` replaces the old ones when present. Code trimmed and uppercased. Errors: `FORBIDDEN`, `NOT_FOUND` (unknown id), `CODE_TAKEN`, `INVALID_PROMOTION` (`details` = the broken rule: a constraint name such as `promotions_value_check` / `promotions_window_check` / `promotions_banner_check`, a column name for a missing value, `items needs a target`, `unknown target`, or the bad-input message). "End now" on a scheduled offer must also move `starts_at`. |
| `admin_promotions() → json` | admin | Every promotion (all columns) plus `status` (`paused` \| `ended` \| `scheduled` \| `running`), `uses` and `discount_total_paise` (over non-cancelled orders) and `targets: [{target_type, target_id}]`, newest first. |

Referral reward: when one of a referee's orders with subtotal ≥ `referral_min_order_paise` is delivered while the
referral is pending (so at most once; a smaller delivered order leaves it pending), a trigger creates the referrer's
reward coupon (personal, flat `referral_reward_paise`, same minimum, one use, 90 days, code `REWARD…`) and marks it
`rewarded`, unless the referrer already got `referral_monthly_cap` this IST month: then it is `void`. Pending
referrals are still honoured after `referral_enabled` is switched off.

### Errors

`COUPON_NOT_FOUND` (unknown, paused, or someone else's), `COUPON_NOT_STARTED`, `COUPON_EXPIRED`, `COUPON_USED_UP`,
`COUPON_LIMIT_REACHED`, `COUPON_MIN_ORDER` (detail = min paise), `COUPON_NOT_APPLICABLE` (nothing eligible, or it
wouldn't lower the total), `COUPON_FIRST_ORDER`, `COUPON_ONLINE_ONLY`, `COUPON_RATE_LIMIT`, the `REFERRAL_*` codes,
and for staff `INVALID_PROMOTION` and `CODE_TAKEN`.

### App

- Home: banner strip under the hero (tone gradients, image when set), tapping opens `link`.
- `/offers` (Account → Offers & coupons, cart → View offers): list with Copy code / Apply. `/offers/:id`: terms,
  code, time left, eligible products.
- Cart and checkout: "Apply coupon" sheet (code field + listed offers); summary shows the discount line (code or sale
  title); errors in plain words; the code rides along to `place_order`. Order detail shows the discount.
- Product page: an offer chip per `offers_for_product` row.
- Account → Refer & earn: your code, share on WhatsApp, counts; "Have a friend's code?" while `can_enter_code`.
- Admin (dashboard tiles): Offers (list with status running/scheduled/paused/ended, uses, total given; create, edit,
  duplicate, pause, end now, delete only when never used), Groups (collections CRUD with a product picker), Banners
  (CRUD, order, schedule, image). Promotion editor: type, value, code (or Generate), public/hidden, applies to (whole
  order, or any mix of products, categories, brands, groups), min order, cap, dates, limits, first order, online only,
  show banner. Settings: referral section.

## Notifications

Migration `20261030000400_notifications.sql`. Database triggers write every notification, so an RPC, a webhook or the
expiry job can't forget one; nobody inserts from a client.

- `notifications`: `kind` (`^[a-z_]{2,40}$`, picks the app's icon and colour), `title` 1..80, `body` ≤ 300 (one line;
  longer copy is cut with …), `link` an app route (`/orders/…`, `/repairs/…`, `/offers…`, `/product/…`,
  `/admin/orders/…`, `/admin/repairs/…`, `/admin/feedback/…`, `/admin/products/…`, `/admin/catalogue…`; always the
  specific screen), `order_id`/`repair_id` (on delete cascade), `read_at`, `created_at`. RLS: people read, delete and
  update their own; the only column they can change is `read_at`. A nightly `pg_cron` job (`notifications-cleanup`,
  03:30) deletes notifications older than 90 days and phone tokens unused for 270.
- Who: the customer the order, repair or coupon belongs to; "staff" means one row for each admin in `admins` except
  whoever did it (staff marking packed tells no staff). Copy formats money in SQL as the app does
  (`private.inr`: ₹1,29,999).

| Event | Customer gets (kind: title) | Staff get |
|---|---|---|
| COD order placed | `order_confirmed`: SM1042 is confirmed (amount, cash on delivery) | `staff_new_order`: New order SM1042 (amount · payment · items · town) |
| Online order placed | `order_awaiting_payment`: Finish paying for SM1042 (15-minute hold) | nothing until paid |
| Payment fails (`mark_payment_failed`) | `payment_failed`: Payment failed for SM1042 (try again before the hold ends) | |
| Payment lands (`mark_order_paid`, also reviving an expired order) | `payment_received`: Payment received for SM1042 | `staff_order_paid`: Paid order SM1042 (summary) |
| Payment lands on a cancelled order | `order_late_payment`: We got your payment for SM1042 (refund coming) | `staff_refund_needed`: Refund ₹X for SM1042 |
| Hold expires (`expire_unpaid_orders`) | `order_expired`: SM1042 was cancelled | |
| Packed / shipped / delivered | `order_packed` · `order_shipped` (courier and tracking) · `order_delivered` (tap to rate) | |
| Courier or tracking changed later (packed/shipped/delivered) | `order_tracking`: Tracking updated for SM1042 (a note sent with it joins the same notification) | |
| Staff note on the timeline | `order_update`: Update on SM1042 (the note) | |
| Customer cancels | `order_cancelled`: You cancelled SM1042 (refund promise if paid) | `staff_refund_needed` if paid, else `staff_order_cancelled`: SM1042 cancelled by the customer (stock is back); nothing for an unpaid online order |
| Shop cancels | `order_cancelled`: SM1042 was cancelled by the shop (the note) | other staff: `staff_refund_needed` if paid |
| Refund (webhook, delivered → refunded, or staff closing a needs-refund) | `order_refunded`: Refund of ₹X for SM1042 (the timeline's refund note) | |
| Repair booked (customer, or a walk-in by staff) | `repair_booked`: Repair booked for your Galaxy A56 (issue, date, slot) | `staff_new_repair`: New repair RP1001: Samsung Galaxy A56 |
| Confirmed / work started / ready / completed | `repair_confirmed` (date and slot) · `repair_started` · `repair_ready` (what to pay) · `repair_completed` (tap to rate) | |
| Quote sent or changed | `repair_quote`: ₹200 quote for your Galaxy A56 screen: approve to start (…to continue, mid-repair) | |
| Quote agreed at the counter (`p_approved`) | `repair_quote_agreed` | |
| Customer approves / declines the quote | | `staff_quote_approved` · `staff_quote_declined` (with the reason) |
| Customer cancels a repair | (their own action: nothing) | `staff_repair_cancelled` |
| Shop cancels a repair | `repair_cancelled` (the reason) | |
| Staff note on a repair | `repair_update` (the note) | |
| Referral: friend's welcome gift / referrer's reward / any personal coupon | `referral_welcome` · `referral_reward` · `coupon` (code, minimum, last day; links to the offer) | |
| Feedback sent or re-rated | | `staff_feedback`: New rating: 5 stars for order SM1042, or `staff_feedback_low`: Low rating: 2 stars for … (1–2 stars); links to `/admin/feedback/<id>` |
| A sale takes a live variant to ≤ 3 / to 0 | | `staff_low_stock` / `staff_out_of_stock`, once per crossing; staff stock edits don't count |

**Live in the app.** Polling, not Realtime (the local stack runs without it to save RAM; a Realtime subscription could
replace the timer): `unread_notifications` every 45 s while the app is in front, on resume, and right after any write
the app sends (`TimeoutClient.onWrite`). A rise slides the newest one in at the top for about 5 s (one at a time,
tappable, with View and a close button; no slide when the phone asks for less motion; it stays for screen-reader
users) and refreshes the screen it's about. `/notifications`: paged, grouped Today / Yesterday / Earlier, icon tinted
by meaning (emerald done, gold needs you or a deal, peacock news, red failed or cancelled), unread rows bold with a
dot; tap marks read and opens the link; Mark all read; a delete button on every row and swipe to delete.

**Push (off until configured).** `device_tokens` (own rows readable and deletable; written only by `register_device`).
An AFTER INSERT trigger on `notifications` posts the row and the user's tokens to `send-push` with pg_net, only when
Vault holds `push_url` and `push_secret` (set by `scripts/launch.py --only secrets,functions,push`); pg_net sends after
commit, and any error is logged and swallowed, so a push never fails the order or repair behind it. The app uses
Firebase only when built with all four `FIREBASE_*` defines (no google-services.json, no Gradle plugin). Then: after
the first order or repair booking a short explainer offers phone notifications once, before Android 13's prompt; the
token is registered after sign-in and on refresh, dropped at sign-out; a push in the foreground shows in the same
banner, and tapping one opens its link.

## Environments and setup

The local stack is `supabase start` (Docker/Colima). Test OTP: phone `+919999999999` / code `123456`. Emails land in Mailpit at `http://127.0.0.1:54324`.

Accounts the owner must create before launch: Supabase project, Razorpay (KYC + live keys + webhook), Google Cloud OAuth clients (Android SHA-1 + web; iOS later), an SMS provider with DLT-registered templates (MSG91 or Twilio), Google Play Console account (Apple Developer only when iOS starts).
