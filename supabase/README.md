# Shyam Mobiles backend (Supabase)

Contract: `docs/SPEC.md`.

## Local

```sh
colima start --cpu 2 --memory 3 --disk 40                   # 8 GB Macs: keep the VM small
cp supabase/.env.example supabase/.env                      # GOOGLE_* only needed to test Google sign-in
supabase start -x studio,realtime,imgproxy,postgres-meta,supavisor,logflare,vector,mailpit,edge-runtime
                                                            # API :54321; drop mailpit from -x to read email codes (:54324)
supabase db reset                                           # migrations + seed.sql
supabase test db                                            # pgTAP: supabase/tests/*.test.sql
python3 scripts/api_e2e.py                                  # attack + E2E suite over HTTP (after dev_setup.py; with functions serve)
supabase db lint && supabase db advisors --level info       # plpgsql check + security/performance advisors
(cd supabase/functions && deno check */index.ts && deno test --allow-env)   # Edge Function unit tests
cp supabase/functions/.env.example supabase/functions/.env  # fake Razorpay values are fine locally
supabase functions serve --env-file supabase/functions/.env # starts the edge runtime while it runs
supabase stop && colima stop
```

`[auth]` changes in config.toml (the access token hook, confirmations) load only on `supabase start`; `db reset` restarts Auth with its old settings.

Advisor findings left on purpose: `unused_index` (empty local DB) and `rls_enabled_no_policy` on `admins` and `payment_events` (no client access at all).

Edge Functions read `SUPABASE_URL`, `SUPABASE_SECRET_KEYS` and `SUPABASE_JWKS` through `@supabase/server` (provisioned by the platform and the CLI); nothing reads the legacy `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`.

Test sign-in: phone `+919999999999`, code `123456`. Email codes land in Mailpit.

Webhook smoke test (with `functions serve` running and `RAZORPAY_WEBHOOK_SECRET=whsec_local` in the env file):

```sh
BODY='{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_x","order_id":"order_x","amount":100}}}}'
SIG=$(printf %s "$BODY" | openssl dgst -sha256 -hmac whsec_local | sed 's/.* //')
curl -i http://127.0.0.1:54321/functions/v1/razorpay-webhook \
  -H "x-razorpay-event-id: evt_$(date +%s)" -H "x-razorpay-signature: $SIG" -d "$BODY"   # 200
curl -i http://127.0.0.1:54321/functions/v1/razorpay-webhook \
  -H "x-razorpay-event-id: evt_bad" -H "x-razorpay-signature: deadbeef" -d "$BODY"       # 401
curl -i http://127.0.0.1:54321/functions/v1/create-payment -d '{}'                       # 401 (no user JWT)
```

## Make someone staff (after their first sign-in)

```sh
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -v who=owner@example.com -f supabase/scripts/make_admin.sql
psql "$PROD_DB_URL" -v who=+919876543210 -f supabase/scripts/make_admin.sql   # Dashboard → Connect → connection string
```

## Deploy

```sh
supabase login
supabase link --project-ref <ref>
supabase db push                                            # migrations only; seed.sql is local-only
supabase secrets set RAZORPAY_KEY_ID=rzp_live_xxx RAZORPAY_KEY_SECRET=xxx RAZORPAY_WEBHOOK_SECRET=xxx
supabase functions deploy                                   # all four; verify_jwt from config.toml
```

Do not `supabase config push` as-is: config.toml has the local test OTP and a dummy Twilio provider. Set auth in the dashboard instead:

- Auth → Hooks → Customize Access Token (JWT) Claims: on, Postgres, schema `private`, function `custom_access_token_hook`. It refuses password sign-ins (sign-in is passwordless); without it anyone can pre-register a customer's email or phone with a password and later read their orders. Keep `private.password_sign_in_domains` empty in production.
- Auth → Providers → Phone: on, phone confirmations on, SMS provider with a DLT-registered template; no test numbers.
- Auth → Providers → Email: on, confirm email on (a new user's first code is the confirmation; OTP sign-in works the same), OTP length 6, expiry 600 s. Email templates "Magic link" and "Confirm signup": paste `supabase/templates/otp.html` (uses `{{ .Token }}`). Custom SMTP on.
- Auth → Providers → Google: on, client IDs = web client id first, then the Android (and later iOS) ids, comma-separated; secret. "Skip nonce check" off for the Android-only v1; turn it on only when iOS ships (the iOS SDK can't pass the nonce).
- Auth → Rate limits: emails 30/h, SMS 60/h, sign-ins 20 per 5 min, verifications 30 per 5 min.
- SMS provider: Twilio (or Twilio Verify, MessageBird, Vonage, TextLocal) is built in. MSG91 is not: it needs a [Send SMS hook](https://supabase.com/docs/guides/auth/auth-hooks/send-sms-hook) (an HTTP Edge Function that verifies the Standard Webhooks signature and calls MSG91 with the DLT template id). Not built in v1.
- Auth → Bot and Abuse Protection: CAPTCHA (Cloudflare Turnstile or hCaptcha) is the documented guard against SMS pumping. Turning it on makes every OTP request need a `captchaToken` from the app, so enable it only together with an app release that sends one.
- Settings → JWT Keys: the project must sign with an asymmetric key (ECC/RSA; the default on new projects). `@supabase/server` rejects tokens signed with the legacy JWT secret. On an older project: migrate the JWT secret, rotate to the new key.
- Settings → API Keys: the app ships the publishable key (`sb_publishable_…`). Once no shipped build uses the legacy `anon` key, disable the legacy keys (Supabase removes them by the end of 2026).
- Integrations → Data API: leave "Automatically expose new tables" off; `20261028000300_grants.sql` grants exactly what the app needs.

## Razorpay dashboard

- Account & Settings → Payment capture: **Automatic**.
- Webhooks → Add new webhook:
  - URL: `https://<ref>.supabase.co/functions/v1/razorpay-webhook`
  - Secret: the `RAZORPAY_WEBHOOK_SECRET` value
  - Events: `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`
- API keys: key id goes in the app (`RAZORPAY_KEY_ID` dart-define) and in the function secrets; key secret only in the function secrets.
