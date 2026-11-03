import { createHash, timingSafeEqual } from "node:crypto";
import { GatewayError, type GatewayRefund, type GatewayState, type PaymentGateway } from "./gateway.js";

// PhonePe Payment Gateway, PG v2 Standard Checkout (docs/PHONEPE.md). Hosts from PhonePe's own SDKs.
const HOSTS = {
  SANDBOX: { pg: "https://api-preprod.phonepe.com/apis/pg-sandbox", auth: "https://api-preprod.phonepe.com/apis/pg-sandbox" },
  PRODUCTION: { pg: "https://api.phonepe.com/apis/pg", auth: "https://api.phonepe.com/apis/identity-manager" },
};

export type PhonePeConfig = {
  env: string; // PHONEPE_ENV: "SANDBOX" | "PRODUCTION", nothing else, so a typo can't mix test and live traffic
  clientId: string;
  clientSecret: string;
  clientVersion: string;
  merchantId: string;
};

const state = (s: unknown): GatewayState => (s === "COMPLETED" ? "completed" : s === "FAILED" ? "failed" : "pending");

// One client per instance: the OAuth token is cached and renewed halfway through its life (what PhonePe's SDKs do), a
// 401 renews it once, every call times out after 10 s. Unreachable -> GatewayError status 0; an error reply ->
// GatewayError with PhonePe's status, code and message.
export function phonePeGateway(config: PhonePeConfig, fetcher: typeof fetch = fetch): PaymentGateway {
  if (config.env !== "SANDBOX" && config.env !== "PRODUCTION") throw new Error("PHONEPE_ENV must be SANDBOX or PRODUCTION");
  for (const [k, v] of Object.entries(config)) if (!v) throw new Error(`Missing PhonePe setting ${k}`);
  const hosts = HOSTS[config.env];
  let cached: { token: string; renewAt: number } | null = null;

  async function send(url: string, init: RequestInit, what: string): Promise<Response> {
    try {
      return await fetcher(url, { ...init, signal: AbortSignal.timeout(10_000) });
    } catch (e) {
      console.error(`phonepe ${what}:`, e);
      throw new GatewayError(0, "UNREACHABLE", String(e));
    }
  }

  async function failure(res: Response, what: string): Promise<GatewayError> {
    const text = await res.text();
    console.error(`phonepe ${what}: ${res.status} ${text.slice(0, 500)}`);
    let code = "", message = "";
    try {
      const body = JSON.parse(text);
      code = String(body?.errorCode ?? body?.code ?? "");
      message = String(body?.message ?? "");
    } catch { /* not JSON */ }
    return new GatewayError(res.status, code, message);
  }

  async function token(): Promise<string> {
    if (cached && Date.now() < cached.renewAt) return cached.token;
    const res = await send(`${hosts.auth}/v1/oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_version: config.clientVersion,
        client_secret: config.clientSecret,
        grant_type: "client_credentials",
      }),
    }, "token");
    if (!res.ok) throw await failure(res, "token");
    const t = await res.json();
    if (typeof t?.access_token !== "string" || !Number.isFinite(t.expires_at)) throw new Error("phonepe token: unexpected reply");
    const issued = Number.isFinite(t.issued_at) ? t.issued_at : Math.floor(Date.now() / 1000);
    cached = { token: `${t.token_type || "O-Bearer"} ${t.access_token}`, renewAt: (issued + (t.expires_at - issued) / 2) * 1000 };
    return cached.token;
  }

  async function call(path: string, body?: unknown): Promise<Record<string, unknown>> {
    for (let attempt = 0; ; attempt++) {
      const res = await send(`${hosts.pg}${path}`, {
        method: body === undefined ? "GET" : "POST",
        headers: { Authorization: await token(), "Content-Type": "application/json", Accept: "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
      }, path);
      if (res.status === 401 && attempt === 0) {
        await res.body?.cancel();
        cached = null;
        continue;
      }
      if (!res.ok) throw await failure(res, path);
      const text = await res.text();
      return text ? (JSON.parse(text) as Record<string, unknown>) : {};
    }
  }

  const refundReply = (r: { state?: unknown; refundId?: unknown }): GatewayRefund =>
    ({ state: state(r.state), gatewayRefundId: typeof r.refundId === "string" ? r.refundId : null });

  return {
    merchantId: config.merchantId,
    env: config.env,
    async createOrder(o) {
      const made = await call("/checkout/v2/sdk/order", {
        merchantOrderId: o.merchantOrderId,
        amount: o.amountPaise,
        expireAfter: o.expireAfterSeconds,
        metaInfo: { udf1: o.orderId, udf2: o.orderNumber },
        paymentFlow: { type: "PG_CHECKOUT" },
      });
      if (typeof made.orderId !== "string" || typeof made.token !== "string" || !made.token) {
        throw new GatewayError(502, "BAD_REPLY", "create order: no orderId or token");
      }
      const expireAt = Number.isFinite(made.expireAt) ? new Date(made.expireAt as number) : null;
      return { phonepeOrderId: made.orderId, token: made.token, expireAt };
    },
    async orderStatus(merchantOrderId) {
      const s = await call(`/checkout/v2/order/${encodeURIComponent(merchantOrderId)}/status?details=false`);
      const details = (Array.isArray(s.paymentDetails) ? s.paymentDetails : []) as { state?: unknown; transactionId?: unknown }[];
      const paid = details.find((p) => p.state === "COMPLETED") ?? details[0];
      return {
        state: state(s.state),
        amountPaise: Number.isSafeInteger(s.amount) ? (s.amount as number) : null,
        transactionId: typeof paid?.transactionId === "string" ? paid.transactionId : null,
      };
    },
    async refund(r) {
      return refundReply(await call("/payments/v2/refund", {
        merchantRefundId: r.merchantRefundId, originalMerchantOrderId: r.merchantOrderId, amount: r.amountPaise,
      }));
    },
    async refundStatus(merchantRefundId) {
      try {
        return refundReply(await call(`/payments/v2/refund/${encodeURIComponent(merchantRefundId)}/status`));
      } catch (e) {
        // shortcut: PhonePe's exact "unknown refund" reply isn't documented; any 400/404 counts as "never heard of it".
        // Safe either way: a resend reuses the same merchantRefundId, which PhonePe refuses to pay twice.
        if (e instanceof GatewayError && (e.status === 400 || e.status === 404)) return null;
        throw e;
      }
    },
  };
}

// PhonePe's webhook check (its SDKs' validateCallback): the Authorization header is the hex SHA-256 of
// "username:password" from the dashboard's webhook. It is the same on every call and doesn't cover the body, so the
// webhook treats the body as a hint and asks PhonePe's status API for the facts.
export function webhookAuthorized(authorization: string | undefined | null, username: string, password: string): boolean {
  if (!username || !password) return false;
  const expected = Buffer.from(createHash("sha256").update(`${username}:${password}`).digest("hex"));
  const sent = Buffer.from(authorization ?? "");
  return sent.length === expected.length && timingSafeEqual(sent, expected);
}
