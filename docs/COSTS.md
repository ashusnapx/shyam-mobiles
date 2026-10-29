# Cost to operate

Update this file in the same change that adds or swaps any paid service. Prices were checked on 2026-10-28. Re-check them before budgeting.

Assumption: $1 = ₹88. All rupee figures include 18% GST unless marked otherwise.

## Fixed costs

| Item | Plan | Cost | Notes |
|---|---|---|---|
| Supabase (prod) | Pro | $25/mo ≈ ₹2,200 | The Free tier pauses after 1 week without activity, so production can't run on it. Pro includes $10 compute credit (covers the Micro instance), 100k MAU, 8 GB DB, 100 GB storage, 250 GB egress, 2M function calls. The spend cap is on by default. |
| Supabase (dev/staging) | Free | ₹0 | Up to 2 active free projects. |
| Apple Developer | Deferred | ₹0 now ($99/yr ≈ ₹725/mo when iOS starts) | v1 is Android only. |
| Google Play | One-time | $25 ≈ ₹2,200 once | |
| Transactional email (Resend) | Free | ₹0 | 3,000/mo, 100/day. Supabase's built-in SMTP is only for testing, so production auth email needs custom SMTP. Pro is $20/mo for 50k. |
| SMS DLT registration | Per operator portal | one-time, ~₹5,900 incl. GST (varies by portal) | Required before any OTP SMS reaches Indian numbers. Unverified estimate; confirm with the chosen portal. |
| Sentry (crash reporting) | Developer (free) | ₹0 | 5k errors/mo. Team plan ~$26/mo if exceeded. Unverified; check sentry.io/pricing. |
| Codemagic (iOS + Android store builds) | Free | ₹0 | ~500 macOS build minutes/mo, enough for ~30 builds. Unverified; check codemagic.io/pricing. |
| GitHub Actions (CI checks) | Free | ₹0 | 2,000 Linux minutes/mo on private repos; checks run on Linux. |
| **Total fixed** | | **≈ ₹2,200/mo** + ₹8,100 one-time | |

## Variable costs

| Driver | Unit cost | Source |
|---|---|---|
| Razorpay, any domestic method (UPI, cards, netbanking, wallets, EMI) | 2% + 18% GST = **2.36% of the amount paid** | razorpay.com/pricing. UPI has zero MDR, but Razorpay still charges its 2% platform fee. |
| Razorpay, corporate cards | 2.15% + GST = 2.54% | |
| Razorpay refunds, setup, AMC | ₹0 | The fee on a refunded payment is **not** returned. |
| COD | ₹0 gateway fee | Real costs: courier COD charges, failed-delivery returns (RTO), cash handling. Not modelled yet. |
| SMS OTP (MSG91, India) | ~₹0.15–0.25 + GST per SMS | Third-party estimates; confirm on msg91.com. Budget 1.3 SMS per phone login (resends). |
| Email OTP / Google sign-in | ₹0 | Inside the Resend free tier and Supabase Auth. |
| Supabase over quota | $0.00325/MAU over 100k; $0.09/GB egress over 250 GB; $0.0213/GB storage over 100 GB; $2/1M function calls over 2M | Not reached at the scenarios below. |

## Scenarios (monthly)

Average order value: ₹15,000 (phones dominate). Online/COD split 70/30. Phone OTP logins = 50% of logins.

| | Launch | Growing |
|---|---|---|
| Orders | 100 | 1,000 |
| Online GMV | ₹10.5 lakh | ₹1.05 crore |
| Logins | 1,000 | 10,000 |
| Razorpay (2.36%) | ₹24,780 | ₹2,47,800 |
| SMS OTP (650 / 6,500 SMS × ~₹0.24) | ₹160 | ₹1,560 |
| Fixed | ₹2,200 | ₹2,200 (+₹1,760 if Resend Pro) |
| **Total** | **≈ ₹27,100** | **≈ ₹2,51,600** |
| Infra excluding payments | ≈ ₹2,400 | ≈ ₹5,500 |

The gateway fee is about 90% of the bill. Infrastructure is a rounding error by comparison.

## Optimisation levers (ranked by impact)

1. **Negotiate the Razorpay rate.** Custom pricing is available at volume. Even 2% → 1.6% saves ~₹50k/mo at "Growing". Also compare gateways that advertise low or zero UPI fees (e.g. PhonePe PG, Cashfree) once volume justifies a second integration.
2. **Push UPI and in-store pickup for high-value phones.** A ₹1 lakh iPhone costs ₹2,360 in gateway fees. Paying by UPI on the shop's own QR at pickup costs ₹0. Store pickup is listed as a v1.1 feature.
3. **Cap COD by value** (`store_settings.cod_max_paise`) to limit RTO losses on expensive phones.
4. **Prefer Google/email sign-in** in the UI order to cut SMS spend; later, replace the SMS fallback with a WhatsApp OTP if that's cheaper at volume.
5. **Keep images small.** Admin uploads are resized to ≤1600px JPEG at quality 85 (≈150–300 KB) so egress stays inside the 250 GB Pro quota.
6. **Stay on Micro compute** until DB CPU stays above 70%. The next size up (Small) costs extra beyond the $10 credit.

## Change log

- 2026-10-29: Android-only v1, so Apple Developer is deferred (−₹725/mo).
- 2026-10-29: Added CI (GitHub Actions), store builds (Codemagic), crash reporting (Sentry), all free tier at launch volumes.
- 2026-10-28: First estimate. Stack: Supabase Pro, Razorpay Standard, MSG91 SMS, Resend free, app stores.
