# Razorpay: what it offers and how Shyam Mobiles uses it

Checked 2026-10-30 against Razorpay's docs. Razorpay changes partners and fees often, so confirm each item on the
dashboard or with your Razorpay account manager before you rely on it. Test everything in Test Mode first. How the
app does it: docs/SPEC.md, "Payments: refunds, payment links, saved cards, disputes".

## In use today

| What | How | Needs |
|---|---|---|
| **Standard Checkout** (`razorpay_flutter`) | UPI, cards, netbanking, wallets, EMI. `create-payment` makes the Razorpay order, `verify-payment` checks the signature, the webhook records `payment.captured`, `order.paid`, `payment.failed`. The amount always comes from the database, with any offer applied, never from the phone. | — |
| **"EMI from ₹X/month"** on the product page | `emi-plans` reads the account's EMI plans (`GET /v1/methods`, key id only [7]) once a day; the app shows the cheapest monthly instalment for the price, "No-cost EMI available" when a plan's interest is paid by the shop (subvention), and a sheet of every bank and tenure. Hidden when no plan applies. | EMI activated (below). The test account has it off, so the line is hidden in testing. |
| **Refund from the admin screen** | "Refund ₹X" (everything left) or "Refund items" (lines at what was paid for them, discount included) calls the Refunds API [8] with an idempotency key [9]; `refund.processed` / `refund.failed` settle it. Staff choose restock and instant per refund. Full → order Refunded; partial → note and per-line flags. "Mark refunded" stays for refunds made outside the app. | Enough Razorpay balance to cover the refund. |
| **Instant refunds** | The refund sheet's "Instant refund" sends `speed: optimum` [3][10]: in the customer's account within minutes, or Razorpay falls back to normal and returns the fee. | On by default. Fee below. |
| **Payment links on WhatsApp** | For an unpaid order (its total) or a typed amount (wholesale, phone orders): `payment-link` creates a Payment Link [11] valid 3 days and the app opens WhatsApp to the customer with it. `payment_link.paid` [12] marks the order paid (a COD order becomes paid online); staff can cancel a link. | Payment Links (works in test mode). |
| **Saved cards** | One Razorpay customer per account [13], made on the first online payment; Checkout gets `customer_id` and `remember_customer` [14], so returning buyers see their saved cards. Card tokens stay with Razorpay (RBI tokenisation). Account deletion deletes the saved cards (Tokens API) and forgets the customer; Razorpay has no API to delete a customer itself. | Saved cards / Flash Checkout on; card tokenisation is activated on request (5–7 working days) [14]. |
| **Dispute alerts** | Every `payment.dispute.*` webhook [15] is recorded on its order and notifies staff with the amount, reason and the respond-by date; open disputes show in red on the order. Evidence goes in through the dashboard. | Subscribe the dispute events. |
| **Refunds made in the dashboard** | `refund.processed` marks a full one refunded, as before; partial ones are left for staff. | — |

## Turn on in the dashboard

