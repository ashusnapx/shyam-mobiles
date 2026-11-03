# Security and privacy

Status: plan, 2026-11-03. This file is the companion to `docs/FIREBASE.md`, and each item lands with the code that
needs it (§5). Goal: no one can move money, stock or staff rights except through the server's checks; a stolen key,
phone or SMS flood costs little; and we collect only what the shop needs, keep it in India, and delete it on time.

## 1. Threat model

| # | Threat | Who | Impact | Main controls |
|---|---|---|---|---|
| T1 | Tampered prices or totals, a fake "paid" status, replayed payment calls, a forged webhook, a double refund | customer with a patched app, scripts | money lost | Prices only on the server (`placeOrder`). Clients never write `orders`. Settlement from PhonePe's status API, never from the body. App Check replay protection. Idempotent refunds (FIREBASE §3) |
| T2 | Stock hoarding (unpaid online orders), overselling under concurrency | bots, competitors | lost sales | Transactions. `PENDING_LIMIT` 2. A 15-minute hold. Per-user rate limits. App Check |
| T3 | Staff account takeover: SIM swap on phone OTP, a stolen unlocked phone, a phished Google account, a removed staffer keeping access | outsiders, ex-staff | refunds, stock and price edits, customer data | Staff powers only in **Google + TOTP** sessions. Removal is immediate (Rules read the role doc). Recent-login checks. Audit log |
| T4 | SMS pumping / toll fraud on phone OTP | bots | SMS bill ($0.07 each) | India-only SMS region. reCAPTCHA SMS defense. App Check on Auth. SMS alert. Budget alert |
| T5 | Scraping: the catalogue (public by design), customer data (must be impossible), guessing coupon or referral codes | scrapers | data leak, coupon abuse | Rules deny by default. App Check on Firestore. Codes ≥ 6 characters. Failed-code rate limit |
| T6 | Fake COD orders, burner accounts | pranksters | courier cost, stock locked | Phone- or Google-verified sign-in. COD cap (`codMaxPaise`). Staff confirm before packing. Per-user limits |
| T7 | Leaked keys or secrets (public repo) | anyone | backend abuse | The only key in the app is the restricted Firebase API key. Secrets live only in Secret Manager. No service-account keys. Keyless CI. Secret scanning with push protection |
| T8 | Lost or shared customer phone | finder, family | orders, addresses seen | Sign-out wipes local data. "Sign out of all phones". Private lock-screen notifications. `FLAG_SECURE` on sensitive screens |
| T9 | Denial of wallet (flooding callables, reads, Storage) | bots | Blaze bill | App Check. `maxInstances`. Per-user rate limits. Bounded queries. Budget alerts |
| T10 | Supply chain (npm, pub, Gradle, Actions) | upstream compromise | code execution | Dependabot. Lockfiles. Pinned Action SHAs. CodeQL. Minimal dependencies |
| T11 | Over-collection, PII in logs or analytics, keeping data too long | us | DPDP liability, trust | §4: minimisation, consent, TTLs, no PII in telemetry |

## 2. Google security features we turn on

### 2.1 App Check (Play Integrity)

