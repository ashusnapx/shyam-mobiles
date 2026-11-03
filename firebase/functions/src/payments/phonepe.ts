import { createHash, timingSafeEqual } from "node:crypto";

// PhonePe Payment Gateway, PG v2 Standard Checkout (docs/PHONEPE.md). Hosts from PhonePe's own SDKs.
const HOSTS = {
  sandbox: { pg: "https://api-preprod.phonepe.com/apis/pg-sandbox", auth: "https://api-preprod.phonepe.com/apis/pg-sandbox" },
  production: { pg: "https://api.phonepe.com/apis/pg", auth: "https://api.phonepe.com/apis/identity-manager" },
};

export type PhonePeConfig = {
  env: string; // "sandbox" | "production", nothing else, so a typo can't mix test and live traffic
  clientId: string;
  clientSecret: string;
  clientVersion: string;
  merchantId: string; // public: the app's SDK init takes it
};

/** Our error contract: `code` for the app (errors.dart), `message` as short human text, `status` for HTTP. */
export class PaymentError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

// PhonePe answered with an error. Staff-facing callers (refunds) read gatewayStatus / gatewayCode / description.
export class PhonePeError extends PaymentError {
  gatewayStatus: number;
  gatewayCode: string;
  description: string;
  constructor(gatewayStatus: number, gatewayCode: string, description: string) {
    super(502, "GATEWAY_ERROR", "Payment service error. Try again.");
    this.gatewayStatus = gatewayStatus;
    this.gatewayCode = gatewayCode;
    this.description = description;
  }
}

/** Order status reply (GET /checkout/v2/order/{merchantOrderId}/status). */
export type PhonePeOrder = {
  orderId?: string;
  state?: string; // PENDING | COMPLETED | FAILED
  amount?: number;
  errorCode?: string;
  paymentDetails?: { transactionId?: string; state?: string; amount?: number; paymentMode?: string }[];
};

export type PhonePe = {
  config: PhonePeConfig;
  environment: "SANDBOX" | "PRODUCTION"; // the SDK's init value matching these hosts
  call<T = Record<string, unknown>>(path: string, body?: unknown): Promise<T>;
};

// One client per instance: OAuth token cached and renewed halfway through its life (what PhonePe's SDKs do); a 401
// renews it once; 10 s timeouts. Unreachable -> 502 GATEWAY_ERROR; an error reply -> PhonePeError.
export function phonePe(config: PhonePeConfig, fetcher: typeof fetch = fetch): PhonePe {
  if (config.env !== "sandbox" && config.env !== "production") throw new Error("PHONEPE_ENV must be sandbox or production");
  for (const [k, v] of Object.entries(config)) if (!v) throw new Error(`Missing PhonePe setting ${k}`);
  const hosts = HOSTS[config.env];
  let cached: { token: string; renewAt: number } | null = null;

  async function send(url: string, init: RequestInit, what: string): Promise<Response> {
    try {
      return await fetcher(url, { ...init, signal: AbortSignal.timeout(10_000) });
    } catch (e) {
      console.error(`phonepe ${what}:`, e);
      throw new PaymentError(502, "GATEWAY_ERROR", "Payment service is unreachable. Try again.");
    }
  }

  async function failure(res: Response, what: string): Promise<PhonePeError> {
    const text = await res.text();
    console.error(`phonepe ${what}: ${res.status} ${text.slice(0, 500)}`);
    let code = "", description = "";
    try {
      const body = JSON.parse(text);
      code = String(body?.errorCode ?? body?.code ?? "");
      description = String(body?.message ?? "");
    } catch { /* not JSON */ }
    return new PhonePeError(res.status, code, description);
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

  return {
    config,
    environment: config.env === "production" ? "PRODUCTION" : "SANDBOX",
    async call<T>(path: string, body?: unknown): Promise<T> {
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
        return (text ? JSON.parse(text) : {}) as T;
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
