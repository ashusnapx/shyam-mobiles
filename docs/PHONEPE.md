# PhonePe Payment Gateway: what Shyam Mobiles uses and how

Checked 2026-11-03 against PhonePe's developer docs, PhonePe's own backend SDK source (Python 2.1.5) and the
`phonepe_payment_sdk` 3.0.2 Flutter plugin. PhonePe replaces Razorpay to cut fees. Until PhonePe is verified with real
sandbox credentials, **Razorpay stays the default** (the owner's phone runs against production, where only Razorpay is
set up). At the Firebase cut-over PhonePe becomes the only gateway (docs/FIREBASE.md D4) and Razorpay is removed.

## The switch

| Where | Setting | Values |
|---|---|---|
| App | `PAYMENT_GATEWAY` dart-define (env/*.json) | `razorpay` (default) or `phonepe` |
| Backend | Cloud Functions in `firebase/functions/src/payments/` (`createPayment`, `verifyPayment`, `phonepeWebhook`, `startRefund`) | PhonePe only; needs the secrets below |

With `phonepe` the app takes the order token from the backend, opens PhonePe's pay page and then asks the backend
whether it was paid. The "EMI from ₹X/month" line, "Send payment link" and the "Instant refund" toggle are hidden
(Razorpay features PhonePe has no API for; see the table below). The SDK sits behind `PaymentGateway`
(`PhonePePaymentGateway`, `app/lib/features/payments/data/payment_gateway.dart`) and the backend calls behind
`PaymentsRepository` (`payments_repository.dart`): until the Firebase implementation is wired into
`paymentsRepositoryProvider`, choosing PhonePe shows "Online payment isn't available right now".

## How a payment works

1. The order is placed as today; the amount is priced on the server.
2. `createPayment {orderId}`: checks the order is the caller's, unpaid and inside its 15-minute stock hold, then
   creates a PhonePe order for the order's own total (`POST /checkout/v2/sdk/order`, `merchantOrderId` =
   `SM100001-xxxxxxxx`, window = what is left of the hold, 5–60 minutes) and returns its token. An order has at most
   pending attempt (`orders/{id}/payments/{merchantOrderId}`): asking again first checks that one with PhonePe (paid → done; failed → a new one; pending →
   the same token), so a customer never has two payments in flight.
3. The app opens the SDK (`PAY_PAGE`). Whatever the SDK says (on Android `SUCCESS` only means the pay page closed), the
   app calls `verifyPayment {orderId}`, which asks PhonePe's order status API and hands the answer to the orders
   settlement (`settleOnlinePayment`). Only `COMPLETED` with exactly the order's total marks the order paid.
4. The webhook does the same from PhonePe's side, so a payment finishes even if the customer closes the app.
5. A payment that lands after the order expired, or a second payment for a paid order, is the settlement's to flag for a
   refund (docs/FIREBASE.md §3, "Payment idempotency").

Refunds (`startRefund`, staff only): everything left (cancelled or delivered orders) or chosen items at what was paid
for them. Our refund id is PhonePe's `merchantRefundId`; a retry asks PhonePe for that refund first and sends it only
if PhonePe has never heard of it, so a refund never goes out twice. One refund in flight per order. PhonePe's
`pg.refund.*` webhooks settle it through the refund status API (`settleRefund`).

## Webhook

PhonePe sends `Authorization: <hex SHA-256 of "username:password">`, the pair you type when creating the webhook
(PhonePe's SDKs check it the same way). That value never changes and doesn't cover the body, so the webhook compares it
in constant time and then **treats the body as a hint only**: it reads the `merchantOrderId` / `merchantRefundId` and
asks PhonePe's status API for the facts. Repeats are harmless (every write is idempotent). Unknown ids and amount
mismatches are acknowledged (200) and logged; a PhonePe or database outage answers 500 so PhonePe retries.

## Turn on in the PhonePe dashboard (business.phonepe.com)

| What | Why | Where |
|---|---|---|
| **API keys** (Test mode first, then Live) | Client ID, Client Secret, Client Version, Merchant ID | Developer Settings |
| **Webhook**, auth type "SHA" (username + password) | URL `https://asia-south1-shyam-mobiles.cloudfunctions.net/phonepeWebhook`; events `checkout.order.completed`, `checkout.order.failed`, `pg.refund.completed`, `pg.refund.failed` (and `pg.refund.accepted` if offered) | Developer Settings → Webhooks |
| **Simulator access** for sandbox | Sandbox payments on Android run in the "PhonePe PG Simulator" app (`com.phonepe.simulator`); PhonePe's integration team invites your email. Pick a "Paypage" template for success / failure / pending | Ask on the integration thread |
| **Card EMI on the pay page** (optional) | PhonePe's checkout can show EMI itself; there is no API to read plans | Ask your PhonePe account manager |
| **Payment Link API** (optional, later) | Needs PhonePe's approval | PhonePe Business team |

## Parity with what we built on Razorpay

| Razorpay feature | PhonePe | Verdict |
|---|---|---|
| Standard Checkout (UPI, cards, netbanking, wallets) | Standard Checkout pay page via `phonepe_payment_sdk` | replaced |
| `verify-payment` (checkout signature) | order status API; PhonePe has no client-side signature | replaced (stricter: always the API) |
| Webhooks paid / failed | `checkout.order.completed` / `failed` | replaced |
| Refunds, full or by item, idempotent | Refund API with our id as `merchantRefundId`, status first on retry | replaced |
| Instant refunds | no option in PhonePe's refund API | dropped (toggle hidden) |
| Refunds made in the dashboard marked automatically | their webhooks carry a refund id we never made | dropped: staff tap "Mark refunded" |
| Payment links on WhatsApp | Payment Link API exists but needs PhonePe's approval [3] | later: hidden. Meanwhile staff can make links in the PhonePe Business dashboard (the app doesn't see those payments). Proposal: an app link to the order's pay screen (`https://<LINK_HOST>/open?order=…`) for customers who have the app, or ask PhonePe for Payment Link API access and rebuild links on it |
| "EMI from ₹X/month" | no EMI plan API | dropped (line hidden); EMI can still show inside PhonePe's pay page |
| Saved cards (Razorpay customer) | PhonePe's pay page keeps tokenised cards itself; no merchant API | dropped, nothing to build |
| Dispute webhooks | not in PhonePe's PG v2 webhook list | dropped: check the dashboard's chargeback section |

## Data the functions read and write (Firestore)

Shapes are docs/FIREBASE.md §3's. The payment functions write only their own documents and two order fields; every
other order change is `orders/settlement.ts`'s.

| Document | Payments reads | Payments writes |
|---|---|---|
| `orders/{id}` | `uid, number, status, paymentMethod, paymentStatus, totalPaise, reservedUntil, payment.merchantOrderId, pendingRefundId, items[]` | `pendingRefundId` and `items[].refundId` when a refund starts |
| `orders/{id}/payments/{merchantOrderId}` | all | created `{state: 'pending', amountPaise, phonepeOrderId, token, expireAt, transactionId: null, createdAt, updatedAt}`; closed (`failed`) when its token never left the server. `settleOnlinePayment` moves it to `completed` / `failed`. `phonepeOrderId` is an addition to §3: the SDK needs it to reopen the same order |
| `orders/{id}/refunds/{refundId}` | `amountPaise, status` | created `{amountPaise, fullRefund, restock, status: 'pending', gatewayRefundId: null, failure: null, createdBy, createdAt, updatedAt}`; `settleRefund` settles it and clears `pendingRefundId` |

Ids: `merchantOrderId` = `SM100001-3fa2b9c1`, `refundId` (= PhonePe's `merchantRefundId`) = `SM100001-R3fa2b9c`. The
webhook finds the order by its number (`orders where number ==`), so no extra index is needed.

## Secrets and settings (Cloud Functions)

Param `PHONEPE_ENV` (`SANDBOX` / `PRODUCTION`, nothing else). Secrets (Secret Manager, `defineSecret`):
`PHONEPE_CLIENT_ID`, `PHONEPE_CLIENT_SECRET`, `PHONEPE_CLIENT_VERSION`, `PHONEPE_MERCHANT_ID`, `PHONEPE_WEBHOOK_USER`,
`PHONEPE_WEBHOOK_PASSWORD`. Test values live in `~/.config/shyam-mobiles/phonepe-test.env` (mode 600), never in the repo.

## The app's Android setup

`MainActivity` is a `FlutterFragmentActivity` (the plugin registers an activity-result launcher and crashes on a plain
`FlutterActivity`), `android/build.gradle.kts` adds PhonePe's Maven repository, and `proguard-rules.pro` keeps
`com.phonepe.**`. The SDK brings its own `<queries>` for UPI apps. Upstream `phonepe_payment_sdk` 3.0.2 doesn't build
with AGP 9 (it minifies itself with `proguard-android.txt` and compiles against SDK 31), so the app uses a vendored copy
with those two lines fixed: `app/third_party/phonepe_payment_sdk/README.md`. A release build (R8) was checked on
2026-11-03: PhonePe's activity, plugin and SDK classes are kept and its UPI `<queries>` merged.

## Fees (2026-11-03)

PhonePe's PG page advertises "1.99% FREE* – Limited Period Offer", zero setup fee and zero annual maintenance, with
"T&C apply" and no end date shown [1]. Third-party listings give 1.95% after the offer [2]. PhonePe's own guide says UPI
and RuPay debit cards usually carry zero or low MDR and credit cards cost the most [4]. Confirm the shop's rates, the
offer's end date and any volume cap with PhonePe before switching, and compare with docs/COSTS.md.

## Sources

- [1] PhonePe Payment Gateway: https://business.phonepe.com/payment-gateway
- [2] Capterra, PhonePe Payment Gateway pricing (third party): https://capterra.com/p/10027485/PhonePe-Payment-Gateway/
- [3] Payment Link API (approval needed): https://developer.phonepe.com/payment-gateway/payment-links/introduction
- [4] PhonePe, payment gateway charges in India: https://business.phonepe.com/articles/payment-gateway-charges-in-india-complete-mdr-and-fee-breakdown
- Flutter SDK setup: https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile/flutter/sdk-setup
- Authorization (OAuth token): https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile/api-reference/authorization
- Create order token: https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile/api-reference/create-order-token
- Order status: https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile/api-reference/check-order-status
- Refund and refund status: https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile/api-reference/refund
- Webhooks: https://developer.phonepe.com/payment-gateway/mobile-app-integration/standard-checkout-mobile/webhook-handling
- Callback check in PhonePe's SDKs: https://developer.phonepe.com/payment-gateway/backend-sdk/nodejs-be-sdk/api-reference-node-js/webhook-handling
- UAT sandbox: https://developer.phonepe.com/payment-gateway/uat-testing-go-live/uat-sandbox
- Plugin: https://pub.dev/packages/phonepe_payment_sdk
