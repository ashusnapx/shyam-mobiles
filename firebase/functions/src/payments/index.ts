import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall, onRequest, type FunctionsErrorCode } from "firebase-functions/v2/https";
import { firestoreDb } from "./firestore.js";
import { checkPayment, createPayment, type Deps, refund, webhook } from "./payments.js";
import { PaymentError, type PhonePe, phonePe } from "./phonepe.js";

// The PhonePe Cloud Functions (docs/PHONEPE.md). Wire in with `export * from "./payments/index.js"` after
// initializeApp(). Callables need a signed-in user; phonepeRefund also needs the `admin` custom claim.
const PHONEPE_ENV = defineString("PHONEPE_ENV"); // sandbox | production
const PHONEPE_CLIENT_ID = defineString("PHONEPE_CLIENT_ID");
const PHONEPE_CLIENT_VERSION = defineString("PHONEPE_CLIENT_VERSION");
const PHONEPE_MERCHANT_ID = defineString("PHONEPE_MERCHANT_ID");
const PHONEPE_CLIENT_SECRET = defineSecret("PHONEPE_CLIENT_SECRET");
const PHONEPE_WEBHOOK_USERNAME = defineSecret("PHONEPE_WEBHOOK_USERNAME");
const PHONEPE_WEBHOOK_PASSWORD = defineSecret("PHONEPE_WEBHOOK_PASSWORD");

const options = { region: "asia-south1", secrets: [PHONEPE_CLIENT_SECRET] };

let client: PhonePe | null = null; // one per instance, so its OAuth token is reused
function deps(): Deps {
  client ??= phonePe({
    env: PHONEPE_ENV.value(), clientId: PHONEPE_CLIENT_ID.value(), clientSecret: PHONEPE_CLIENT_SECRET.value(),
    clientVersion: PHONEPE_CLIENT_VERSION.value(), merchantId: PHONEPE_MERCHANT_ID.value(),
  });
  return { db: firestoreDb(), pp: client };
}

const CODES: Record<number, FunctionsErrorCode> = {
  400: "invalid-argument", 401: "unauthenticated", 403: "permission-denied", 404: "not-found", 409: "failed-precondition",
  502: "unavailable",
};

// Our {code, message} reach the app as HttpsError details, so errors.dart can keep matching on the code.
async function call<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof PaymentError) throw new HttpsError(CODES[e.status] ?? "internal", e.message, { code: e.code });
    console.error(e);
    throw new HttpsError("internal", "Something went wrong. Try again.");
  }
}

const body = (data: unknown) => (data && typeof data === "object" && !Array.isArray(data) ? (data as Record<string, unknown>) : {});
const uid = (auth: { uid: string } | undefined) => {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in again.", { code: "UNAUTHORIZED" });
  return auth.uid;
};

export const phonepeCreatePayment = onCall(options, (req) => call(() => createPayment(body(req.data), uid(req.auth), deps())));

export const phonepeCheckPayment = onCall(options, (req) => call(() => checkPayment(body(req.data), uid(req.auth), deps())));

export const phonepeRefund = onCall(options, (req) => {
  const staff = uid(req.auth);
  if (req.auth?.token.admin !== true) throw new HttpsError("permission-denied", "This is for Shyam Mobiles staff.", { code: "FORBIDDEN" });
  return call(() => refund(body(req.data), staff, deps()));
});

// PhonePe calls this (dashboard → Webhooks, "SHA" auth with the username and password below). No Firebase auth.
export const phonepeWebhook = onRequest(
  { ...options, secrets: [PHONEPE_CLIENT_SECRET, PHONEPE_WEBHOOK_USERNAME, PHONEPE_WEBHOOK_PASSWORD] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ result: "method_not_allowed" });
      return;
    }
    try {
      const [status, out] = await webhook(req.get("authorization"), req.rawBody.toString("utf8"),
        { username: PHONEPE_WEBHOOK_USERNAME.value(), password: PHONEPE_WEBHOOK_PASSWORD.value() }, deps());
      res.status(status).json(out);
    } catch (e) {
      console.error("phonepe webhook:", e);
      res.status(500).json({ result: "retry" }); // PhonePe retries
    }
  },
);
