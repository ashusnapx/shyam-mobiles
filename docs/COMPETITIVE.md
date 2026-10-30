# Competitive research: what to copy, what to beat

Checked 29 Oct 2026, public sources only. Complaint sites are self-selected, so "frequency" means how often a theme recurs across apps and sources, not a measured rate. `[n]` = Sources.

## 1. Top recurring complaints

Frequency / severity is rated High (H), Medium (M) or Low (L).

1. **Refund limbo: money debited and no order, or a cancelled order not refunded for weeks.** Seen at Flipkart, Amazon, Reliance Digital, Sangeetha, Poorvika and Cashify. H / H. Non-refund is a top-four National Consumer Helpline (NCH) category; Flipkart led NCH e-commerce grievances in FY24 (1.6 lakh) [1], and its Play reviews cite debits with no order [2]. [3][4][15]
2. **Silent delays, fake "out for delivery" or "attempted" statuses, no proactive updates.** Seen at Croma, Reliance Digital, Sangeetha and Flipkart. H / H. Delayed delivery is a top NCH category [1]. [3][4][5][26]
3. **Can't reach a human.** Flipkart's chatbot loops and, anecdotally, has no human agents between 6 pm and 9 am. Flipkart says the bot handles about two-thirds of contacts. Croma's IVR waits run to 45 minutes. Sangeetha's calls and emails go unanswered. H / H. [4][5][6]
4. **Fake, wrong or used phone in the box, or an IMEI that doesn't match the invoice.** In a Sep 2026 case, a consumer commission ordered Flipkart to refund ₹1,43,335 for a fake "iPhone 14 Pro" and rejected Flipkart's "open-box delivery" defence. M / very high. [7]
5. **Cancelled for stock days after payment, while the listing still says "in stock".** Seen at Reliance Digital and Sangeetha. M / H. [3][4]
6. **Price cut at the doorstep.** Delivery agents cut exchange values. Inventiva's reading of Cashify complaints puts pickup cuts at 20–50% below the online quote. M / H. [9][10]
7. **Hidden or late fees.** Examples are platform fees, "offer handling" fees on iPhone orders (₹355 reported, *unverified*), and "no-cost" EMI that still carries a processing fee plus GST. India's consumer regulator now fines drip pricing. In Baymard's US survey, extra costs are the top reason for abandoning checkout (40%). M / M. [11][12][13]
8. **Return rules for phones unclear at purchase.** Phones are replacement-only on the big marketplaces, and accepting an open-box delivery removes later damage claims. M / H. [8][23]
9. **No self-serve cancel button** (Sangeetha). M / M. [4]
10. **Repairs: the quote changes, the work is slow, or the device comes back worse** (Cashify, anecdotal). L–M / H. [10]
11. **The OTP SMS never arrives** (DLT template or sender ID problems). L–M, but it blocks sign-in completely. [16]

