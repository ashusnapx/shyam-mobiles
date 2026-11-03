import { getFirestore } from "firebase-admin/firestore";
import { defineSecret, defineString } from "firebase-functions/params";
import { type CallableRequest, type FunctionsErrorCode, HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { settleOnlinePayment, settleRefund } from "../orders/settlement.js";
import { createPayment as create, type Deps, phonepeWebhook as webhook, startRefund as refund, verifyPayment as verify } from "./flows.js";
import type { PaymentGateway } from "./gateway.js";
import { phonePeGateway } from "./phonepe.js";
import { PaymentError } from "./service.js";

// The payment callables and PhonePe's webhook (docs/FIREBASE.md §5). The region comes from src/index.ts.
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
  return { db: getFirestore(), gateway, settlement: { settleOnlinePayment, settleRefund } };
}

const CODES: Record<number, FunctionsErrorCode> = {
  400: "invalid-argument", 401: "unauthenticated", 403: "permission-denied", 404: "not-found", 409: "failed-precondition",
  502: "unavailable",
};

// shortcut: local error and auth mapping until src/shared/{errors,auth}.ts land; then use fail() and requireUser/requireStaff
async function run<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof PaymentError) throw new HttpsError(CODES[e.status] ?? "internal", e.message, { reason: e.reason });
    if (e instanceof HttpsError) throw e;
    console.error(e);
    throw new HttpsError("internal", "Something went wrong. Try again.");
  }
}
const uid = (req: CallableRequest) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in again.", { reason: "UNAUTHORIZED" });
  return req.auth.uid;
};

export const createPayment = onCall({ secrets: api }, (req) => run(() => create(req.data, uid(req), deps())));

export const verifyPayment = onCall({ secrets: api }, (req) => run(() => verify(req.data, uid(req), deps())));

export const startRefund = onCall({ secrets: api }, (req) => {
  const staff = uid(req);
  if (req.auth?.token.role !== "owner" && req.auth?.token.role !== "staff") {
    throw new HttpsError("permission-denied", "This is for Shyam Mobiles staff.", { reason: "FORBIDDEN" });
  }
  return run(() => refund(req.data, staff, deps()));
});

// PhonePe calls this (dashboard → Webhooks, "SHA" auth with PHONEPE_WEBHOOK_USER / _PASSWORD). No Firebase auth, no App
// Check: the Authorization header is the check.
export const phonepeWebhook = onRequest({ secrets: [...api, PHONEPE_WEBHOOK_USER, PHONEPE_WEBHOOK_PASSWORD] }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ result: "method_not_allowed" });
    return;
  }
  try {
    const [status, body] = await webhook(req.get("authorization"), req.rawBody.toString("utf8"),
      { username: PHONEPE_WEBHOOK_USER.value(), password: PHONEPE_WEBHOOK_PASSWORD.value() }, deps());
    res.status(status).json(body);
  } catch (e) {
    console.error("phonepe webhook:", e);
    res.status(500).json({ result: "retry" }); // PhonePe retries
  }
});
