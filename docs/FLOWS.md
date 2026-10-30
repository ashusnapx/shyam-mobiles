# Customer ↔ admin flows

How every flow looks from both sides, the database step behind each state, and whether the two sides line up.
Audited 30 Oct 2026 against the app (`app/lib/features/*`), the migrations up to `20261030000350` and the Edge
Functions. ✓ = both sides agree and every state has a next step. ✗ = a mismatch, with what was done about it.
Contract details live in `docs/SPEC.md`; this file is the cross-check.

## Repairs

Backend: `20261030000300_repair_flow.sql`. Nobody updates `repair_bookings` directly any more; every change goes
through an RPC and writes a `repair_events` row, which both sides show as the timeline.

| State | Customer sees / can do | Staff see / can do | DB |
|---|---|---|---|
| requested | "We'll call to confirm your slot." Cancel. | Confirm booking (also one tap on the dashboard), Send quote, Cancel with reason, note, WhatsApp, call | insert (RLS); `admin_update_repair → confirmed` |
| confirmed, no quote | "Bring your phone in… we'll send you the price here." Cancel. | Start repair **disabled**: "Send a quote first…"; Send quote; Cancel | `admin_set_repair_quote` |
| quote pending (requested / confirmed / in repair) | Quote card with **Decline** and **Approve** (confirmChoice; decline asks for an optional reason). "Awaiting approval" tag in My repairs. | "Waiting for the customer to approve ₹X in the app." Start / Ready disabled with that reason; Change quote; "Customer agreed in person or by phone" (records the yes); dashboard tile and list filter **Awaiting approval** | `approve_repair_quote(id, amount seen)` / `decline_repair_quote(id, reason)` |
| quote declined | "You declined the price. We'll call you with other options, or you can cancel" (or, once in repair, "We'll call you about your phone"). | Red note with the reason; send a new quote, record a yes, or cancel | same RPCs |
| confirmed, approved | "Price approved. We'll start the repair soon." Cancel. | **Start repair** | `admin_update_repair → in_progress` (needs approved, else `QUOTE_NOT_APPROVED`) |
| in repair | "Our technician is on it." No cancel (phone is open). A new price mid-repair comes back to Approve/Decline. | **Ready for pickup** (needs the current quote approved), Change quote, Cancel | `→ ready` |
| ready | "Pick it up from the store." | **Mark completed** (confirm), Cancel | `→ completed` |
| completed | "All done", **rate the repair** | Customer feedback card (stars, comment, status → inbox); notes still allowed | `send_feedback` |
| cancelled | Cancelled hero, the reason in Updates | Timeline; notes | `cancel_repair` (customer, requested/confirmed) or `admin_update_repair → cancelled` |

Lists: My repairs and Admin → Repairs load 30 at a time (spinner row, retry row, pull to refresh).

✗ found and fixed:
- The quote card said "Work starts only after you approve this price" but there was no Approve button (only "Approve
  on WhatsApp", which staff had no way to record). → In-app Approve / Decline; staff can record a yes given in person.
- Staff could only "Mark <next status>" with no approval gate, and wrote the table directly, so any step could be
  skipped (the old test even moved a *cancelled* booking back to confirmed). → `admin_update_repair` enforces the
  steps, `UPDATE` revoked from clients, in_progress/ready need an approved quote.
- No timeline: the customer saw fixed step labels with no times, and one `admin_note` that each save overwrote. →
  `repair_events` (backfilled for existing bookings, old notes included), shown as step times + an Updates list on
  both sides.
- A quote could be approved after staff changed it (customer saw ₹200, store had typed ₹500). → approve sends the
  amount seen; a different one is `QUOTE_CHANGED` ("The store just changed the price…").
- Dashboard had no count for quotes waiting on the customer. → `repairs_awaiting_approval` tile → filtered list.
- My repairs was a single unpaged query; the admin list stopped at 200. → paged.
- One booking's screen could outlive a sign-out (provider didn't watch the user). → it does now.

## Orders