*Unverified:* app-size or lag complaints about Flipkart or Amazon (I found no recent public data). Play ratings for the Croma, Reliance Digital, Poorvika and Sangeetha apps (Poorvika's iOS listing has only 1 rating) [18]. Nothing has no India store app; it sells through Flipkart and partner retailers [21].

## 2. Patterns worth adopting

- **Server-confirmed payment state, with pending as its own screen.** UPI intent has no redirect back, so the webhook or a poll is the only truth [14]. The spec already does this.
- **Variant chips that show the price difference, with out-of-stock options visible but disabled.** The mockup already shows "+₹12,000".
- **Open-box handover.** Check the seal, match the IMEI on the box against `*#06#`, and power the phone on before the customer accepts [8].
- **Pickup with a "ready" signal.** Apple says most in-stock pickups are ready within an hour. Reliance auto-cancels pick-at-store orders after 48 h [19][18].
- **Free setup at collection** (Apple Personal Setup) [19].
- **One timeline per order, with a carrier link and milestone alerts.** The Shop app offers live tracking and delivery notifications [20].
- **Repair price and warranty in writing.** Cashify gives 6 months on screens, 3 months on other parts, and 7-day money-back [10].
- **Exchange as model → condition questions → estimate, with the final value set at inspection.** This is only honest if the deduction rules are shown first [24][19].
- **A human always one tap away.** Apple's checkout has a chat button [19].

## 3. Where a single store beats the giants

1. **Same-day delivery and pickup in town.** Reliance and Croma sell same-day only with cutoffs and select pincodes; Poorvika advertises 2-hour delivery [18][25]. Our staff can deliver across town. Pickup paid by the shop's UPI QR costs ₹0 in gateway fees, against ₹2,360 for online payment on a ₹1 lakh phone (COSTS.md).
2. **A named person on WhatsApp during store hours**, e.g. "Replies in 15 min, 10 am–9 pm". `wa.me` links cost nothing. Automated template messages run about ₹0.115 + GST each (vendor figure; check against Meta's rate card) [17].
3. **Proof it's genuine before and at delivery.** The IMEI is already recorded at packing (mockup screen 6). Show it before dispatch, tell the customer how to check it, and have staff open the box at the door. This answers complaint 4.
4. **No surprise money.** The price shown is the price paid: no platform or COD fees. Exchange and repair prices are agreed in the shop before the customer commits, with no doorstep haggling.
5. **Refunds you can see.** One store means a short "needs refund" list. Promise refunds within 24 h and show each refund step in the order timeline.
6. **Stock is real.** There is one shelf, and stock changes are atomic (spec rule 9), so there are no "cancelled for stock" orders days later. Say so on the product page.
7. **Repair work starts only after the customer approves the quote.** The old part goes back to the customer, and the warranty is written on the booking.

## 4. Recommendations

**Δ SPEC** / **Δ MOCKUP** marks a v1 item that needs a change to SPEC.md or mockup.html.

| # | Feature | Answers | Phase | Effort | Notes |
|---|---|---|---|---|---|
| 1 | WhatsApp + Call buttons on the product, order and repair screens, with a prefilled `wa.me` message (order or repair number, or product + variant) | 3 | v1 | S | **Δ SPEC** `store_settings.whatsapp_phone` (or reuse `store_phone`). **Δ MOCKUP** screens 3 and 7 (the order screen already has both buttons) |
| 2 | Admin "Send update on WhatsApp" on order and repair detail: opens `wa.me/<customer phone>` with the status text, sent from the shop phone | 2 | v1 | S | Covers for the lack of push in v1, with no API and no cost. **Δ SPEC** admin flow. **Δ MOCKUP** screen 9 |
| 3 | Same button as "Confirm COD order" before packing | 2, COD returns (RTO) | v1 | S | COD orders come back undelivered (RTO) about 26% of the time; electronics run 8–18% (vendor estimates [22]) |
| 4 | Refund visibility: `order_events` on paid-then-cancelled ("Refund due within 24 h") and on `refund.processed` (with the refund id). Result-screen copy: "If money left your account, we confirm or refund it automatically" | 1 | v1 | S | **Δ SPEC** `cancel_order`, `mark_order_paid` (late path), `mark_order_refunded` write events |
| 5 | Returns, warranty and genuine-product policy as one text block, shown on the product page, checkout and order screen | 4, 8 | v1 | S | **Δ SPEC** `store_settings.returns_note` (like `repair_note`). **Δ MOCKUP** screen 3. Razorpay activation may also require a refund policy page (*unverified*) |
| 6 | IMEI shown once packed, plus "How to check: dial `*#06#`, match the box label" and a brand warranty-check link. Local drops: "We open the box in front of you" | 4 | v1 | S | Data already exists. **Δ MOCKUP** screen 6 copy |
| 7 | Fee honesty in the cart: "No platform, COD or packing fees". EMI line: "Any bank interest or fee is shown by Razorpay before you pay" | 7 | v1 | S | **Δ MOCKUP** screens 3–5, copy only |
| 8 | Courier "Track" deep link (a URL template per courier) next to "Copy" | 2 | v1 | S | **Δ SPEC** courier list. **Δ MOCKUP** screen 6 |
| 9 | Finish the interrupted action after sign-in: add-to-cart or buy-now completes on return from `/sign-in?from=` | Forced sign-in (Baymard: 18% abandon over required accounts [13]) | v1 | S | **Δ SPEC** Navigation |
| 10 | OTP autofill (SMS User Consent API), phone-number hint, and "Use email instead" after 30 s | 11 | v1 | S | One dependency (e.g. `smart_auth` [16]). **Δ SPEC** Stack |
| 11 | UPI intent on Android 11+: add a `<queries>` entry for the `upi` scheme and UPI app packages, then test GPay, PhonePe and Paytm on real devices | 1 | v1 | S | Without it, UPI apps don't appear [14]. Engineering checklist item |
| 12 | Repair quote shown prominently, with copy "Work starts only after you approve this price", warranty days and part type | 10 | v1 | S | **Δ SPEC** `repair_bookings.warranty_days`, `part_type`. **Δ MOCKUP** repair detail. The approval itself happens by call or WhatsApp |
| 13 | Size and speed budget: download ≤ 25 MB, cold start ≤ 2 s on a ₹10k phone, Sentry slow-screen alerts | Performance (*unverified* complaints) | v1 | S | These are our own targets, not research findings |
| 14 | Store pickup: "Pay at store", "Ready for pickup", auto-cancel after N days | 2, 7 | v1.1 | M | The biggest differentiator, and it saves the 2.36% fee. Consider pulling it into v1 |
| 15 | In-app repair quote approval (`approve_repair_quote` RPC; `in_progress` blocked until approved) | 10 | v1.1 | M | Replaces the call-based approval in row 12 |
| 16 | Push notifications (FCM) for order and repair milestones | 2 | v1.1 | M | Retires row 2 for routine updates |
| 17 | Auto-refund "needs refund" orders via the Razorpay Refunds API from an Edge Function | 1 | v1.1 | M | Removes the manual step |
| 18 | Own-staff same-day delivery by pincode, with a cutoff, named rider and open-box handover | 2, 4 | v1.1 | M | Needs an `out_for_delivery` event |
| 19 | Sealed-box photo with the IMEI label, uploaded at packing and shown on the order | 4 | v1.1 | M | Storage path on `order_items` |
| 20 | Search: typo tolerance (`pg_trgm` fallback) and RAM, storage and 5G filters from variant attributes | Search pattern | v1.1 | M | Fixes queries like "samsng" or "iphone16" |
| 21 | Exchange estimate: model + 4 condition questions gives a range, with the final value set in store and the deduction rules shown first | 6 | v1.1 | M | |
| 22 | WhatsApp API: automated templates and OTP fallback | 2, 11 | later | M | About ₹0.115 per message [17] |
| 23 | Repair price ranges per model and issue | 10 | later | M | |
| 24 | App Links, so shared product links open in the app | Sharing | later | M | Needs a domain and a web page |

Already in the spec or mockup and matching best practice (no change needed): pending and failed payment states with retry, the 15-minute stock hold, late-payment revival, totals computed on the server, the COD cap, the order timeline, stock badges, variant price differences, and the free-delivery threshold on the product page.

## 4b. Offers research (2026-10-30)

Indian phone retailers sell on offers more than on price: Croma, Reliance Digital and Vijay Sales run a few big
festive sales a year (Independence Day, Diwali, Black Friday) with no-cost EMI, bank-card discounts and exchange
bonuses on top [18][19]; coupon codes circulate on WhatsApp and deal sites [20]. Coupon-abuse guides agree on the
basics: enforce every limit in the backend, cap per-customer use, set start and end dates, use a minimum order, and
decide which offers stack [21][22].

Built now (SPEC, "Offers"): coupons and automatic sales in one engine, scoped to the whole order or any mix of
products, categories, brands and product groups; percent with cap, flat, free delivery; min order, dates, total and
per-customer limits, first order only, online only, hidden and personal codes; one offer per order; referrals paid as
personal coupons only after the friend's order is delivered; banners that follow a sale automatically.

Next, ranked:

| # | Feature | Why | Size |
|---|---|---|---|
| 25 | "EMI from ₹X/month" on phones, and Razorpay's card offers shown at payment | The big chains lead with EMI and bank discounts [18][19]; Razorpay already runs both | S |
| 26 | Countdown on sale banners ("ends in 5 h") | Festive sales are short and time-boxed [19] | S |
| 27 | Combos: phone + case + guard at a bundle price | A ₹1,299 case is easy to add to a ₹25,000 phone; needs a "bought together" rule in the engine | M |
| 28 | Spend tiers ("₹200 off over ₹2,000, ₹500 off over ₹5,000") and buy-2-get-1 on accessories | Common in accessories; one more rule type in the engine | M |
| 29 | Back-in-stock and price-drop alerts | Needs push notifications (row 16) | M |
| 30 | Exchange bonus on top of the estimate (row 21) | Every big chain advertises it [18] | M |
| 31 | Reviews and ratings | Trust on high-value items; needs moderation | M |
| 32 | Loyalty points, gift cards | Later: margins and accounting first | L |

## 5. Sources

1. MediaNama, NCH e-commerce grievances FY2023-24: https://www.medianama.com/2024/12/223-flipkart-leads-consumer-complaints-in-e-commerce-over-1-5-lakh-grievances-registered-in-fy-2023-24/
2. Quash, Flipkart release health (Oct 2026): https://quashbugs.com/release-health/flipkart
3. Reliance Digital: https://voxya.com/consumer-complaints/amount-deducted-but-order-not-placed-/260661 · https://techenclave.com/t/reliance-digital-cancelled-my-order-2-times/266501
4. Sangeetha (596 complaints, 429 unresolved, Oct 2026): https://www.consumercomplaints.in/sangeetha-mobiles-b100213 · https://www.consumercomplaints.in/sangeetha-mobiles-paid-iphone-15-order-kept-on-hold-repeated-delivery-delays-and-no-proactive-communication-c3543904 · https://www.desidime.com/discussions/is-sangeethamobile-com-online-store-is-2103424
5. Croma: https://techenclave.com/t/croma-feedback-discussion/399281 · https://www.desidime.com/discussions/help-croma-didn-t-deliver-a-c-but-marked-as-delivered
6. Flipkart support: https://techenclave.com/t/what-is-the-customer-care-number-of-flipkart-how-to-talk-to-a-human-being/394428 · https://stories.flipkart.com/flipkart-customer-experience-qa-suresh-john
7. Fake iPhone ruling: https://www.analyticsinsight.net/news/consumer-panel-orders-flipkart-refund-after-fake-iphone-delivery
8. Flipkart Open Box Delivery: https://www.flipkart.com/pages/open-box-delivery-tnc · https://techenclave.com/t/things-to-do-before-accepting-open-box-delivery-from-flipkart-cannot-return-once-accepted/264323
9. Exchange deductions: https://www.desidime.com/discussions/amazon-cheating-in-the-name-of-mobile-exchange · https://voxya.com/consumer-complaints/amazon-malpractice-to-earn-extra-from-rejected-exchange-order/100013
10. Cashify: https://www.inventiva.co.in/trends/cashify-built-a-%e2%82%b91000-crore-business-on-used-phones-there-are-93-cashify-complaints-on-one-consumer-portal-alone/ · https://techenclave.com/t/need-advice-regarding-a-repair-issue-with-my-macbook-m1-pro-and-cashify/427022 · https://www.cashify.in/faq/category/mobile-repair-faqs
11. No-cost EMI costs: https://www.businesstoday.in/amp/personal-finance/banking/story/is-no-cost-emi-really-free-when-should-you-opt-for-it-pros-cons-hidden-costs-467006-2025-03-06
12. Fees and drip pricing: https://smartprix.com/bytes/if-youre-buying-an-iphone-17-on-flipkart-or-amazon-be-ready-to-pay-extra-fees · https://ts.yourstory.com/2024/08/flipkart-introduces-platform-fees-on-its-ecommerce-platform · https://www.business-standard.com/industry/news/ccpa-fines-indigo-zepto-bookmyshow-dark-patterns-quick-commerce-penalty-126080600580_1.html
13. Baymard checkout abandonment (US survey): https://baymard.com/lists/cart-abandonment-rate
14. UPI intent: https://razorpay.com/docs/payments/payment-methods/upi-intent/android · https://developers.google.com/pay/india/api/android/overview
15. UPI refund timelines: https://payu.in/blog/?p=14665
16. OTP delivery and autofill: https://thenextweb.com/news/heres-why-youre-not-receiving-otps-in-india · https://pub.dev/packages/smart_auth
17. WhatsApp API pricing, India: https://chatmaxima.com/whatsapp-api-pricing/india/ · https://developers.facebook.com/docs/whatsapp/pricing
18. Same-day and pickup: https://www.reliancedigital.in/page/same-day-free-delivery-tc · https://www.croma.com/lp-express-delivery · https://apps.apple.com/app/id1539862976
19. Apple: https://www.apple.com/ca/shop/personal-setup · https://9to5mac.com/2022/07/30/apple-iphone-checkout-page/ · https://www.techrepublic.com/article/news-apple-store-ai-shopping-assistant/
20. Shop app tracking: https://help.shopify.com/en/manual/online-sales-channels/shop/customer-experience
21. Nothing in India: https://support.nothing.tech/hc/en-us/articles/38494767092881-Where-can-I-buy-Nothing-and-CMF-products-in-India
22. COD RTO (vendor estimates): https://razorpay.com/blog/cash-on-delivery-and-the-challenges/ · https://base.com/en-IN/blog/?p=22444
23. Phones replacement-only (2016): https://techenclave.com/t/amazon-india-ends-return-policy-for-mobile-phones/235231
24. Flipkart exchange and IMEI: https://flipkart.com/pages/sell-back-faq · https://digitalterminal.in/amp/story/e-commerce/flipkart-minutes-launches-fast-smartphone-exchange-service
25. Reliance Digital 30-minute delivery: https://m.greaterkashmir.com/article/reliance-digital-offers-30-minute-delivery-for-samsung-galaxy-s25-series/369529/amp
26. Croma "out for delivery" stall: https://voxya.com/consumer-complaints/order-delayed-and-not-delivered-no-cancellation-or-refund/252492
- [18] Croma vs Reliance Digital comparison: https://dealifyhq.com/compare/croma-vs-reliance-digital.html
- [19] Electronics sales calendar 2026: https://www.myrupaya.in/post/upcoming-ongoing-electronics-sales-2026-best-deals-on-croma-reliance-digital-flipkart
- [20] Croma vs Reliance Digital coupons (Zoutons): https://zoutons.com/news/croma-vs-reliance-digital-where-buy-electronics-india
- [21] Voucherify, preventing coupon fraud: https://www.voucherify.io/blog/how-to-prevent-coupon-fraud-and-abuse
- [22] Fingerprint, preventing promo abuse: https://fingerprint.com/blog/prevent-coupon-promo-abuse-increase-sales/
