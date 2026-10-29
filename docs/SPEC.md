# Shyam Mobiles — v1 spec

Single source of truth for everyone building v1. If code and this file disagree, fix one of them in the same change.

## Product

Android app for Shyam Mobiles, a phone shop. iOS comes later from the same Flutter codebase; v1 is designed, tested and shipped on Android only (minSdk 24, edge-to-edge, predictive back, Credential Manager sign-in, UPI intent payments).

- Customers: browse and search new phones and accessories, wishlist, cart, checkout (Razorpay or cash on delivery), track orders, book repairs.
- Staff: the same app shows an **Admin** tab when the signed-in user is in `admins`. Admins manage products/stock/images, move orders through fulfilment (with IMEIs), and handle repair bookings.

Not in v1 (on purpose): guest cart, coupons, reviews, banners, store pickup, courier API, push notifications, GST invoice PDF, Hindi UI, refurbished phones. The schema leaves room for each.

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
- Delivery is free when the subtotal is at or above `free_delivery_min_paise`, else `delivery_fee_paise`. COD needs `cod_enabled` and a **total** (subtotal + delivery) at or below `cod_max_paise`. Every order satisfies `subtotal = Σ unit_price × qty` and `total = subtotal + delivery_fee`.
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
- `orders(number 'SM100001', user_id, status, payment_method, payment_status, subtotal/delivery_fee/total paise, address jsonb snapshot, razorpay_order_id, razorpay_payment_id, courier, tracking_number, reserved_until)`.
- `order_items(order_id, variant_id, product_name, variant_name, unit_price_paise, qty, gst_rate, imeis text[])`: snapshot of what was sold.
- `order_events(order_id, status, note, created_at)`: timeline shown to the customer.
- `payment_events(razorpay_event_id unique, type, payload)`: webhook audit + idempotency.
- `repair_bookings(number 'RP100001', user_id, device_brand, device_model, issue, description, preferred_date, slot, contact_phone, status, quote_paise, admin_note)`: a customer has at most 3 open (not completed/cancelled) bookings (`REPAIR_LIMIT`); staff booking walk-ins are exempt.
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
repair.status:  requested ─> confirmed ─> in_progress ─> ready ─> completed ; any open ─> cancelled
```

- COD orders start `confirmed` with `payment_status = pending`. They become `paid` when the admin marks them `delivered`.
- Razorpay orders start `pending_payment` and hold their stock until `reserved_until` (now + 15 min). A `pg_cron` job cancels expired ones and puts the stock back.
- If a payment lands on an order that already expired, `mark_order_paid` tries to re-reserve the stock. If it can't, the order stays `cancelled` with `payment_status = paid`, and the admin dashboard lists it as **needs refund**.
- Customers book repairs with a plain `insert` of `user_id, device_brand, device_model, issue, description, preferred_date, slot, contact_phone` (RLS: own `user_id`, `status = requested`, no `quote_paise`/`admin_note`, `preferred_date` from today to today + 30 in IST; `id`, `number` and timestamps are never client-set) and cancel via `cancel_repair`. Admins write repairs directly.

## RPC contract (called by the app via `supabase.rpc`)

Errors are raised exceptions with `errcode 'P0001'` and `message` = a bare code (detail, if any, in `details`). Codes: `CART_EMPTY`, `ADDRESS_NOT_FOUND`, `OUT_OF_STOCK`, `COD_UNAVAILABLE`, `NOT_FOUND`, `INVALID_TRANSITION`, `FORBIDDEN`, `INVALID_IMEIS`, `ADDRESS_LIMIT` (address insert trigger: max 10 per user), `CART_LIMIT` (cart insert trigger: max 20 lines; `place_order`: max 10 lines), `REPAIR_LIMIT` (repair insert trigger: max 3 open), `PENDING_LIMIT`, `ORDER_TOO_LARGE`. Calling a function your role may not execute gives `42501`.

| Function | Caller | Does |
|---|---|---|
| `is_admin() → bool` | authenticated | Whether the caller is staff. |
| `place_order(p_address_id uuid, p_payment_method payment_method) → uuid` | authenticated | Reads the caller's cart, locks its lines and variants (only those locked lines are ordered: a line added while it runs stays in the cart), checks stock and active flags, computes totals, applies the COD rules, creates the order, items and first event, decrements stock, clears the cart. Errors: `CART_EMPTY`, `ADDRESS_NOT_FOUND`, `OUT_OF_STOCK` (also for inactive variants/products; `details` = comma-separated variant ids), `COD_UNAVAILABLE` (COD disabled or total > `cod_max_paise`), `CART_LIMIT` (more than 10 lines), `PENDING_LIMIT` (an online order while the caller already has 2 unpaid online orders whose hold hasn't expired; COD is not capped), `ORDER_TOO_LARGE` (total beyond what int paise can hold, ₹2,14,74,836.47). `address` snapshot keys: `name, phone, line1, line2, landmark, city, district, state, pincode` (`district` may be null). |
| `cancel_order(p_order_id uuid) → void` | authenticated (owner) | Allowed while `pending_payment` or `confirmed`. Restocks. A paid order cancelled here shows up as **needs refund**. |
| `cancel_repair(p_booking_id uuid) → void` | authenticated (owner) | Allowed while `requested` or `confirmed`. |
| `admin_update_order(p_order_id uuid, p_status order_status, p_note text, p_courier text, p_tracking_number text) → void` | admin | Validates the transition, writes an event, restocks on cancel, marks COD paid on delivered; `refunded` also sets `payment_status = refunded`. `p_status` = current status just updates courier/tracking (null keeps the old value) and adds a note event if `p_note` is set. |
| `admin_set_imeis(p_order_item_id uuid, p_imeis text[]) → void` | admin | A one-dimensional array; count must equal qty; each value 15 digits; no duplicates. Else `INVALID_IMEIS`. |
| `admin_dashboard() → json` | admin | `{orders_today, revenue_today_paise, open_orders, low_stock, open_repairs, needs_refund}`, all integers. Today = IST calendar day, orders in confirmed/packed/shipped/delivered. `open_orders`: confirmed/packed/shipped. `low_stock`: active variants of active products with stock ≤ 3. `open_repairs`: not completed/cancelled. `needs_refund`: `status = cancelled and payment_status = paid`. |
| `mark_order_paid(p_order_id uuid, p_razorpay_payment_id text) → void` | service_role only | Idempotent. Used by the Edge Functions. A late payment revives an *expired* order if stock allows; a customer/admin-cancelled order is never revived (→ needs refund). |
| `mark_payment_failed(p_order_id uuid) → void` | service_role only | From the `payment.failed` webhook: `pending → failed`, order stays payable until expiry. |
| `mark_order_refunded(p_razorpay_payment_id text) → void` | service_role only | From the `refund.processed` webhook (full refunds only): `payment_status = refunded`. |
| `expire_unpaid_orders() → int` | `pg_cron`, every 5 min | Cancels `pending_payment` orders past `reserved_until`, restocks. |

## Edge Functions (`supabase/functions/*`)

All are `POST`. User functions keep the platform `verify_jwt` check and verify the user JWT again in code (`@supabase/server`, JWKS). A request with no `Authorization` header is refused by the platform with a 401 whose body is `{"msg": "..."}`, not the shape below; treat every 401 as `UNAUTHORIZED`. Errors: JSON `{"error": "<CODE>", "message": "<short human text>"}` with a matching status: 400 `BAD_REQUEST`/`BAD_SIGNATURE`, 401 `UNAUTHORIZED`/`BAD_SIGNATURE` (webhook), 404 `NOT_FOUND`, 409 `ORDER_NOT_PAYABLE`/`ORDER_EXPIRED`/`PAYMENT_MISMATCH`/`ACTIVE_ORDERS`, 502 `GATEWAY_ERROR` (Razorpay unreachable or erroring), 500 `INTERNAL`.

| Function | Auth | Body → Response |
|---|---|---|
| `create-payment` | user JWT | `{order_id}` → `{key_id, razorpay_order_id, amount, currency, order_number, reserved_until}` (`reserved_until`: ISO 8601 UTC, when the stock hold ends; set Razorpay's checkout `timeout` from it). Reuses an existing `razorpay_order_id`. Refuses unless the order is the caller's, `pending_payment`, `razorpay`, and not expired. |
| `verify-payment` | user JWT | `{razorpay_order_id, razorpay_payment_id, razorpay_signature}` → `{order_id, status}`. Checks the HMAC, fetches the payment from Razorpay (order id, amount = total, status captured/authorized), then calls `mark_order_paid`. `status` is the order status afterwards (`confirmed`, or `cancelled` if it was paid too late). |
| `razorpay-webhook` | none (`verify_jwt = false`), HMAC instead | Handles `payment.captured`, `order.paid`, `payment.failed`, `refund.processed`. Verifies `x-razorpay-signature` over the raw body (401 if bad), dedupes on `x-razorpay-event-id` via `payment_events`, checks amount = order total. `refund.processed` counts as full only when the event's payment has `amount_refunded ≥ amount`; anything else (a partial refund, missing totals) is left for staff. Returns 200 on duplicates, unknown events/orders and business refusals; 500 only on infrastructure errors (Razorpay retries). |
| `delete-account` | user JWT | `{}` → 204. Returns 409 `ACTIVE_ORDERS` if any order is not delivered/cancelled/refunded, or any repair is not completed/cancelled. Otherwise deletes the auth user (cascades the profile, cart, wishlist, addresses; orders keep `user_id = null`). |

Secrets: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` (+ the built-in `SUPABASE_URL`, `SUPABASE_SECRET_KEYS`, `SUPABASE_JWKS`, read by `@supabase/server`).

## App structure (`app/`)

```
lib/
  main.dart, app.dart
  core/
    env.dart            String.fromEnvironment: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, RAZORPAY_KEY_ID, GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID
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
/                     home: categories, featured products, repair CTA
/search?q=&category=&brand=&sort=   listing + filters (also used for category pages)
/product/:slug        gallery, variant picker, price/MRP/discount, stock, specs, add to cart, buy now
/cart                 lines, qty stepper, totals preview, checkout CTA
/checkout             address select/add, payment method, summary, place order → Razorpay sheet
/checkout/result/:orderId   success / pending / failed with retry
/orders, /orders/:id  list + detail with timeline, cancel
/repairs              my bookings + "Book a repair"; /repairs/new form; /repairs/:id
/account              profile, addresses, wishlist, store contact, sign out, delete account
/sign-in              phone | email tabs + Google; /sign-in/verify code entry
/admin                dashboard; /admin/catalogue (every variant: inline and bulk stock/price/visibility edits);
                      /admin/products(/:id); /admin/orders(/:id); /admin/repairs(/:id); /admin/settings
```

Browsing needs no sign-in. Cart, wishlist, checkout, orders, repairs and account redirect to `/sign-in?from=<path>` and come back after login.

## UX bar

- Every screen that loads data has a skeleton, an empty state and an error state with retry. Lists pull to refresh.
- Optimistic cart/wishlist updates that roll back on error.
- Tap targets ≥ 48dp, semantic labels on icon buttons, text scales to 1.3× without clipping, WCAG AA contrast in both themes.
- Haptics on add-to-cart and order success. No modal dialogs for success; use inline states or snackbars.
- The Razorpay sheet is prefilled with the account's phone/email.
- Copy is short and plain. Errors say what to do next.

## Photos and slow networks

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

## Environments and setup

The local stack is `supabase start` (Docker/Colima). Test OTP: phone `+919999999999` / code `123456`. Emails land in Mailpit at `http://127.0.0.1:54324`.

Accounts the owner must create before launch: Supabase project, Razorpay (KYC + live keys + webhook), Google Cloud OAuth clients (Android SHA-1 + web; iOS later), an SMS provider with DLT-registered templates (MSG91 or Twilio), Google Play Console account (Apple Developer only when iOS starts).
