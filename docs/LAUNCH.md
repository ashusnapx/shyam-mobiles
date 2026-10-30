# Launch

Everything production needs is wired up. What's left is keys and details, all in `.env.local` (gitignored; the
template, with where to get each key, is in the chat of 2026-10-29 and below).

1. Paste what you have into `.env.local`. Empty lines are fine: each step waits for its own keys.
2. `python3 scripts/launch.py --dry-run` shows every command it would run, and what it's still waiting for.
3. `python3 scripts/launch.py` does it. Run it again whenever more keys arrive; it skips what can't run yet.

| Keys | What turns on |
|---|---|
| Supabase (filled) | link, migrations, Edge Functions, auth settings: sign-in hook, 6-digit codes, code emails |
| `RESEND_API_KEY`, `SMTP_SENDER_EMAIL` | sign-in emails through Resend (Supabase's own mailer sends only a few an hour) |
| `MSG91_AUTH_KEY`, `MSG91_TEMPLATE_ID` (after DLT) | phone sign-in: Auth's Send SMS hook → `functions/send-sms` → MSG91 |
| `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | Google sign-in, in Supabase and in the app build |
| `RAZORPAY_KEY_ID`, `_KEY_SECRET`, `_WEBHOOK_SECRET` | online payments (`rzp_test_` keys first) |
| `ANDROID_KEYSTORE_PASSWORD` | the Play upload key, `key.properties`, and the SHA-1 for Google's Android client |
| `LINK_HOST` (where `site/` is published, e.g. `shyammobiles.in`) | share links `https://<LINK_HOST>/open?p=…&ref=…` in the app, and the App Link the build claims |
| `PLAY_SIGNING_SHA256` (Play Console > Setup > App signing, after the first upload) | share links open copies installed from Play, not only the sideloaded `.apk` |
| `FCM_SERVICE_ACCOUNT` + `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID` | phone notifications (paste these to turn them on; see below). Without them the app still shows every notification inside the app |
| business details | policy pages filled into `build/site/`, ready to publish |

Outputs: `app/env/prod.json` (app build settings), `app/android/upload-keystore.jks` + `key.properties` (back
them up: without them the app can never be updated), `build/site/` (with `.well-known/assetlinks.json` from the
upload key's SHA-256 and `PLAY_SIGNING_SHA256`), and the release `.aab` and `.apk`.

After the first run:
- Send yourself a phone code once: MSG91's API is wired from its docs, so the first real send is the check
  (Supabase > Authentication > Logs show MSG91's error text if it refuses).
- Razorpay webhook: `https://<ref>.supabase.co/functions/v1/razorpay-webhook`, events `payment.captured`,
  `payment.failed`, `refund.processed`.
- Google Cloud Android client: package `com.shyammobiles.app`, the SHA-1 the script prints, and Play's app-signing
  SHA-1 (Play Console > Setup > App signing) once the first bundle is uploaded.
- Share links work once `build/site/` is published at `https://<LINK_HOST>`: `/open` must serve `open.html`
  (most hosts drop the `.html`; GitHub Pages also needs an empty `.nojekyll` to publish `.well-known/`). Without the
  app, the page sends people to Play with the link as the install referrer, so the app opens it on first launch.
  Rebuild the app after setting `LINK_HOST`: the manifest's App Link host comes from `env/prod.json`.
- Phone notifications: in the Firebase console make a project, add an Android app with package
  `com.shyammobiles.app` (skip the google-services.json download: the app reads the keys from its build settings), then
  paste into `.env.local`: from Project settings > General > Your apps, the app's `apiKey` → `FIREBASE_API_KEY`,
  `appId` → `FIREBASE_APP_ID`, `messagingSenderId` → `FIREBASE_MESSAGING_SENDER_ID`, `projectId` →
  `FIREBASE_PROJECT_ID`; from Project settings > Service accounts > Generate new private key, the downloaded file's path
  (or its JSON on one line) → `FCM_SERVICE_ACCOUNT`. Run `python3 scripts/launch.py --only secrets,functions,push,app,build`:
  send-push gets the key and a fresh shared secret, the database (Vault) learns where send-push is, and the new build
  asks for notification permission after the first order or repair booking. Keep the key file private.
- Not keys: Supabase Pro, the Play developer account, real products, a courier and the delivery fee.