- **Providers:** Play Integrity in release builds. The debug provider in debug builds only, with tokens registered in the console and never compiled into release. Play Console → App integrity → link the Cloud project.
- **Verdict settings** (Firebase console → App Check → app → Play Integrity): `PLAY_RECOGNIZED` required (the default) and `LICENSED` required, because we ship only through Play; demo APKs go out through the internal testing track. Device integrity: **basic**, which blocks emulators and bots without locking out older budget phones. Token TTL: 1 hour (the default; the Play Integrity standard tier allows 10,000 calls a day).
- **Enforcement order:** ship the SDK, then watch the App Check metrics for 7 days, then enforce on Firestore, Storage, and every callable (`enforceAppCheck: true` in the shared callable options). Then Authentication: App Check for Auth is in *Preview* and needs Identity Platform. Turn it on in monitor mode and enforce once 99% of requests are verified.
- **Replay protection** on `placeOrder`, `createPayment`, `startRefund`, `setRole`, `deleteAccount`, `adminDeleteAccount`: `consumeAppCheckToken: true` on the server, plus `if (request.app?.alreadyConsumed) fail('UNAUTHORIZED')` (enforcement alone doesn't reject a consumed token). The client sends `HttpsCallableOptions(limitedUseAppCheckToken: true)`. Each such call costs one Play Integrity attestation, which is fine at shop volume.
- `phonepeWebhook` is the only HTTP endpoint without App Check. It has its own constant-time credential check and never trusts the body.

### 2.2 Identity Platform (Firebase Auth upgrade, free under 50k MAU)

- **SMS region policy:** allowlist **India (IN)** only. Enforcement is immediate.
- **reCAPTCHA SMS defense:** enable the reCAPTCHA Enterprise API, then SMS defense in **AUDIT** for 2 weeks (a failed score falls back to Play Integrity, then reCAPTCHA v2), then **ENFORCE** (a blocked request gets no SMS). Android needs Firebase Auth SDK ≥ 23.1.0 (in `firebase_auth` 7's BoM) and `com.google.android.recaptcha:recaptcha` ≥ 18.5.1 in `app/build.gradle.kts`. Add `recaptchaenterprise.googleapis.com` to the API key's allowlist. reCAPTCHA gives 10,000 free assessments a month, but SMS defense sits in a paid tier: confirm its price on the compare-tiers page before ENFORCE.
- **MFA (TOTP) required for staff.** Firebase MFA does not work with phone as the first factor and needs a verified email. So **staff sign in with Google** (Gmail is verified) and enrol TOTP in Account → Staff security (re-authentication first). `TotpMultiFactorGenerator` and `TotpSecret.generateQrCodeUrl` are in `firebase_auth` 7. TOTP is enabled once through the Admin SDK `projectConfigManager().updateProjectConfig({ multiFactorConfig: { providerConfigs: [{ state: 'ENABLED', totpProviderConfig: { adjacentIntervals: 1 } }] } })`, run from Cloud Shell (§2.4).
  - Staff power requires both: `request.auth.token.firebase.sign_in_second_factor == 'totp'` **and** a role on `users/{uid}` (Rules `get()`; one billed read per staff request, never for customers because `&&` short-circuits). Callables check the same through `requireStaff()`. A staffer who signs in by phone gets customer powers only.
  - **Owner bootstrap** (changes FIREBASE §4): `claimOwner` needs a Google sign-in with TOTP, a linked, verified phone equal to `settings/business.phone`, and no existing owner.
- **Blocking functions:** none at launch. Firebase gives them 7 seconds, and a slow or failing one locks out every sign-in. Everything they would enforce is already enforced by the region policy and the Rules MFA check. Kept ready to deploy during an attack: `beforeUserCreated` rejecting sign-ups while `settings/security.signupsPaused` is true.
- **Email enumeration protection:** on (the default for new projects). There is no email or password provider in production anyway. Anonymous, email-link and password sign-in stay disabled.
- **Token revocation on staff removal:** `setRole(null)` removes the claim and the `users/{uid}.role` field, then calls `revokeRefreshTokens(uid)`. Because Rules and callables read the role doc, access ends at once, not after the 1-hour ID-token life.
- **Recent-login checks:** `auth_time` within 5 minutes for `setRole`, `startRefund`, `deleteAccount`, `adminDeleteAccount`, TOTP enrolment, and Rules writes to `settings/business` (`request.time < timestamp.value(request.auth.token.auth_time * 1000) + duration.value(5, 'm')`). The app re-prompts Google and TOTP.
- **"Sign out of all phones"** (Account): callable → `revokeRefreshTokens` + delete the user's `devices/*`.

### 2.3 Security Rules

- `match /{document=**} { allow read, write: if false; }` first. Every allowed path then lists the exact keys (`keys().hasOnly`), types, sizes and regexes (FIREBASE §3), `updatedAt == request.time`, and field-limited updates (`diff().affectedKeys().hasOnly`).
- Customer list queries must carry the owner filter (`uid == request.auth.uid`). Unbounded staff lists are refused (`request.query.limit <= 100`).
- Storage: `product-images/**` public read, staff write, `image/(webp|jpeg|png)` ≤ 1 MB. `invoices/{uid}/**` readable by the owner or staff, with no client write.
- Tests: `test/rules` (ports of `rls.test.sql` and `attacks.test.sql`) run in CI on every PR. The emulator's rules-coverage report must show every allow line hit. Rules deploy only from CI.

### 2.4 Secrets, keys and IAM

- **Secret Manager** for every secret: the six PhonePe values (`defineSecret`, bound only to the payment functions). Nothing else is secret: `google-services.json` and the Firebase API key are public by design.
- **No downloaded service-account keys.** After cut-over, delete the FCM key that Supabase's `send-push` uses (Cloud console → IAM → Service accounts → `firebase-adminsdk-…` → Keys → delete). One-off admin jobs (the Supabase import, the TOTP config, a restore) run in **Cloud Shell**, which has gcloud and Node and uses the owner's own login, with no key on disk. The project has no Google Cloud organization, so key creation cannot be blocked by org policy; an alert fires instead (§2.6).
- **API key restrictions** (Cloud console → Credentials → "Android key (auto created by Firebase)"):
  - Application: Android apps, `package` + SHA-1 of the debug, upload and Play-signing keys.
  - APIs, only what we use from Firebase's list: Identity Toolkit, Token Service, Cloud Firestore, Cloud Storage for Firebase, Firebase Installations, FCM Registration, Firebase App Check, Remote Config (+ Realtime), Firebase Management, and reCAPTCHA Enterprise once SMS defense is on.
  - Change it on the internal track first. Being able to remove the restriction is the rollback.
- **Runtime service accounts** (the `serviceAccount` function option). 2nd gen defaults to the Compute Engine default account, which holds Editor.

  | Account | Functions | Roles |
  |---|---|---|
  | `fn-api` | order, offer, repair, feedback callables | `roles/datastore.user` |
  | `fn-account` | `claimOwner`, `setRole`, `deleteAccount`, `adminDeleteAccount`, `exportMyData`, `signOutEverywhere` | `datastore.user`, `firebaseauth.admin` |
  | `fn-payments` | `createPayment`, `verifyPayment`, `phonepeWebhook`, `startRefund` | `datastore.user`, `secretmanager.secretAccessor` on the PhonePe secrets only |
  | `fn-events` | triggers, schedule, push, invoices | `datastore.user`, `firebasecloudmessaging.admin`, `storage.objectAdmin` on the bucket, `eventarc.eventReceiver` |

  Once everything runs on these accounts, remove Editor from the default compute account. Engineers move from build-time Firebase Develop Admin to `roles/firebase.viewer` at launch. Deploys go only through CI.
- **Keyless CI deploys:** Workload Identity Federation.
  - Pool `github`, OIDC provider `token.actions.githubusercontent.com`, attribute condition `assertion.repository == 'ashusnapx/shyam-mobiles' && assertion.ref == 'refs/heads/main'`.
  - `google-github-actions/auth` impersonates `deployer@`. The deploy job runs only in a GitHub `production` environment with the owner as required reviewer.
  - `deployer@` gets Firebase Develop Admin + Service Account User on the four runtime accounts + Secret Manager Viewer. Add only what a failed deploy names. No JSON key in GitHub secrets.

### 2.5 Data protection

- Firestore: **point-in-time recovery** on (7-day window; Cloud console → Firestore → Disaster recovery), **daily scheduled backups kept 14 days**, and **delete protection** on (`gcloud firestore databases update --database='(default)' --delete-protection` from Cloud Shell).
- Storage: keep the default 7-day soft delete. Lifecycle rule: delete `invoices/` objects older than 8 years.
- Encryption at rest is Google's default. TLS only in transit (§3). No CMEK: it adds cost and operational work without changing our risk.

### 2.6 Audit logs, alerting, cost caps

- Admin Activity audit logs are always on (400 days, free). Turn on **Data Access** logs for Identity Toolkit, IAM and Secret Manager. Leave Firestore data reads off (volume): business actions are already audited in `events[].by/byUid`. Every staff callable logs one structured line `{audit: true, action, actorUid, targetId}` with no names, phones or addresses.
- **Retention ≥ 1 year** (DPDP Rules r.6(1)(e)): a log sink routes audit logs, `audit: true` lines and `severity >= WARNING` to a `security-logs` bucket with 400-day retention. The `_Default` bucket stays at 30 days.
- **Alerts** (Cloud Monitoring → email to the owner and the lead developer):
  - an IAM policy change
  - a service-account key created
  - Security Rules released by anyone but `deployer@`
  - function 5xx over 5% for 10 minutes
  - more than 200 `SendVerificationCode` per day (log-based metric)
  - an App Check unverified-request spike
  - the budget at 50/90/100% (FIREBASE §9)
- **Cost caps:**
  - `maxInstances`: callables 10, payments and webhook 5, triggers 5.
  - Every query has `limit()` (≤ 100).
  - `shared/rateLimit.ts` (one `rateLimits/{uid}` doc with rolling windows, TTL 1 day): `quoteOrder` 30/min, `placeOrder` 5 per 10 min, `createPayment` 10 per 10 min, `verifyPayment` 20 per 10 min, `applyReferralCode` 5/hour, `exportMyData` 1/day, failed coupons 10 per 10 min, `sendFeedback` 10/day.

### 2.7 GitHub (the repo is public)

- Settings → Code security: **secret scanning + push protection**, **Dependabot alerts + security updates** (npm, pub, Gradle, GitHub Actions; weekly version updates grouped), **CodeQL default setup** (JS/TS, Kotlin). All free for public repos.
- Branch protection on `main`: PR, CI green, 1 review. `CODEOWNERS` requires the owner or lead for `firebase/firestore.rules`, `firebase/storage.rules` and `firebase/functions/src/{payments,orders,account}/**`.
- Actions are pinned by commit SHA with `permissions: read-all` by default. `.gitignore` keeps out `.env*`, `.secret.local`, `.emulator-data/` and `*-key.json`.

## 3. Android hardening

- **R8:** already on (`isMinifyEnabled`, `isShrinkResources`). Add `-assumenosideeffects class android.util.Log { public static *** v(...); public static *** d(...); public static *** i(...); }`. Drop the Razorpay rules in Phase 2.
- **No cleartext:** already `usesCleartextTraffic="false"`. A debug-only `src/debug/res/xml/network_security_config.xml` allows cleartext to `10.0.2.2` and `127.0.0.1` for the emulators.
- **Backups:** already `allowBackup="false"`, `fullBackupContent="false"`, and `data_extraction_rules.xml` excluding every domain. So the Auth session, the Firestore cache and the FCM token never leave the phone. Keep this, and a test pins it.
- **`FLAG_SECURE`** (no screenshots or recents preview) on the OTP and TOTP screens, the checkout payment and result screens, Admin refunds and Staff, and the account data export. Implement it with a `setSecure(bool)` method channel in `MainActivity`, which becomes a `FlutterFragmentActivity` for PhonePe anyway, plus a `SecureScreen` wrapper widget. No new dependency.
- **Play Integrity** is used only through App Check (§2.1). There are no custom verdict calls.
- **Sign-out on a shared family phone:** delete `devices/{token}`, then `FirebaseMessaging.deleteToken()`, `GoogleSignIn.signOut()` and `FirebaseAuth.signOut()`, then `FirebaseFirestore.terminate()` + `clearPersistence()`, so the next person sees nothing.
- **Notifications:** order, payment and repair channels use `NotificationVisibility.private` with a public version reading "Shyam Mobiles: you have an update", so the lock screen never shows amounts or addresses.
- **Logs:** `avoid_print` lint. `debugPrint` only under `kDebugMode`. Never log tokens, OTPs, phones, addresses or GSTINs. Crashlytics custom keys come from an allowlist (§4.4).
- **Permissions:** drop `ACCESS_FINE_LOCATION` and keep `ACCESS_COARSE_LOCATION` (address prefill: the position stays on the phone and goes only to the platform geocoder). In Phase 2, re-audit the merged manifest once Razorpay's merged permissions are gone. No SMS read permission: SMS Retriever needs none.
- **Deep links:** verified App Links only (`firebase/hosting/.well-known/assetlinks.json`). The router accepts only known routes (`core/links.dart`).

## 4. Privacy by design (India's DPDP Act 2023 and DPDP Rules 2025)

Status: the DPDP Rules were notified on 13–14 Nov 2025 (G.S.R. 846(E)) with a staggered start. The Board's provisions apply now, consent managers from Nov 2026, and the main fiduciary duties (notice, security safeguards, breach intimation, retention) **18 months after notification (13 May 2027)**. We meet them from launch. The shop is the *Data Fiduciary*; Google (Firebase) and PhonePe are processors.

### 4.1 Data inventory

| Data | Why | Where | Kept | Seen by |
|---|---|---|---|---|
| Name, phone (Auth + `users`), Google photo URL | account, delivery contact | Firebase Auth, Firestore asia-south1 | until account deletion | the user, staff |
| Addresses | delivery | `users/{uid}/addresses` | until deleted by the user or the account | the user (staff see the order's copy) |
| Orders: items, address copy, payment ids, B2B GSTIN, invoice PDF | sale, GST records | `orders/*` (+ subcollections), Storage `invoices/` | **8 years** (CGST Act s.36: 72 months from the annual-return due date), then TTL `purgeAt`. `uid` removed at account deletion | the user, staff |
| Repairs | service | `repairs/*` | 3 years, TTL. Deleted with the account | the user, staff |
| Feedback | improve service | `feedback/*` | 2 years, TTL. Deleted with the account | staff |
| Notifications, FCM tokens | inform | `users/{uid}/notifications`, `devices/*` | 90 days. Tokens until sign-out or 270 days | the user |
| Cart, wishlist (with back-in-stock marks), referral link, coupons | shopping | Firestore | until removed or account deletion | the user (staff see referrals) |
| Rate-limit timestamps | abuse prevention | `rateLimits/*` | 1 day | nobody |
| Card or UPI details | payment | **PhonePe only**: never reach us. We keep PhonePe order and transaction ids and amounts | with the order | staff |
| Usage analytics (opt-in) | improve the app | Google Analytics | 2 months | the owner |
| Crash reports (no identifiers) | fix bugs | Crashlytics | 90 days | developers |
| Server logs (uid, function, no other PII) | security | Cloud Logging | 400 days security bucket, 30 days default | the owner, developers |
| Backups | recovery | Firestore backups / PITR | 14 / 7 days: deleted data is gone from every copy within 14 days | nobody (restore only) |

**Not collected:** PAN (the GSTIN is the only tax id we hold; for B2B it is only what the buyer types), date of birth, email in Firestore (a Google email stays inside Firebase Auth), contacts, exact location, advertising ID, SMS contents, device fingerprints beyond App Check.

### 4.2 Notice and consent

- At first sign-in, the Name screen shows a short notice in **English and Hindi** (DPDP s.5(3)): what we collect (the table above, in plain words), why, how long, your rights (access, correction, erasure, grievance, nominee), how to withdraw consent, the grievance officer's contact, how to complain to the Data Protection Board, and the privacy-policy link.
- Required checkbox: "I am 18 or older." DPDP s.9 needs verifiable parental consent for children, so we do not knowingly open accounts for minors.
- Optional, **unticked**: "Help improve the app with usage analytics." Consent must be an affirmative act, so it is never pre-ticked.
- Record: `users/{uid}.consent {noticeVersion, acceptedAt, analytics}`, written once per notice version. A new version asks again.
- **Crash reports** carry no user identifier or personal data, so they are on by default as part of keeping the service working, disclosed in the notice, with an off switch.
- **Account → Privacy:** toggles for analytics, crash reports, back-in-stock alerts, offer notifications; "Download my data"; "Delete my account"; "Sign out of all phones". Withdrawing analytics runs `setAnalyticsCollectionEnabled(false)` + `resetAnalyticsData()`.

### 4.3 GA4 configuration

- Manifest: `firebase_analytics_collection_enabled=false` (on only after consent), `google_analytics_adid_collection_enabled=false`, `google_analytics_ssaid_collection_enabled=false`, `google_analytics_default_allow_ad_personalization_signals=false`. Consent mode: `adStorage`, `adUserData`, `adPersonalizationSignals` denied; `analyticsStorage` follows the toggle.
- GA4 property: data retention **2 months**, Google signals **off**, granular location and device data **off**, no Google Ads links, user-provided data collection off.
- **No user ID** in GA4: only the app-instance id. This changes FIREBASE §6. No PII in events or user properties: `Telemetry` takes typed parameters only (item ids, prices, counts, route names). A unit test fails on keys like `name`, `phone`, `address` or `gstin`. The `search` event sends a result count, **not the search term**. GA4 does not log or store IP addresses.

### 4.4 Crashlytics

No `setUserIdentifier`. Custom keys come from an allowlist: `build`, `backend`, `route` (the pattern without ids, e.g. `/orders/:id`). No request or response bodies. Opt-out uses `setCrashlyticsCollectionEnabled(false)`.

### 4.5 Retention mechanics

TTL policies on `expireAt`/`purgeAt` for notifications, devices, rateLimits, feedback, repairs, orders, and **each order subcollection** (`payments`, `refunds`: TTL deletes do not cascade, so every doc carries its own `purgeAt`). There is a Storage lifecycle rule for `invoices/`. Backups expire after 14 days. A unit test asserts that every collection in `src/model/` declares a retention.

### 4.6 Account deletion (in-app and web)

- **In the app:** `deleteAccount` (recent login, replay-protected). It keeps today's `ACTIVE_ORDERS` guard. **Orders and invoices are kept with `uid: null`** (GST law). Everything else is deleted: `users/{uid}` with its addresses, notifications, coupons and wishlist; `carts`, `devices`, `rateLimits`, `referralCodes`; the user's `referrals` (the referee side; the referrer side is anonymised); repairs; feedback; and finally the Auth user.
- **On the web** (Play requirement): `https://shyam-mobiles.web.app/delete-account` (`firebase/hosting/delete-account.html`, rewritten 2026-11-03). The user messages or calls from the registered number. Staff verify the number and run `adminDeleteAccount({phone})` (TOTP + recent login). We acknowledge within 48 hours and finish within 7 days. This URL goes in the Play Data safety form.

### 4.7 Data export (right to access, DPDP s.11)

Account → Download my data → `exportMyData` returns JSON: profile, addresses, orders with items, repairs, feedback, notifications, consent record. The share sheet opens. Limited to 1 a day.

### 4.8 Grievance officer and breach process

- **Grievance officer:** the owner (or a named person), with name, phone 7987559272 and email on `firebase/hosting/privacy.html`, `firebase/hosting/contact.html` and in Account → Help. Acknowledge within 48 hours and resolve within 1 month (Consumer Protection (E-Commerce) Rules 2020, r.4; DPDP s.8(10)).
- **Breach runbook**, kept in this file:
  1. Detect: §2.6 alerts.
  2. Contain: revoke tokens, rotate the PhonePe secrets, pause sign-ups, deploy a lock-down rule for the affected paths, set `maxInstances: 0` on the abused functions.
  3. Assess: the security log bucket.
  4. Notify: affected users **without delay** (in-app notification + SMS/WhatsApp); the **Data Protection Board** at once, with the detailed report **within 72 hours** (DPDP Rules r.7); **CERT-In within 6 hours** (CERT-In directions of 28 Apr 2022); PhonePe if payments are involved.
  5. Write a post-mortem in `docs/`.

### 4.9 Privacy policy and Play Data safety

- `firebase/hosting/privacy.html` (rewritten 2026-11-03; the Hindi version is still to do): replaces Supabase, Razorpay and MSG91 with Google Firebase (data stored in Mumbai, asia-south1; Analytics and Crashlytics may process outside India) and PhonePe (payments). Add the §4.1 table, rights, the grievance officer, and a Hindi version.
- **Data safety answers:**
  - **Collected:** Personal info (name, phone number, address), required, for app functionality and account management. Financial info: purchase history. App activity: app interactions, optional (analytics). App info and performance: crash logs and diagnostics. Device or other IDs: FCM token and Firebase installation id, for app functionality and fraud prevention (App Check).
  - **Not collected:** location (used on the phone only), search history, photos, contacts.
  - **Shared:** none (processors are not "sharing").
  - **Security:** encrypted in transit; deletion in the app + web URL.
  - **Payment info** collected by the PhonePe SDK: D confirms against PhonePe's SDK disclosure and declares it.

## 5. Checklist by phase and engineer (see FIREBASE §7)

| Item | Phase | Owner |
|---|---|---|
| Deny-by-default Rules skeleton, `isStaff()` (claim + TOTP + role doc), rules tests + coverage in CI | 0 | A |
| `shared/{auth,rateLimit,audit}.ts`: `requireStaff`, `requireRecentLogin`, `rejectConsumedAppCheck`, structured audit log | 0 | A |
| `model/*` declares the retention field for every collection, and the retention unit test | 0 | A (each owner fills theirs) |
| App Check SDK (Play Integrity + debug provider), `HttpsCallableOptions` helper with the `limitedUse` flag | 1 | A |
| Google + TOTP staff flow, Staff security screen, `claimOwner`/`setRole` (revoke + role doc), "Sign out of all phones" | 1 | A |
| Consent notice (English and Hindi) at first sign-in, `users.consent`, Account → Privacy toggles, `exportMyData`, `deleteAccount` + `adminDeleteAccount` | 1 | A |
| `Telemetry` with typed params, the PII test, GA4 manifest flags, consent mode; Crashlytics allowlist | 1 | A |
| Sign-out wipe (token, devices doc, Firestore cache); private lock-screen notification visibility | 1 | A / D |
| `FLAG_SECURE` channel + `SecureScreen`; debug network config; `Log` stripping; coarse location only | 1 | A |
| Storage Rules (types, size, invoices owner/staff), `deleteProduct` guard, catalog Rules field validation | 1 | B |
| `placeOrder`/`quoteOrder` rate limits, replay protection on `placeOrder`, failed-coupon limit, bounded staff queries | 1 | C |
| PhonePe secrets via `defineSecret` on `fn-payments`, webhook constant-time check, replay protection on `createPayment`/`startRefund` | 1 | D |
| Notification copy has no amounts or addresses in the public version; back-in-stock respects opt-out | 1 | D |
| Runtime service accounts per function group; `maxInstances` defaults | Cut-over | A |
| WIF deploy from CI, `production` environment, `CODEOWNERS`, branch protection, pinned Actions | Cut-over | A |
| API key restrictions (tested on the internal track) | Cut-over | A + owner |
| Enforce App Check (Firestore, Storage, callables), then Auth (Preview) | Cut-over + 7 days | A |
| SMS defense AUDIT → ENFORCE after 2 weeks | Cut-over + 14 days | A + owner |
| Delete the old FCM service-account key; remove Editor from the default compute account | Cut-over + 7 days | A + owner |
| Log sink to `security-logs` (400 days), alerts, Data Access logs | Cut-over | A |
| PITR, daily backups (14 days), delete protection; `invoices/` lifecycle rule | Cut-over / 2 | A / D |
| TTL policies for every collection (incl. order subcollections) | Cut-over / 2 | each owner |
| Privacy policy (English and Hindi), delete-account page, Play Data safety form | Cut-over | A + owner |
| Merged-manifest permission audit after Razorpay removal; drop Razorpay R8 rules | 2 | A |

### Owner's console steps (plain words)

1. Firebase → Authentication → Settings → **Upgrade to Identity Platform**. Then **SMS region policy** → Allow → India.
2. Google Cloud console → **reCAPTCHA** → enable the API → Settings → **SMS defense** → turn on in Audit. After 2 weeks, switch it to Enforce.
3. Play Console → App integrity → **link the Firebase project**. Firebase → App Check → register the app with **Play Integrity**: Play-recognized ✔, Licensed ✔, device integrity *basic*.
4. After the developers say the metrics look good: App Check → **Enforce** for Firestore, Storage and Functions (later Authentication).
5. Cloud console → APIs & Services → Credentials → the Android key → **restrict** to the app (package + SHA-1s) and the listed APIs (do it with the developer on the test track).
6. Cloud console → Firestore → Disaster recovery → **enable PITR** and **daily backups (14 days)**. In Cloud Shell, the developer turns on **delete protection**.
7. Cloud console → IAM → Service accounts → `firebase-adminsdk-…` → Keys → **delete the old key** (after cut-over).
8. Cloud console → IAM → Audit logs → turn on **Data Access** for Identity Toolkit, IAM, Secret Manager. Monitoring → confirm the alert emails reach you.
9. Google Analytics → Admin → Data settings: **retention 2 months**, **Google signals off**, **granular location and device data off**. Don't link Google Ads.
10. GitHub → repo Settings → Code security: turn on **secret scanning, push protection, Dependabot alerts and updates, CodeQL**. Settings → Environments → `production` → add yourself as required reviewer.
11. Choose the **grievance officer** (you, or someone you name) and the email to publish. Review the English and Hindi notice and the privacy page before launch.
12. Play Console → App content → **Data safety**: answer as in §4.9, with the delete-account URL.

## Sources (checked 2026-11-03)

- App Check: https://firebase.google.com/docs/app-check (Auth support in Preview; Play Integrity 10,000/day) · Play Integrity provider settings: https://firebase.google.com/docs/app-check/android/play-integrity-provider · callable `consumeAppCheckToken`: https://firebase.google.com/docs/reference/functions/2nd-gen/node/firebase-functions.https.callableoptions · Flutter `HttpsCallableOptions.limitedUseAppCheckToken`: https://pub.dev/documentation/cloud_functions/latest/cloud_functions/HttpsCallableOptions-class.html
- reCAPTCHA SMS defense (Android SDK ≥ 23.1.0, reCAPTCHA SDK ≥ 18.5.1, OFF/AUDIT/ENFORCE): https://docs.cloud.google.com/identity-platform/docs/recaptcha-tfp · tiers and pricing: https://docs.cloud.google.com/recaptcha/docs/compare-tiers · SMS regions: https://docs.cloud.google.com/identity-platform/docs/admin/sms-regions
- TOTP MFA (phone first factor unsupported, verified email required): https://firebase.google.com/docs/auth/android/totp-mfa · Blocking functions (7 s limit, Identity Platform): https://firebase.google.com/docs/functions/auth-blocking-events
- API key restrictions: https://firebase.google.com/docs/projects/api-keys · Function identity (default compute account, least privilege): https://cloud.google.com/functions/docs/securing/function-identity
- Firestore PITR: https://docs.cloud.google.com/firestore/docs/use-pitr · backups: https://firebase.google.com/docs/firestore/backups · delete protection: https://docs.cloud.google.com/firestore/docs/manage-databases
- Analytics data collection flags: https://firebase.google.com/docs/analytics/android/configure-data-collection
- Play account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- DPDP Rules 2025 (notified 13–14 Nov 2025, 18-month phase-in, 72-hour breach report): https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/nov/doc20251117695301.pdf, https://www.hoganlovells.com/en/publications/indias-digital-personal-data-protection-act-2023-brought-into-force- · Rule 6 log retention: https://dpdpa.com/dpdparules/rule6.html
