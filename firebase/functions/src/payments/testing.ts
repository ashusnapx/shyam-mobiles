// Test helpers: a recording fetch with canned PhonePe replies.
import { type PhonePeConfig } from "./phonepe.js";

export type Call = { method: string; url: string; headers: Headers; body: unknown };

export const CONFIG: PhonePeConfig = {
  env: "sandbox", clientId: "pp_client_fake", clientSecret: "pp_secret_fake", clientVersion: "1", merchantId: "PPFAKEMERCHANT",
};
export const SANDBOX = "https://api-preprod.phonepe.com/apis/pg-sandbox";
export const TOKEN_URL = `${SANDBOX}/v1/oauth/token`;

export function fakeFetch(reply: (call: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fetcher = (async (input: string | URL | Request, init?: RequestInit) => {
    const call = {
      method: init?.method ?? "GET",
      url: String(input),
      headers: new Headers(init?.headers),
      body: init?.body instanceof URLSearchParams ? Object.fromEntries(init.body) : init?.body ? JSON.parse(String(init.body)) : undefined,
    };
    calls.push(call);
    return await reply(call);
  }) as typeof fetch;
  return { calls, fetcher, api: () => calls.filter((c) => c.url !== TOKEN_URL) };
}

export const ok = (body: unknown) => Response.json(body);
export const token = (accessToken = "pp_access_fake") => {
  const now = Math.floor(Date.now() / 1000);
  return ok({ access_token: accessToken, token_type: "O-Bearer", issued_at: now, expires_at: now + 3600 });
};
export const refused = (status: number, code: string, message: string) => Response.json({ code, message, data: {} }, { status });
