# firebase/: the Firebase backend

The plan and the data model are in `docs/FIREBASE.md`, and the security rules every function follows are in
`docs/SECURITY.md`. This file covers how to work in this folder.

```
firebase.json  .firebaserc (default shyam-mobiles, alias demo)  .nvmrc (22)
firestore.rules  firestore.indexes.json  storage.rules
test-vectors/        cases ported from supabase/tests/*.sql and scripts/api_e2e.py (format below)
functions/
  src/index.ts       FROZEN: one `export *` per domain
  src/shared/        options, callable, errors, auth, validation, money, time, rateLimit, log, db
  src/model/         Firestore document types (docs/FIREBASE.md §3), with each collection's retention
  src/<domain>/      contract.ts (zod in/out), handlers.ts, index.ts, plus pure modules and repository.ts
  test/unit/         no emulator: shared modules, vectors ↔ contracts, input rules, errors ↔ app, retention
  test/rules/        Security Rules on the Firestore + Storage emulators
  test/integration/  callables on the full emulator suite (the api_e2e.py port grows here)
```

## Running it on the 8 GB Mac

Do one heavy thing at a time. Never run the emulators, `flutter test` and a Gradle build together.

```sh
cd firebase/functions
nvm use                  # Node 22 from ../.nvmrc. Node 20 stays the default for other tools
npm ci
npm run build            # tsc → lib/
npm run typecheck        # src + tests
npm run lint             # typescript-eslint strict, plus the layering rule
npm test                 # unit tests, no emulator, one fork
npm run test:rules       # starts the Firestore + Storage emulators, runs test/rules, stops them
npm run test:int         # builds, starts auth/firestore/functions/storage, runs test/integration, stops them
npm run emulators        # the suite for the app (UI on :4000); Ctrl-C to stop it and give the RAM back
```

- `firebase-tools` 15.34.2 is installed globally under Node 22 (`~/.nvm/versions/node/v22.23.4/bin`). The Firestore
  emulator needs Java ≥ 21; Java 22 is installed. The first emulator run downloads about 150 MB of jars into
  `~/.cache/firebase/emulators`.
- Every script uses the project id `demo-shyam-mobiles`. A `demo-` project can't reach anything real and needs no
  login. Never run `firebase deploy` or `firebase use` from a laptop: deploys go through CI (SECURITY §2.4).
- The emulators get `JAVA_TOOL_OPTIONS=-Xmx512m`, which keeps the whole suite at about 1–1.3 GB.
- App against the emulators: `flutter run --dart-define=BACKEND=firebase --dart-define=USE_EMULATORS=true`. On a USB
  phone, first run `adb reverse tcp:9099 tcp:9099`, and the same for 8080, 5001 and 9199. On the Android emulator
  image, add `--dart-define=EMULATOR_HOST=10.0.2.2`.

## Who owns what (docs/FIREBASE.md §7)

| Engineer | Backend | App |
|---|---|---|
| A, platform and identity | `firebase.json`, `.firebaserc`, `functions/{package.json,tsconfig*.json,eslint.config.mjs,vitest.config.ts}`, `src/index.ts`, `src/shared/**`, `src/health/**`, `src/account/**`, `src/model/{users,retention}.ts`, Rules helpers and sections `users`/`devices`, `test-vectors/input.json` | `core/{backend,firebase,callable,telemetry}.dart`, `features/auth/**`, `features/account/data/**`, `core/push.dart` (registration) |
| B, catalog and storage | `src/catalog/**`, `src/model/{catalog,settings}.ts`, `storage.rules`, Rules sections catalog/settings/banners/collections/wishlists, `seed/**` | `features/{catalog,wishlist}/data/**`, `admin/data/{catalogue,photos,rules,catalog_admin_repository,photo_store}.dart` |
| C, commerce (money) | `src/{orders,offers,referrals}/**`, `src/model/{orders,offers}.ts`, Rules sections carts/addresses/orders/offers, `test-vectors/{pricing,offers,referrals,orders-state,settlement}.json` | `features/{cart,checkout,orders,offers}/data/**`, `admin/data/{admin,offers_admin,offers_admin_repository}.dart` (orders and offers parts) |
| D, payments and service | `src/{payments,notifications,repairs,feedback,invoices}/**`, `src/model/{repairs,feedback,notifications}.ts`, Rules sections repairs/feedback/notifications | `features/{payments,repairs,feedback,notifications}/data/**` |

`firestore.rules` is one file split into commented sections. Edit only your own section, and A reviews the change.
Add to `firestore.indexes.json` only together with the query that needs the index.

## The frozen entry

`functions/src/index.ts` imports `shared/options.js` (the region and the global limits) and then has one
`export * from "./<domain>/index.js"` line per domain. It does not change after Phase 0. A domain adds a function by
exporting it from its own `index.ts`, so two engineers never edit the same file to ship a function.

## Adding a callable

