# Razorpay: what it offers and how Shyam Mobiles uses it

Checked 2026-10-30. Razorpay changes partners and fees often, so confirm each item on the dashboard or with your
Razorpay account manager before you rely on it. Test everything in Test Mode first.

## In use today

- **Standard Checkout** in the app (`razorpay_flutter`): UPI, cards, netbanking, wallets. The server creates the
  Razorpay order (`create-payment`), checks the signature (`verify-payment`), and the webhook (`razorpay-webhook`)
  records `payment.captured`, `payment.failed` and `refund.processed`. The amount always comes from the database, with
  any offer applied, never from the phone.

## Turn on in the dashboard (no code)

| What | Why it matters here | Where |
|---|---|---|
| **EMI: credit card, debit card, cardless, Pay Later** | A ₹25,000 phone sells far more easily as "₹2,100 a month". Razorpay lists 40+ banks and lenders [1][2]. They appear in the app's checkout automatically once activated. | Dashboard → Payment Methods / Affordability |
| **No-cost EMI** | You pay the interest (the bank gives a discount equal to it); the customer pays the phone price split over 3–6 months. Big chains lead with it. Set it on phones above about ₹10,000 only. | Dashboard → Affordability → No-cost EMI |
| **Offers (instant bank and card discounts)** | "₹1,000 off on HDFC cards" shows inside checkout and applies by itself. You choose who funds it. Separate from the app's own coupons, and they can combine. | Dashboard → Offers |
| **Instant refunds** | Money back in minutes instead of 5–7 days, which builds trust for a new shop [3]. Each instant refund has a small fee: check the current rate. | Dashboard → Settings → Refunds |
| **Auto-capture** | Payments must be captured for the order to count as paid. Keep auto-capture on. | Dashboard → Settings → Payment capture |
| **Payment receipts** | Razorpay can SMS or email a receipt; the app already confirms orders, so keep one source to avoid duplicate messages. | Dashboard → Settings → Customer notifications |

## Worth building (ranked)

| # | Feature | What it does for the shop | Size |
|---|---|---|---|
| 1 | **"EMI from ₹X/month" on the product page** | Shows the lowest monthly EMI (and "No-cost EMI" when set) before checkout, from Razorpay's EMI plans for this account, cached daily by an Edge Function. Razorpay's own Affordability Widget does this on websites [2]; the app needs its own small version. | S–M |
| 2 | **Refund from the admin screen** | One button on a cancelled or returned order calls Razorpay's Refunds API (full or one item); the webhook then marks it refunded. Replaces logging in to Razorpay and pressing "Mark refunded". | M |
| 3 | **Payment links on WhatsApp** | For wholesale and phone orders: staff create a link for an amount, send it on WhatsApp, and the order turns paid when the customer pays (`payment_link.paid` webhook). Fits the bulk-enquiry button. | M |
| 4 | **Saved cards** | Create a Razorpay customer for each account, so returning buyers see their saved card or UPI ID (RBI-compliant tokens; no card data with us). | S |
| 5 | **COD risk and RTO protection** | Razorpay's Magic Checkout scores COD risk, nudges buyers to prepay, and can reimburse verified COD returns [4]. Magic is built for websites; ask Razorpay whether it's available for a native Android app before building. COD returns are the biggest hidden cost for phone shops. | ask first |
| — | UPI QR at the counter | Razorpay QR codes still carry the platform fee. For in-store payments the shop's own UPI QR is free (docs/COSTS.md), so don't use Razorpay for this. | skip |
| — | Route, subscriptions, payroll, POS | Not needed for one shop. | skip |

## Fees to keep in mind

About 2% + 18% GST on most domestic methods; corporate and international cards cost more; no setup or annual fee;
refunds don't return the original fee [5][6]. A bank offer or no-cost EMI you fund comes out of your margin, so set
them on high-margin items. See docs/COSTS.md for the shop's numbers.

## Sources

- [1] Razorpay Affordability Suite: https://razorpay.com/affordability-suite/
- [2] Razorpay Affordability Widget: https://razorpay.com/affordability-widget/
- [3] Razorpay Instant Refunds: https://razorpay.com/instant-refunds/
- [4] Razorpay Magic Checkout: https://razorpay.com/magic/
- [5] Razorpay payment gateway: https://razorpay.com/payment-gateway/
- [6] Razorpay charges guide (third party, 2026): https://kodestudio.in/guides/razorpay-charges-guide
