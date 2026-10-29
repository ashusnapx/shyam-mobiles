import { env, HttpError } from "./http.ts";

// Razorpay REST call: basic auth, JSON, 10 s timeout. Any failure -> 502 GATEWAY_ERROR.
export async function razorpay<T = Record<string, unknown>>(path: string, body?: unknown): Promise<T> {
  const auth = btoa(`${env("RAZORPAY_KEY_ID")}:${env("RAZORPAY_KEY_SECRET")}`);
  let res: Response;
  try {
    res = await fetch(`https://api.razorpay.com/v1${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (e) {
    console.error(`razorpay ${path}:`, e);
    throw new HttpError(502, "GATEWAY_ERROR", "Payment service is unreachable. Try again.");
  }
  if (!res.ok) {
    console.error(`razorpay ${path}: ${res.status} ${await res.text()}`);
    throw new HttpError(502, "GATEWAY_ERROR", "Payment service error. Try again.");
  }
  return await res.json();
}
