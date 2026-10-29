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
| business details | policy pages filled into `build/site/`, ready to publish |

Outputs: `app/env/prod.json` (app build settings), `app/android/upload-keystore.jks` + `key.properties` (back
them up: without them the app can never be updated), `build/site/`, and the release `.aab` and `.apk`.

After the first run:
- Send yourself a phone code once: MSG91's API is wired from its docs, so the first real send is the check
  (Supabase > Authentication > Logs show MSG91's error text if it refuses).
- Razorpay webhook: `https://<ref>.supabase.co/functions/v1/razorpay-webhook`, events `payment.captured`,
  `payment.failed`, `refund.processed`.
- Google Cloud Android client: package `com.shyammobiles.app`, the SHA-1 the script prints, and Play's app-signing
  SHA-1 (Play Console > Setup > App signing) once the first bundle is uploaded.
- Not keys: Supabase Pro, the Play developer account, real products, a courier and the delivery fee.
