import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onRequest } from "firebase-functions/v2/https";
import { settleOnlinePayment, settleRefund } from "../orders/settlement.js";
import { rejectConsumedAppCheck, requireRecentLogin, requireStaff, requireUser } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { db } from "../shared/db.js";
import { REASONS, type Reason } from "../shared/errors.js";
import { audit, log } from "../shared/log.js";
import { PAYMENTS, REPLAY_PROTECTED } from "../shared/options.js";
import { type LimitKey, takeRateLimit } from "../shared/rateLimit.js";
import * as c from "./contract.js";
import { createPayment as create, type Deps, phonepeWebhook as webhook, startRefund as refund, verifyPayment as verify } from "./flows.js";
import type { PaymentGateway } from "./gateway.js";
import { phonePeGateway } from "./phonepe.js";
import { PaymentError } from "./service.js";

// The payment callables and PhonePe's webhook (docs/FIREBASE.md §5, docs/SECURITY.md §2.1, §2.6). The flows in
// flows.ts do the work; this file adds the guards, the limits and the shared error shape.
const PHONEPE_ENV = defineString("PHONEPE_ENV"); // SANDBOX | PRODUCTION
const PHONEPE_CLIENT_ID = defineSecret("PHONEPE_CLIENT_ID");
const PHONEPE_CLIENT_SECRET = defineSecret("PHONEPE_CLIENT_SECRET");
const PHONEPE_CLIENT_VERSION = defineSecret("PHONEPE_CLIENT_VERSION");
const PHONEPE_MERCHANT_ID = defineSecret("PHONEPE_MERCHANT_ID");
const PHONEPE_WEBHOOK_USER = defineSecret("PHONEPE_WEBHOOK_USER");
const PHONEPE_WEBHOOK_PASSWORD = defineSecret("PHONEPE_WEBHOOK_PASSWORD");
const api = [PHONEPE_CLIENT_ID, PHONEPE_CLIENT_SECRET, PHONEPE_CLIENT_VERSION, PHONEPE_MERCHANT_ID];

let gateway: PaymentGateway | null = null; // one per instance, so the OAuth token is reused
function deps(): Deps {
  gateway ??= phonePeGateway({
    env: PHONEPE_ENV.value(), clientId: PHONEPE_CLIENT_ID.value(), clientSecret: PHONEPE_CLIENT_SECRET.value(),
    clientVersion: PHONEPE_CLIENT_VERSION.value(), merchantId: PHONEPE_MERCHANT_ID.value(),
  });
  return { db: db(), gateway, settlement: { settleOnlinePayment, settleRefund } };
}

/** Staff refusals whose message is the staff copy the app shows (app/lib/core/errors.dart has none for them). */
const STAFF_COPY = new Set<Reason>(["REFUND_NOT_ALLOWED", "REFUND_REFUSED"]);

/** A flow's PaymentError as the shared error shape (shared/errors.ts fail()). PAYMENT_IN_PROGRESS, a second tap while
 * the first is still making the PhonePe order, reads as GATEWAY_ERROR's "try again in a moment". */
async function run<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (!(e instanceof PaymentError)) throw e;
    const reason: Reason = Object.hasOwn(REASONS, e.reason) ? (e.reason as Reason) : "GATEWAY_ERROR";
    throw new HttpsError(REASONS[reason], STAFF_COPY.has(reason) ? e.message : reason, { reason });
  }
}

const limit = (uid: string, key: LimitKey) => db().runTransaction((tx) => takeRateLimit(tx, uid, key));
const options = { ...PAYMENTS, secrets: api };

export const createPayment = callable(c.createPayment, async (input, req) => {
  rejectConsumedAppCheck(req);
  const { uid } = requireUser(req);
  await limit(uid, "createPayment");
  return run(() => create(input, uid, deps()));
}, { ...REPLAY_PROTECTED, ...options });

export const verifyPayment = callable(c.verifyPayment, async (input, req) => {
  const { uid } = requireUser(req);
  await limit(uid, "verifyPayment");
  return run(() => verify(input, uid, deps()));
}, options);

/** Staff in a TOTP session, signed in within 5 minutes (SECURITY §2.2). */
export const startRefund = callable(c.startRefund, async (input, req) => {
  rejectConsumedAppCheck(req);
  const staff = await requireStaff(req);
  requireRecentLogin(staff);
  const r = await run(() => refund(input, staff.uid, deps()));
  audit("startRefund", staff.uid, input.orderId, { refundId: r.refundId, amountPaise: r.amountPaise, status: r.status, retry: r.retry });
  return r;
}, { ...REPLAY_PROTECTED, ...options });

// PhonePe calls this (dashboard → Webhooks, "SHA" auth with PHONEPE_WEBHOOK_USER / _PASSWORD). No Firebase auth, no App
// Check: the Authorization header is the check, and the body is only a hint.
export const phonepeWebhook = onRequest({ ...PAYMENTS, secrets: [...api, PHONEPE_WEBHOOK_USER, PHONEPE_WEBHOOK_PASSWORD] }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ result: "method_not_allowed" });
    return;
  }
  try {
    const [status, body] = await webhook(req.get("authorization"), req.rawBody.toString("utf8"),
      { username: PHONEPE_WEBHOOK_USER.value(), password: PHONEPE_WEBHOOK_PASSWORD.value() }, deps());
    if (status !== 200) log.warn("phonepe webhook refused", { status, result: body.result });
    res.status(status).json(body);
  } catch (e) {
    log.error("phonepe webhook failed", { error: e });
    res.status(500).json({ result: "retry" }); // PhonePe retries
  }
});
