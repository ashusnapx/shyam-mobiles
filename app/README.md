# Shyam Mobiles app

Flutter app for the shop (Android first). Product, money and security rules: `../docs/SPEC.md`.

```sh
flutter run --dart-define-from-file=env/dev.json      # local stack, see env/example.json
flutter analyze                                        # must be clean (strict lints in analysis_options.yaml)
flutter test --concurrency=1
```

## Release build

1. `env/prod.json`: the production `SUPABASE_URL` (https), `SUPABASE_PUBLISHABLE_KEY` (`sb_publishable_…`),
   `RAZORPAY_KEY_ID` (`rzp_live_…`), `GOOGLE_WEB_CLIENT_ID`, `POLICIES_URL`. Never `DEV_*` keys; they are
   compiled out of release builds anyway (`Env.devLogin`), and nothing secret belongs in the app.
2. `android/key.properties` (gitignored) with `storeFile` (path relative to `android/app`), `storePassword`,
   `keyAlias`, `keyPassword`. Codemagic writes it from its keystore secrets. Without it the build is debug-signed
   and Play rejects it.
3. Build:

   ```sh
   flutter build appbundle --release \
     --dart-define-from-file=env/prod.json \
     --obfuscate --split-debug-info=build/symbols/$(git rev-parse --short HEAD)
   ```

   `--obfuscate` renames Dart symbols; R8 (`isMinifyEnabled`, `proguard-rules.pro`) does the same for Java/Kotlin.
   Keep `build/symbols/<sha>` and `build/app/outputs/mapping/release/mapping.txt` for every upload (Sentry / Play
   Console) or stack traces can't be read. `flutter symbolize -i <trace> -d build/symbols/<sha>/app.android-arm64.symbols`.

Release manifest: no cleartext (only the debug/profile manifests allow it, for the local stack), backups off, no
deep-link intent filters on our activity, and the only runtime permission is location (address form, asked on tap).

### FLAG_SECURE: not set, on purpose

Card numbers, CVV, UPI PIN and bank OTPs are only ever typed into Razorpay's own `CheckoutActivity` or the UPI app,
never into our screens, so there is nothing on our payment screens a screenshot or the recents thumbnail could leak
beyond the order summary. Customers screenshot that summary and the order number to share with the shop, so
blocking screenshots would cost support without protecting a secret. Admin screens show customers' names, phones
and addresses, which staff screenshot for the courier; the same reasoning applies. Revisit if a screen ever shows
saved cards or payment tokens.