| What | Why it matters here | Where |
|---|---|---|
| **Webhook events** | The app needs `payment.captured`, `payment.failed`, `refund.processed`, `refund.failed`, `payment_link.paid`, `payment_link.cancelled`, `payment_link.expired` and all `payment.dispute.*`. | Dashboard → Accounts & Settings → Webhooks (test and live separately) |
| **EMI: credit card, debit card, cardless, Pay Later** | A ₹25,000 phone sells far more easily as "₹2,100 a month". Razorpay lists 40+ banks and lenders [1][2]. They appear in checkout and on the product page once activated (HDFC and SBI are requested separately). | Dashboard → Payment Methods / Affordability |
| **No-cost EMI** | You pay the interest; the customer pays the phone price over 3–6 months. Set it on phones above about ₹10,000 only. The product page says "No-cost EMI available" only for plans Razorpay reports as merchant-subvented: a No Cost EMI *offer* made on the Offers page can't be read through any API [16], so it shows only in checkout. | Dashboard → Affordability → No-cost EMI |
| **Offers (instant bank and card discounts)** | "₹1,000 off on HDFC cards" shows inside checkout and applies by itself. Separate from the app's own coupons; they can combine. Dashboard only [16]. | Dashboard → Offers |
| **Saved cards** | Needed for the saved-cards feature above. | Dashboard → Settings → Checkout (Flash Checkout); ask support for card tokenisation |
| **Auto-capture** | Payments must be captured for the order to count as paid. Keep auto-capture on. | Dashboard → Settings → Payment capture |
| **Payment receipts** | The app already confirms orders and payment links go by WhatsApp (Razorpay's own SMS is off for them), so keep one source to avoid duplicate messages. | Dashboard → Settings → Customer notifications |

## Looked at, not built (2026-10-30)

| Feature | Verdict | Why |
|---|---|---|
| **Turbo UPI** (in-app UPI, no app switch) [17] | later, ask Razorpay | A separate `razorpay_turbo_standard` package, Axis Bank handle, whitelisting by Razorpay's integrations team and on-demand activation; not buildable with test keys alone. |
| **UPI intent** [18] | nothing to do | On by default in Standard Checkout (this account's methods reply has `upi_intent: true`); UPI Collect was retired on Android in Feb 2026, so UPI already means intent. |
| **Magic Checkout** (COD risk scoring, RTO protection) [4][19] | ask Razorpay first | Supported in `razorpay_flutter` (`one_click_checkout`), but on-demand activation, enterprise pricing, `line_items` on every order and public shipping and promotions APIs we'd have to host. The biggest win (COD returns) needs COD on Magic, a separate request. |
| **Payment downtime** webhooks and API [20] | skip | Standard Checkout already warns about downtime and disables instruments that are failing [21]; our own banner would repeat it. |
| **Affordability widget for Android** [22] | covered | A native Android view (not Flutter). `EmiLine` does the same job from the same data. |
| **Debit card / cardless EMI eligibility** (`/customers/eligibility`) [23] | later | On-demand, and covers only debit, cardless and Pay Later, not credit card EMI. |
| **Settlements and instant settlements** [24][25] | later | Settlement reports are in the dashboard; instant settlements are activated on request with their own pricing. Worth it only if cash flow gets tight. |
| **Invoices API** [26] | skip | The API makes only non-GST invoices; GST invoices come from the dashboard. A GST invoice PDF is out of v1 (docs/SPEC.md). |
| **Smart Collect** (virtual bank accounts for NEFT/RTGS) [27] | skip | Activation case by case, and 1% or ₹10 a transfer. A wholesale buyer can transfer to the shop's own account for free, or pay a payment link. |
| **Disputes API: accept / contest with evidence** [28] | later | Needs document uploads; rare enough to answer in the dashboard. The alerts above make sure nobody misses a deadline. |
| **Payments on WhatsApp** [29] | skip | Needs the WhatsApp Business API through a provider. wa.me links with a payment link do the job. |
| **Razorpay POS, UPI Reserve Pay, Route, subscriptions** | skip | POS is a counter terminal (the shop's own UPI QR is free, docs/COSTS.md); Reserve Pay is server-to-server block-and-debit; the rest aren't needed for one shop. |
| UPI QR at the counter | skip | Razorpay QR codes still carry the platform fee; the shop's own UPI QR is free. |

## Fees to keep in mind

About 2% + 18% GST on most domestic methods; corporate and international cards cost more; no setup or annual fee;
refunds don't return the original fee [5][6]. Instant refunds: ₹7.99 (up to ₹1,000), ₹11.99 (₹1,000–₹25,000),
₹14.99 (above ₹25,000), + 18% GST, returned if it falls back to a normal refund [10][30]. Payment links cost the same
as any payment. A bank offer or no-cost EMI you fund comes out of your margin, so set them on high-margin items.
See docs/COSTS.md for the shop's numbers.

## Sources

- [1] Razorpay Affordability Suite: https://razorpay.com/affordability-suite/
- [2] Razorpay Affordability Widget: https://razorpay.com/affordability-widget/
- [3] Razorpay Instant Refunds: https://razorpay.com/instant-refunds/
- [4] Razorpay Magic Checkout: https://razorpay.com/magic/
- [5] Razorpay payment gateway: https://razorpay.com/payment-gateway/
- [6] Razorpay charges guide (third party, 2026): https://kodestudio.in/guides/razorpay-charges-guide
- [7] Methods API (EMI plans, key id only): https://razorpay.com/docs/payments/payment-gateway/s2s-integration/payment-methods/methods-api/
- [8] Create a normal refund: https://razorpay.com/docs/api/refunds/create-normal/
- [9] Idempotent refunds (`X-Refund-Idempotency`): https://razorpay.com/docs/api/refunds/normal-refunds-idempotent/
- [10] Instant refunds: https://razorpay.com/docs/payments/refunds/instant/ and https://razorpay.com/docs/api/refunds/create-instant/
- [11] Create a payment link: https://razorpay.com/docs/api/payments/payment-links/create-standard/ (cancel: https://razorpay.com/docs/api/payments/payment-links/cancel-standard/)
- [12] Payment link webhooks: https://razorpay.com/docs/webhooks/payment-links/
- [13] Customers API: https://razorpay.com/docs/api/customers/create/ (tokens: https://razorpay.com/docs/api/payments/recurring-payments/cards/tokens/)
- [14] Saved cards: https://razorpay.com/docs/payments/payment-methods/cards/features/integrate-saved-cards/ and Android checkout options: https://razorpay.com/docs/payments/payment-gateway/android-integration/standard/integration-steps/
- [15] Dispute webhooks: https://razorpay.com/docs/webhooks/disputes/ (entity: https://razorpay.com/docs/api/disputes/entity/)
- [16] Offers: https://razorpay.com/docs/payments/offers/standard-integration/ and No Cost EMI: https://razorpay.com/docs/payments/payment-methods/emi/no-cost-emi/
- [17] Turbo UPI: https://razorpay.com/docs/payments/payment-methods/upi/turbo-upi/ (Flutter: https://razorpay.com/docs/payments/payment-gateway/flutter-integration/standard/payment-methods/turbo-upi/)
- [18] UPI intent: https://razorpay.com/docs/payments/payment-methods/upi/upi-intent/ and the UPI Collect retirement: https://razorpay.com/docs/announcements/upi-collect-migration/standard-integration/
- [19] Magic Checkout for Flutter: https://razorpay.com/docs/payments/magic-checkout/flutter-integration/
- [20] Payment downtime API: https://razorpay.com/docs/api/payments/downtime/
- [21] Downtime in Checkout: https://razorpay.com/docs/payments/payments/downtime-updates/
- [22] Affordability widget for Android: https://razorpay.com/docs/payments/payment-gateway/emi²/widget/android/
- [23] EMI² eligibility check: https://razorpay.com/docs/payments/payment-gateway/emi²/eligibility-check/
- [24] Settlements API: https://razorpay.com/docs/api/settlements/
- [25] Instant settlements: https://razorpay.com/docs/payments/settlements/instant/
- [26] Invoices FAQ (non-GST through the API): https://razorpay.com/docs/payments/invoices/faqs/
- [27] Smart Collect: https://razorpay.com/smart-collect/ and https://razorpay.com/docs/api/payments/smart-collect/
- [28] Disputes API (accept, contest): https://razorpay.com/docs/api/disputes/ and https://razorpay.com/docs/api/disputes/contest/
- [29] Payments on WhatsApp: https://razorpay.com/docs/payments/whatsapp/integrate/
- [30] Razorpay pricing: https://razorpay.com/pricing/
