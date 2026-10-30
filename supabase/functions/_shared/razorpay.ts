import { env, HttpError } from "./http.ts";

// Razorpay answered with an error. Callers that show staff Razorpay's own reason (refunds, payment links) read
// `gatewayStatus` and `description`; to everyone else it is the same 502 GATEWAY_ERROR.
export class RazorpayError extends HttpError {
  gatewayStatus: number;
  description: string;
  constructor(gatewayStatus: number, description: string) {
    super(502, "GATEWAY_ERROR", "Payment service error. Try again.");
    this.gatewayStatus = gatewayStatus;
    this.description = description;
  }
}

type Options = {
  method?: string;
  headers?: Record<string, string>;
  keyOnly?: boolean; // the public methods endpoint takes the key id alone, like Checkout does
};

// Razorpay REST call: basic auth, JSON, 10 s timeout. Unreachable -> 502 GATEWAY_ERROR; an error reply -> RazorpayError.
export async function razorpay<T = Record<string, unknown>>(path: string, body?: unknown, opts: Options = {}): Promise<T> {
  const auth = btoa(`${env("RAZORPAY_KEY_ID")}:${opts.keyOnly ? "" : env("RAZORPAY_KEY_SECRET")}`);
  let res: Response;
  try {
    res = await fetch(`https://api.razorpay.com/v1${path}`, {
      method: opts.method ?? (body === undefined ? "GET" : "POST"),
      headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json", ...opts.headers },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (e) {
    console.error(`razorpay ${path}:`, e);
    throw new HttpError(502, "GATEWAY_ERROR", "Payment service is unreachable. Try again.");
  }
  const text = await res.text();
  if (!res.ok) {
    console.error(`razorpay ${path}: ${res.status} ${text}`);
    let description = "";
    try {
      const body = JSON.parse(text);
      description = String(body?.error?.description ?? body?.message ?? "");
    } catch { /* not JSON */ }
    throw new RazorpayError(res.status, description);
  }
  return (text ? JSON.parse(text) : {}) as T;
}
