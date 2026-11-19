# Growth playbook: honest sales levers for Shyam Mobiles

The owner asked for "the hidden sales hacks of e-commerce apps, MBA books and notes". This is that list, filtered for
one GST-registered shop in Waidhan: price-sensitive, WhatsApp-first buyers, COD and PhonePe, retail, wholesale and
repairs. Every lever here works by telling the customer something true at the right moment. Anything that only works
by misleading is left out, and the law (§3) forbids most of it anyway.

**Already built, not repeated here:** MRP strike and "You save ₹X", the best-offer line, free-delivery progress, the
accessory rail in the cart, recently viewed, the trust strip, WhatsApp cart, referrals, coupons, the real low-stock
badge, back-in-stock alerts, wishlist and reorder.

## 1. The ranking (expected sales impact ÷ effort, for this shop)

Impact and effort are 1 (low) to 5 (high), and the score is impact ÷ effort. 🛠 = built in this round (§2).
**Owner** = needs the owner's decision or numbers before it can ship.

| # | Lever | Principle | Learned from | Impact | Effort | Score | Status |
|---|---|---|---|---|---|---|---|
| 1 | Re-engagement pushes (cart left, wishlist price drop) | Hooked loop (trigger), loss aversion | Amazon, Myntra, Blinkit | 4 | 2 | 2.0 | 🛠 d |
| 2 | Verified-purchase reviews | Social proof (Cialdini), uncertainty reduction | Amazon "Verified Purchase", Flipkart "Certified Buyer" | 5 | 3 | 1.7 | 🛠 a |
| 3 | "N bought this week" + frequently bought together | Social proof; AOV via bundling | Amazon "bought in past month", "Frequently bought together" | 4 | 3 | 1.3 | 🛠 b |
| 4 | Post-purchase "Protect your new phone" | Commitment and consistency; peak moment | Amazon "Complete your setup", Croma protection | 3 | 2 | 1.5 | 🛠 e |
| 5 | Exchange your old phone | Mental accounting (reduces the pain of paying) | Flipkart and Amazon exchange, Cashify | 4 | 3 | 1.3 | 🛠 c |
| 6 | Campaign calendar: festivals, shop days, seasons; one-tap dated offer; auto-applied code | Timing, scarcity that is real (a dated sale), defaults | Flipkart Big Billion Days, Amazon Great Indian Festival | 4 | 1 | 4.0 | 🛠 Admin → Settings; **Owner**: which days get offers, season dates |
| 7 | Bundles ("Phone + case + guard, ₹X less") | Bundling, price-bundle anchoring | Amazon combos, Meesho sets | 4 | 3 | 1.3 | **Owner**: which bundles and the discount; touches pricing.ts, so a separate task |
| 8 | Wholesale quantity tiers ("10+ pcs: ₹X each") | Anchoring, volume discount | Udaan, IndiaMART | 4 | 3 | 1.3 | **Owner**: tier prices; pricing.ts change, separate task |
| 9 | Good–better–best variant order (cheapest, most chosen, top) with a real "Most chosen" tag | Decoy and compromise effect | Apple, Flipkart variant pickers | 3 | 2 | 1.5 | After (b): "most chosen" needs the sales counter |
| 10 | Hindi UI | Processing fluency; trust in own language | Meesho, PhonePe | 4 | 4 | 1.0 | **Owner**: approve translations (about 900 strings) |
| 11 | Scratch card after a paid order (real, pre-funded rewards) | Variable reward (Hooked), reciprocity | GPay, PhonePe | 3 | 3 | 1.0 | **Owner**: monthly budget; odds shown |
| 12 | Free screen-guard fitting with a phone, said up front | Reciprocity | Local shops, Croma | 3 | 1 | 3.0 | **Owner**: yes or no; then one line on phone pages |
| 13 | "Pick up in shop today" | Immediacy, lower risk | Croma, Reliance Digital | 3 | 2 | 1.5 | **Owner**: counter process |
| 14 | Repair → upgrade nudge ("repair costs ₹X; exchange gives ₹Y") | Anchoring against a real alternative | Cashify | 2 | 2 | 1.0 | After (c) has real estimates |

