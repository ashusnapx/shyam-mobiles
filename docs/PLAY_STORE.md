# Launch checklist: policy site, Google Play, Razorpay

Policy pages live in `site/` (static HTML + one `style.css`, no JS). Host the folder on GitHub Pages or similar. Every page is dated 29 October 2026. Requirements were checked on 29 Oct 2026; sources are at the bottom.

## 1. Fill the placeholders

Search `site/` for `[[` and replace each one everywhere. Six remain:

| Placeholder | Put in | Appears in |
|---|---|---|
| `[[LEGAL BUSINESS NAME]]` | Proprietor or firm name exactly as on PAN/GST/Razorpay KYC (e.g. "Ram Kumar, proprietor") | every page (footer), plus About, Privacy, Terms, Contact, Delete account |
| `[[GSTIN]]` | 15-character GSTIN | every page (footer), About, Contact |
| `[[SUPPORT EMAIL]]` | A monitored inbox. It is also the grievance and deletion address. Keep `mailto:` links valid. | every page (footer), Privacy, Refunds, Contact, Delete account |
| `[[GRIEVANCE OFFICER NAME]]` | A real person, usually the owner | Contact, Privacy |
| `[[DELIVERY TIME]]` | e.g. "1–2 days in Waidhan, 2–4 days elsewhere in Singrauli district" | Shipping |
| `[[SMS PROVIDER]]` | MSG91 or Twilio, whichever sends the OTPs | Privacy |

Already filled from the founder's details: shop name (श्याम मोबाइल शॉप, Shyam Mobile Shop), address (Rajeev Complex, Waidhan, District Singrauli, Madhya Pradesh 486886), phone and WhatsApp (+91 79875 59272), brands. **Check:** the pages say "Shop address". If the GST registered address differs, add it on About and Contact. Store hours say "as shown in the app", so keep `store_settings.store_hours` correct.

## 2. Decisions written into the pages: confirm or edit

These are promises to shoppers. Change the page if you can't keep one.