| State | Customer | Staff | DB | |
|---|---|---|---|---|
| pending_payment (online) | "Payment pending", Pay by <time>, Cancel | Cancel with reason | `place_order`, `create-payment` | ✓ |
| payment failed | "Not paid yet", Pay again until the hold ends | "Razorpay · Failed" | `mark_payment_failed` | ✓ |
| expired | Cancelled, "Payment not received in time", Reorder | Cancelled | `expire_unpaid_orders` (restocks) | ✓ |
| confirmed (COD at once, online once paid) | Cancel | Mark packed (and one tap on the dashboard), Cancel with reason | `admin_update_order` | ✓ |
| packed | IMEIs once added | Ship (courier required, tracking optional), Cancel, IMEIs per item | same | ✓ (see Left: IMEIs aren't required) |
| shipped | Courier and tracking (copy button) | Edit courier & tracking, Mark delivered | same | ✗ fixed |
| delivered | Rate the order | Mark refunded (returns) | COD becomes paid | ✓ |
| cancelled, paid (needs refund) | "Refund due", note that it's on its way | Red note, **Mark refunded** | `admin_update_order(…, 'refunded')` | ✗ fixed |
| refunded | "Money returned" / payment "Refunded" | — | | ✓ |

Customer cancel (pending_payment, confirmed) and the staff transitions match the SQL tables (`rules_test.dart` pins
them). Restock happens on customer cancel, staff cancel and expiry.

✗ fixed:
- A cancelled, paid order could only leave "needs refund" through the full-refund webhook; partial refunds, cash or UPI
  refunds and missed webhooks left the dashboard red forever and the customer never saw "Refunded". → staff **Mark
  refunded** on those orders (`20261030000350_refund_by_staff.sql`): payment becomes refunded, status stays cancelled
  (its coupon use stays given back), timeline note "Refund issued…". Admin note copy no longer says "paid after this
  order was cancelled" for orders paid first.
- Fixing the courier or tracking number wrote no event, so the customer timeline never said anything changed. → the
  RPC adds "Courier and tracking updated: <courier> · <tracking>". The edit button was a small "Edit" in a header; it's
  now "Edit courier & tracking" under the shipping line.
- A courier without a tracking number ("Shop delivery") never showed to the customer. → "Delivery by <courier>".
- Customer feedback on an order or repair only showed in Admin → Feedback. → a Customer feedback card on the admin
  order and repair screens (opening them doesn't mark it seen).
- Error copy promised refunds nothing performs: BAD_SIGNATURE "will be refunded automatically", PAYMENT_MISMATCH "it
  will be refunded". → "call or WhatsApp the store with the order number and we'll sort it out".

## Cart, product hidden or out of stock

| Change by staff | Product page | Cart | Checkout | |
|---|---|---|---|---|
| stock 0 | Out of stock | line "Out of stock", can't check out | `OUT_OF_STOCK` | ✓ |
| variant or product hidden | Not found (RLS) | ✗ fixed | ✗ fixed | |

✗ fixed: RLS hides an inactive variant from customers, so its cart line came back without one and the whole cart
failed to load (error and Retry forever, line impossible to remove), while `place_order` kept refusing the cart over
that invisible line. → the cart drops (and deletes) such lines when it loads. Left: no message says an item was
removed (cart screen is the Offers engineer's area).

## Offers, coupons, referrals, banners

| Staff action | Customer side | |
|---|---|---|
| create / pause / end an offer | Offers list (`available_offers`, refreshed within 2 min), cart/checkout quote returns the coupon error | ✓ |
| referral delivered | Reward coupon appears in the referrer's Offers (`offer_open` matches `user_id`) | ✓ |
| banner edit / offer ends | Home strip | ✗ partly fixed |

✗ banners stayed on other phones until the app was restarted. → banners and store settings are re-read whenever the
app comes back to the foreground (`main.dart`). Rest handed off (below).

## Store settings

Delivery fee, free-delivery minimum, COD on/limit, phone, hours, address, repair note, returns policy are saved on the
phone and refreshed only on pull-to-refresh or reconnect. Totals were always right (the server prices), but the shown
text and COD availability could be stale. ✗ fixed: re-read on every app resume.

## Wishlist and addresses

Wishlist: hidden products drop out (RLS) ✓; see Handed off for the empty-state edge case. Addresses: add/edit/delete/
default ✓; orders keep a snapshot, so deleting an address never changes a past order ✓.

## Admin dashboard counts vs the lists they open

| Tile | Count | Opens | |
|---|---|---|---|
| Orders today / Revenue today | today (IST), confirmed…delivered | was every order ever → now `?status=today` (same filter) | ✗ fixed |
| Open orders | confirmed/packed/shipped | `?status=open` | ✓ |
| Open repairs | not completed/cancelled | Repairs (Open) | ✓ |
| Awaiting approval | open, quote pending | `?status=awaiting_approval` | new |
| Low stock | counted variants | Products low-stock list shows products → now counts products | ✗ fixed |
| Needs refund | cancelled + paid | `?status=needs_refund` | ✓ (and now clearable) |
| New feedback | status new | Feedback inbox | ✓ |

## Account deletion

Orders stay with `user_id = null` (tax records) and staff still see them from the address snapshot ✓; repairs likewise
✓. ✗ fixed: deletion went through while a cancelled order was still owed a refund, so the customer lost sight of it →
`delete-account` refuses (409 `ACTIVE_ORDERS`, copy now mentions a refund on its way).

## Sign-in / sign-out

Every per-user provider (cart, wishlist, orders, repairs, offers, admin flag) watches the signed-in user and resets on
sign-out or account switch ✓ (the single repair screen was the exception; fixed above).

## Handed off

- **Offers engineer — banners:** `bannersProvider` filters `runningAt` only when it fetches; filter again in the strip,
  and drop banners of offers that are used up or first-order-only for this customer (they open "This offer has ended").
- **Offers engineer — referral screen:** "You get a ₹X coupon once it's delivered" should mention the friend's
  minimum order and that rewards stop after the monthly cap (`referral_monthly_cap` voids silently).
- **Offers engineer — wishlist:** if every row of the first page is hidden, the screen shows "Nothing saved yet" while
  later pages have items; load the next page (or show the list) when `hasMore`.
- **Offers engineer — cart:** tell the customer when a hidden item was removed from their cart.
- **Product page / admin products:** "Reports about this listing" on the admin product editor needs a product filter
  in the feedback inbox; not added.

## Left

- **IMEIs at packing:** the site promises "your order shows the IMEI of each phone once it is packed", but packing
  never asks for them (dashboard one-tap Pack included). Enforcing it needs `admin_update_order` to know which lines
  are phones (join to `categories.kind`) and would change many existing order tests; suggested: refuse `packed` with
  `IMEIS_MISSING` for phone lines without IMEIs, and make the dashboard open the order instead.
- **PAYMENT_MISMATCH / a second payment on a paid order:** only logged by the webhook; staff aren't told. Suggested: an
  order event or a needs-attention count.
- **Tracking can't be cleared** once set (`coalesce` keeps the old value); only replaced.