Order of work: the 🛠 items first (they need no owner numbers), then 6 and 12 the day the owner answers (no code or
copy only), then 7 and 8 together (one pricing.ts change, its own vectors).

## 2. What we build, item by item

**(a) Verified-purchase reviews.** Principle: social proof from people like me. Amazon and Flipkart show it on every
page. We build: 1–5 stars, optional text (≤ 1,000), up to 3 photos compressed like admin photos. Only a customer with
a *delivered* order of that product can review, one review per customer per product (editing replaces it). Staff can
hide an abusive one, never edit it. The product page shows the average, the count, a 5-to-1 star breakdown and the top
reviews (photos and longer text first). Tiles show "★ 4.3 (12)" only from 3 reviews up. Guardrail: E-Commerce Rules
7(2) bar the shop from posting reviews as a consumer. Low ratings are never hidden for being low (IS 19000:2022
integrity): staff hide only abuse, personal data or spam, and the review's author can still see it.

**(b) Honest social proof.** "N bought this week" counts units on orders that were paid or delivered in the last 7
IST days. A trigger keeps the counter, and a cancelled or refunded order is taken back out. It shows only when N ≥ 3,
because "1 bought" isn't proof of anything. "Frequently bought together" comes from real co-purchase counts (a pair seen
at least twice), on accessory pages only: phone pages and phone carts get the "Complete your pack" bundle card
instead (another engineer, owner's call). Guardrail: false urgency covers "falsely depicting popularity". These
numbers are counted, never typed in.

**(c) Exchange your old phone.** Principle: mental accounting (the old phone pays part of the new one). Flipkart and
Amazon do it at checkout. We build: an "Exchange your old phone" sheet on phone pages and in the cart: brand, model,
age, condition chips, up to 3 photos. It saves a request staff see in Admin, with "Send on WhatsApp" too. **No price
appears until the shop gives one.** Staff reply with an estimate the customer sees in the app, worded "estimate, final
after the shop checks the phone". Guardrail: bait and switch, and COMPETITIVE.md complaint 6 (cuts at the doorstep).
The deduction rules are the owner's, shown before the estimate (**owner**: write them).

**(d) Gentle re-engagement pushes.** Principle: the Hooked loop's external trigger, and loss aversion ("the price you
wanted dropped"). We build: a cart left for 24 h with items in stock gets one push. A wishlist item whose price dropped
gets one push. At most 1 marketing push per customer per 3 days, none from 9 pm to 9 am IST. Both respect the new
"Offers & reminders" switch in Account → Notifications (on for new customers, off in one tap). An hourly job sends them, and
one transaction checks the switch, the cap and the push's own id, so nothing goes twice. Guardrail: nagging. The
guideline says users must be able to switch such notifications off, hence the switch, the cap and the quiet hours.

**(e) Post-purchase upsell.** Principle: commitment and consistency; the "unboxing" moment. We build: when a phone order
is delivered, the order page shows "Protect your new phone" (cases, guards and chargers that fit, from the existing
fits logic). One push 2 to 3 days after delivery, only when something in stock fits, and it counts toward the 3-day
cap. Guardrail: basket sneaking. Nothing is ever added to the cart for the customer.

## 3. Guardrails: what the law forbids

**Guidelines for Prevention and Regulation of Dark Patterns, 2023** (CCPA, notified 30 Nov 2023 under s.18 of the
Consumer Protection Act 2019). They apply to every platform, seller and advertiser in India. Annexure I lists 13
patterns. Each row below says how this app stays clear of it:

| Pattern | What it bans | Our rule |
|---|---|---|
| False urgency | Fake scarcity or popularity ("only 2 left" when 50 are) | Low-stock badge reads real stock; "bought this week" is counted, N ≥ 3; no countdowns except a real sale's end date |
| Basket sneaking | Items, donations or charges added at checkout without consent; pre-ticked boxes | Rails and sheets only suggest; the cart changes only on the customer's tap |
| Confirm shaming | Guilt or ridicule to push a choice ("No, I like overpaying") | Neutral copy: "Not now", "Turn off" |
| Forced action | Making the customer buy something else or share data they didn't intend to | Exchange and reviews are optional; reviewing needs no extra data |
| Subscription trap | Hard or hidden cancellation | No subscriptions; the offers switch is one tap |
| Interface interference | Hiding relevant information, or a symbol that does the opposite of what it shows | Equal-weight Yes/No; the X always closes |
| Bait and switch | Advertising one thing and serving a costlier one | No exchange price until the shop gives one; an estimate says it is one |
| Drip pricing | Showing part of the price and revealing the rest later | "Inclusive of all taxes"; the delivery fee is shown in the cart before checkout (existing) |
| Disguised advertisement | Ads dressed as reviews or content | Staff never write reviews; banners look like banners |
| Nagging | Repeated, persistent requests; must be possible to switch off | 1 marketing push per 3 days, quiet hours, the switch |
| Trick question | Confusing wording such as double negatives | "Offers & reminders: on/off", never "Don't not send" |
| SaaS billing | Silent recurring charges | Not applicable (no recurring billing) |
| Rogue malware | Scareware | Not applicable |

The CCPA advisory of 5 Jun 2025 told platforms to self-audit for these within 3 months, and on 20 Nov 2025 it
published the 26 platforms that declared compliance. **Owner:** keep §3 as our self-audit record and re-check it each
release.

**Consumer Protection (E-Commerce) Rules, 2020** (G.S.R. 462(E), 23 Jul 2020; Rule 4(1) substituted 17 May 2021). We
sell our own stock, so we are an *inventory e-commerce entity* (Rule 7) as well as bound by Rule 4:

- 4(3): no unfair trade practice. 4(11)(a): no price manipulation for unreasonable profit, so "was ₹X" must be a real
  MRP.
- 4(4): grievance officer named in the app (already on the policy pages).
- 4(9): consent to a purchase only by explicit, affirmative action, never pre-ticked. Hence suggestions never fill the cart.
- 7(1)(e): total price in a single figure with its breakup (the cart and checkout already do this).
- 7(2): the shop must not pose as a consumer to post reviews, or misstate quality. Reviews are verified purchases only.
- Country of origin and other material details go on the product page (the specs).

**Also relevant:** BIS IS 19000:2022, *Online consumer reviews* (in force 25 Nov 2022, voluntary). Its principles are
integrity, accuracy, privacy, security, transparency, accessibility and responsiveness. The DPDP Act 2023 (see
SECURITY.md §4) applies to review photos and exchange photos, which are personal data. They are kept only as long as
the review or request, and both are deleted with the account. **Owner:** confirm with the CA or lawyer that "Offers &
reminders" may default to on. Android 13+ asks the customer for notification permission anyway, and the guideline only
requires an easy off switch.

## 4. Sources (checked 2026-11-19)

- Dark Patterns Guidelines 2023, official PDF: https://consumeraffairs.nic.in/sites/default/files/The%20Guidelines%20for%20Prevention%20and%20Regulation%20of%20Dark%20Patterns%2C%202023.pdf
  (notified 30 Nov 2023; summaries: AZB & Partners, 6 Dec 2023, https://www.azbpartners.com/bank/a-new-dawn-for-dark-patterns/ ;
  K&S, https://ksandk.com/md/newsletter/safeguarding-consumer-rights-dark-patterns-guidelines-2023/)
- CCPA self-audit advisory, PIB 7 Jun 2025: https://www.pib.gov.in/PressReleasePage.aspx?PRID=2134765 ; 26 platforms'
  declarations, PIB 20 Nov 2025: https://www.pib.gov.in/PressReleasePage.aspx?PRID=2191948
- Consumer Protection (E-Commerce) Rules 2020, text with amendments: https://www.legitquest.com/act/consumer-protection-e-commerce-rules-2020/91C8 ;
  summary: https://www.indialaw.in/blog/civil/consumer-protection-e-commerce-rules/
- IS 19000:2022 online reviews, PIB 12 Dec 2022: https://pib.gov.in/PressReleasePage.aspx?PRID=1882828
- Competitor patterns and exchange complaints: docs/COMPETITIVE.md (rows 21, 30, 31; complaint 6).