1. **Contract** in `src/<domain>/contract.ts`:

   ```ts
   export const cancelOrder = contract("cancelOrder", z.strictObject({ orderId: v.docId }), z.object({}));
   ```

   Inputs use the shared rules in `shared/validation.ts` (`v.phone`, `cleanText(max)`, `v.typedCode`…). Input that
   fails the schema gets `BAD_REQUEST`, or the contract's own reason when the app has better copy for it (for
   example `INVALID_IMEIS`, the 4th argument).
2. **Handler** in `handlers.ts`:

   ```ts
   export const cancelOrder = callable(c.cancelOrder, async ({ orderId }, req) => {
     const { uid } = requireUser(req);
     await db().runTransaction(async (tx) => { /* load → decide (pure module) → write */ });
     return {};
   });
   ```

   `callable()` applies the shared options: asia-south1, App Check enforced outside the emulator, `maxInstances` 10
   and a 30 s timeout. It parses the input, checks the output, and turns any error that isn't `fail(...)` into a
   logged `INTERNAL`. Pass `REPLAY_PROTECTED` as the 3rd argument for placeOrder, createPayment, startRefund,
   setRole, deleteAccount and adminDeleteAccount. Their handlers also call `rejectConsumedAppCheck(req)`.
3. **Guards** (`shared/auth.ts`):
   - `requireUser`.
   - `requireStaff`: the `role` claim, a TOTP session, and the role still on `users/{uid}`.
   - `requireOwner`.
   - `requireRecentLogin` (5 minutes) for setRole, startRefund and the account deletions.
   - `takeRateLimit(tx, uid, key)` for the per-user limits in `shared/rateLimit.ts`.
4. **Fail with a reason:** `fail("OUT_OF_STOCK", variantIds)`. The reasons are the app's `errors.dart` codes.
   `test/unit/errors.test.ts` fails if a reason has no app copy, so add the copy there in the same change.
5. **Export it** from `src/<domain>/index.ts` (this is already done for every domain).
6. **Test it:** unit-test the pure module against its vectors, then the Rules, then an integration test.
7. **App:** `callFunction(ref.read(functionsProvider), 'cancelOrder', {'orderId': id})` (`lib/core/callable.dart`)
   from the domain's Firebase repository.

### Layering (enforced by ESLint)

- Handlers, `repository.ts`, `triggers.ts`, `settlement.ts`, `index.ts` and `shared/` may import `firebase-admin`
  and `firebase-functions`.
- Every other module stays pure (`pricing.ts`, `state.ts`, `notices.ts`, `contract.ts`, `model/`). It may use type
  imports, so unit tests run it without an emulator.

### Security defaults (docs/SECURITY.md)

- **Secrets:** only `defineSecret(...)` (Secret Manager), bound to the functions that use them. There are no `.env`
  secrets; `.secret.local` is for the emulator only and is gitignored.
- **Logging:** only `log`/`audit` from `shared/log.ts`, never `console` (lint enforces this). The logger redacts
  personal fields (names, phones, addresses, tokens, free text) and scrubs phone numbers, emails and tokens out of
  strings. Every staff action writes one `audit(action, actorUid, targetId)` line.
- **Retention:** every collection in `src/model/*.ts` declares its retention. `test/unit/retention.test.ts` fails
  when one is missing.

## Test vectors (`test-vectors/*.json`)

The vectors are data that C's unit tests, the integration tests and the app can all run. `test/vectors.ts` loads
them, validates them, and resolves the times.

```jsonc
{
  "about": "…", "now": "2026-11-03T12:00:00+05:30",
  "world": { "settings/store": { … }, "variants/v1": { … } },          // docs in the §3 shapes
  "cases": [{
    "id": "coupon-min-order-names-the-minimum", "source": "supabase/tests/offers.test.sql:142",
    "as": "alice",                                   // a users/{uid} in world, "anon" or "system"
    "given": { "carts/alice": { … }, "promotions/p5": null },    // replaces world docs; null removes one
    "call": "quoteOrder", "input": { "couponCode": "WELCOME" },
    "expect": { "couponError": "COUPON_MIN_ORDER" },  // deep-partial; or "error" + "errorDetail"
    "then": { "variants/v2": { "stock": 49 }, "orders/$orderId": { … } }  // docs afterwards, deep-partial
  }],
  "notExpressed": [{ "source": "…", "why": "…" }]
}
```

The matching rules:

- **Money:** always integer paise.
- **Times:** ISO strings, or `@now`, `@now+15m`, `@now-2d`.
- **Arrays** in `expect`/`then` match element by element and must have the same length.
- **`null`** in `then` means the field is absent or null.
- **Placeholders:** `$orderId`, `$refundId` and `$id` stand for ids the call returned. A key ending in `/*` means the
  one doc in that collection.
- **`input.json`** has its own shape: `{rules: {<name>: {valid: [], invalid: []}}}`. zod (`test/unit/validation.test.ts`),
  Rules and `app/lib/core/input.dart` must all agree with it.

`test/unit/vectors.test.ts` checks three things:

- every file parses;
- case ids are unique;
- every case's input passes its callable's contract, unless the case expects the contract's invalid-input reason.
</content>
</invoke>