- **Money values match `store_settings` defaults:** delivery ₹49 below ₹999, free at ₹999+, COD up to ₹25,000 total. If you change them in Admin, change About, Terms and Shipping too.
- **Delivery area:** "Waidhan and nearby areas of Singrauli district". The app accepts any Indian PIN code, so the page promises a call and a full refund if you can't deliver.
- **Returns** (matches the app's default `returns_policy`): unopened items within 7 days; damaged, wrong or fake items reported within 48 hours; free pickup when it's our fault; change-of-mind returns at the buyer's cost, with the delivery fee not refunded.
- **Refunds:** issued from the Razorpay dashboard within 2 working days; banks usually take 5–7 working days (Razorpay's stated normal-refund time). COD refunds go by UPI, bank transfer or cash at the shop.
- **Grievances:** acknowledged within 24 hours (with a complaint number), resolved within 15 days. That is the IT Rules timeline, which is also stricter than the E-Commerce Rules (48 h / 1 month) and DPDP (90 days max), so it meets all three.
- **Deletion requests made without the app** are done within 7 days of confirming identity.
- **No marketing messages**, a tax invoice with every order, and no repair payments in the app.
- **Retention:** orders, repair bookings and payment records are kept 72 months from the GST annual-return due date for that financial year (CGST Act s.36), then deleted. **No code deletes them yet.** Do a yearly purge, or build a `pg_cron` job before the first records reach that age (around 2033).

## 3. Host the site

- Publish `site/` at a public HTTPS URL. Each page must load without login, outside India too (Play rejects geofenced URLs and PDFs).
- URLs for the forms below: `<site>/privacy.html`, `<site>/delete-account.html`, `<site>/terms.html`, `<site>/refunds.html`, `<site>/shipping.html`, `<site>/contact.html`, `<site>/index.html` (About), `<site>/index.html#pricing` (Pricing).
- **App gap (not fixed here):** Play requires a privacy policy link or text *inside the app*. Today the sign-in screen only says "By continuing you agree to the Terms and Privacy Policy" with no links, and the Account screen has none. Add links to `privacy.html` and `terms.html` on both screens before submitting.

## 4. Google Play Console

**Account**
- A personal developer account created after 13 Nov 2023 must run a **closed test with at least 12 opted-in testers for 14 days** before it can apply for production access. Organisation accounts with a D-U-N-S number are exempt. Start this early.

**Store listing**
- App name: Shyam Mobiles. Category: Shopping. Contact email: `[[SUPPORT EMAIL]]`. Website: the site URL.
- Short description: 80 characters max, with no emoji, ALL CAPS or "best/#1" claims. Full description: plain features, no keyword stuffing.
- App icon: 512 × 512 px, 32-bit PNG with alpha, up to 1024 KB.
- Feature graphic: 1024 × 500 px, JPEG or 24-bit PNG (no alpha).
- Phone screenshots: 2–8, JPEG or 24-bit PNG, each side 320–3840 px, long side no more than twice the short side. For promotion slots, provide at least 4 at 1080 × 1920 (9:16).
- Tablet screenshots are only needed if you target tablets. Preview video is optional.

**App content**
- Privacy policy: `<site>/privacy.html`.
- Ads: **No, my app does not contain ads.**
- App access: **All or some functionality is restricted** (see below).
- Content rating: fill in the IARC questionnaire honestly. It's a shopping app for physical goods, with no user-to-user chat in the app (WhatsApp opens outside it), no user-generated content shown to others, and no gambling. Expect a low rating; the exact label comes from IARC.
- Target audience: **18 and over** only (the pages say the app is for adults). This keeps it out of the Families policy. Don't use child-like art in the listing.
- Data safety: see the table below.
- Account deletion: **Yes, users can create accounts**. In-app path: Account → Delete account. Web URL: `<site>/delete-account.html`.
- Government app: No. Financial features: none (it sells goods; Razorpay is just checkout). Health: none. News: No.

**App access instructions for reviewers**
1. Create a fixed-OTP test number in Supabase (Auth → Providers → Phone → test phone numbers, format `<number>=<code>`, with an expiry date). Use a spare SIM the shop owns, not a made-up number. Anyone with the number and code can sign in, so set an expiry and remove it once review is done.
2. Make it a **customer** account, not an admin, so reviewers can't edit live products or orders.
3. Paste into Play's sign-in details:
   > Browsing needs no login. To test cart, checkout, orders and repairs: tap Account → Sign in → Phone, enter `<test number>`, then code `<code>`. No SMS is sent; the code is fixed. Please don't complete a payment. If you place a cash-on-delivery order, our staff will cancel it. The Admin tab is visible only to shop staff accounts.

**Permissions** (the profile build's merged manifest has INTERNET, ACCESS_NETWORK_STATE, NFC, USE_BIOMETRIC, USE_FINGERPRINT, READ_BASIC_PHONE_STATE and a dynamic-receiver permission, all from plugins. Check again after the location feature lands and on the release AAB)
- **Camera / photos (staff only):** the app declares no CAMERA or READ_MEDIA_* permission. `image_picker` opens the Android photo picker or the system camera app. If Play asks anyway: *"Only shop staff, in the Admin tab, add product photos from the camera or gallery. Customers are never asked. We use the system photo picker and camera app, and request no broad media access."*
- **ACCESS_COARSE_LOCATION / ACCESS_FINE_LOCATION** (coming with "Use my current location"): foreground only, requested only when the user taps the button on the address form. Approximate is enough; precise only if the user allows it. Justification: *"Location is used once, when the user taps 'Use my current location', to fill in a delivery address with Android's Geocoder. The coordinates are not stored or sent to our servers; only the address the user reviews and saves is stored. No background location."* Don't add ACCESS_BACKGROUND_LOCATION. The system permission prompt follows the user's own tap, which matches the "reasonable expectation" standard. If you ever request location without that tap, add an in-app prominent disclosure first.

**Data safety answers**

Encryption in transit: **Yes** (HTTPS). Users can request deletion: **Yes**. Shared with third parties: **No** for every type. Supabase, Razorpay, Google sign-in, the SMS provider, Resend and couriers act as service providers, which Play does not count as sharing, and opening WhatsApp is user-initiated.

| Data type | Collected | Optional? | Purposes | Notes |
|---|---|---|---|---|
| Name | Yes | Required (for delivery) | App functionality, Account management | |
| Email address | Yes | Optional (phone sign-in works) | Account management, App functionality | |
| User IDs | Yes | Required | Account management | Supabase user id |
| Address | Yes | Required to buy | App functionality | now with district + Home/Work/Other label |
| Phone number | Yes | Required to buy / book repairs | App functionality, Account management | |
| Approximate location | Yes, **processed ephemerally**, not stored | Optional | App functionality | only on the button tap. Android's Geocoder backend (usually Google Play services) may send it off-device, so declare it |
| Precise location | Yes, ephemeral, not stored | Optional | App functionality | only if the user grants precise |
| Purchase history | Yes | Required to buy | App functionality | orders, IMEIs |
| User payment info | Yes (by the Razorpay SDK) | Optional (COD exists) | App functionality, Fraud prevention/security | card/UPI details go to Razorpay, not us |
| App interactions | Yes (by the Razorpay SDK, on its own screens) | Required for online pay | App functionality, Fraud prevention/security | per Razorpay's guidance |
| Installed apps | Yes (by the Razorpay SDK: UPI-app detection only) | Required for UPI intent | App functionality | per Razorpay's guidance |
| Other user-generated content | Yes | Optional | App functionality | repair description |
| Photos | Yes (staff only) | Optional | App functionality | product photos in Admin; conservative answer |
| Crash logs, Diagnostics | **No** | | | Android vitals is Google's own and isn't declared; change to Yes only if an in-app crash SDK is added |
| Device or other IDs | No | | | Razorpay says only "if configured"; we don't configure it. Confirm with Razorpay support |
| Everything else (contacts, messages, files, health, calendar, audio, web history, financial "other", credit score) | No | | | |

## 5. Razorpay website / app details

Razorpay asks for links to **About us, Contact us, Pricing details, Terms and conditions, Privacy policy and Refunds policy**. Live API keys stay locked until they pass.

| Razorpay asks | Give |
|---|---|
| About us | `<site>/index.html` |
| Contact us | `<site>/contact.html` |
| Pricing details | `<site>/index.html#pricing` (prices incl. GST, delivery fee, no extra fees) |
| Terms and conditions | `<site>/terms.html` |
| Privacy policy | `<site>/privacy.html` |
| Refunds / Cancellation policy | `<site>/refunds.html` |
| Shipping policy (not in the doc we checked, but often asked) | `<site>/shipping.html` |

- Business name, address and GSTIN on the site must match the KYC documents exactly. Fill `[[LEGAL BUSINESS NAME]]` and `[[GSTIN]]` first.
- Upload a sample invoice (PNG, JPG or PDF).
- Payment needs login, so give Razorpay the same test account as Play (or a second test number).
- App URL: the Play listing URL once it exists (internal or closed testing link until then).
- Razorpay runs instant checks on the primary website and may contact you by email, WhatsApp or SMS.

## 6. Ask a lawyer / CA to review

- **DPDP Act 2023 timing:** the main duties (notice, consent, rights, breach reporting, Rules 3 and 5–16) start **13 May 2027**. MeitY proposed moving that to 13 Nov 2026 in Jan 2026, but no amending notification was found as of late Sep/Oct 2026, so re-check the Gazette. The pages already follow the Act's model.
- **DPDP Rule 3 notice:** the Act wants a standalone, itemised notice at the point of consent (sign-in) with links to withdraw consent and to complain to the Board. The privacy page has the content. The app may need a short notice screen.
- **DPDP Rule 8(3):** keep personal data, traffic data and logs for **at least one year** (from May 2027). Check how long Supabase keeps auth/API logs and whether you need to export them.
- **Erasure vs. retention:** after account deletion, orders keep the delivery name, phone and address, and repair bookings keep `contact_phone`, device and notes, both just unlinked. Confirm that GST (s.36: 72 months) justifies each field. If not, null `contact_phone` and similar fields on deletion. `payment_events.payload` (the Razorpay webhook JSON, which can include email, phone or UPI ID) is also kept.
- **Returns:** is the "unopened only" rule for change-of-mind returns fine? The E-Commerce Rules 7(4) bar refusing returns of defective, spurious, not-as-described or late goods; the page says so. Can you insist on an unboxing video? The page only "suggests" one.
- **IT Rules 2021** apply to intermediaries. The app shows no user content, so it may not be one. The page commits to the IT Rules timelines anyway; drop that if the lawyer says it isn't needed.
- Are the jurisdiction clause (Singrauli courts), the liability wording, and the minors rule (18+, parents order for under-18s) acceptable?
- Wholesale business: B2B sales don't go through the app. Confirm nothing in the pages needs a wholesale carve-out.
- Product pages: Legal Metrology e-commerce declarations (MRP, manufacturer, country of origin). Not verified here; ask.
- Cross-border processing: Resend, Twilio, Google and possibly Supabase are outside India. DPDP s.16 allows it unless a country is restricted.

## 7. Update the pages when

- **An in-app crash SDK is added** (none planned): add it to Privacy → "Who we share it with" and "Technical logs", and set Crash logs and Diagnostics to Yes in Data safety.
- **"Use my current location" ships:** the pages already describe it. If it's delayed past launch, remove the Location row from Privacy and from Data safety.
- **Any other change** to the SMS provider, delivery area or fees, store pickup, push notifications, marketing messages, coupons or reviews: update the page and its "Last updated" date.

## Sources (checked 29 Oct 2026)

- Play account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Play User Data / privacy policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Play Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Play app access: https://support.google.com/googleplay/android-developer/answer/9859455
- Play listing assets: https://support.google.com/googleplay/android-developer/answer/9866151
- Play testing requirement: https://support.google.com/googleplay/android-developer/answer/14151465
- Play target audience: https://support.google.com/googleplay/android-developer/answer/9867159
- Razorpay website details: https://razorpay.com/docs/payments/dashboard/account-settings/business-website-details/
- Razorpay refunds (5–7 working days): https://razorpay.com/docs/payments/refunds/
- Razorpay SDK data safety: https://razorpay.com/docs/payments/payment-gateway/android-integration/standard/google-data-safety/
- Supabase test OTP: https://supabase.com/docs/guides/auth/testing-auth-flows
- Supabase backups (Pro: 7 days): https://supabase.com/docs/guides/platform/backups
- Android Geocoder: https://developer.android.com/reference/android/location/Geocoder
- DPDP phased dates: https://www.azbpartners.com/bank/indias-digital-personal-data-protection-act-phased-rollout-and-key-compliance-milestones/ and https://www.mirvolegal.com/insights/dpdp-rules-2025-compliance-timeline/
- DPDP Rules 3, 8, 9, 14 and Act s.12, s.13: https://dpdpa.com/dpdparules/rule3.html (and rule8, rule9, rule14; dpdpa2023/chapter-3/section12, section13)
- Proposed DPDP timeline cut: https://ssrana.in/articles/meity-plans-to-cut-short-dpdp-compliance-timeline-and-notify-cross-border-restrictions-for-sdfs/
- E-Commerce Rules 2020 (Rules 4, 7): https://www.legitquest.com/act/consumer-protection-e-commerce-rules-2020/91C8
- CGST s.36 retention: https://www.knowyourgst.com/gstlaw/cgst-act/36-period-of-retention-of-accounts-36/
- National Consumer Helpline 1915: https://newsonair.gov.in/toll-free-number-in-17-languages-for-consumers-grievance-redressal-across-the-country-govt-in-ls/
