import { safeEqual } from "../_shared/crypto.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

/** The Firebase service account key (Firebase console > Project settings > Service accounts > Generate new key). */
type ServiceAccount = { project_id: string; client_email: string; private_key: string; token_uri?: string };

export interface PushDeps {
  secret?: string; // PUSH_SECRET: the database trigger sends it in x-push-secret
  serviceAccount?: string; // FCM_SERVICE_ACCOUNT, the key's JSON; unset = push is off
  fetch: typeof fetch;
  forget: (tokens: string[]) => Promise<void>; // phones FCM no longer knows (app uninstalled, signed out)
  now?: () => number;
}

const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const encoder = new TextEncoder();
const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/** RS256 JWT for Google's OAuth token endpoint, signed with the service account's PKCS#8 key. */
export async function signJwt(claims: Record<string, unknown>, privateKeyPem: string): Promise<string> {
  const der = Uint8Array.from(atob(privateKeyPem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const part = (v: unknown) => b64url(encoder.encode(JSON.stringify(v)));
  const head = `${part({ alg: "RS256", typ: "JWT" })}.${part(claims)}`;
  return `${head}.${b64url(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(head))))}`;
}

/**
 * One notification row (private.push_notification, via pg_net) to each of its user's phones, as FCM HTTP v1
 * messages: the system tray shows title and body, and the app opens `data.link` on tap. Without
 * FCM_SERVICE_ACCOUNT it sends nothing and says so in the log. pg_net ignores the reply, so failures are logged.
 */
export function sendPushHandler(deps: PushDeps) {
  const now = deps.now ?? Date.now;
  let access: { token: string; until: number } | null = null; // Google access tokens last an hour

  async function accessToken(sa: ServiceAccount): Promise<string> {
    if (access && access.until > now() + 60_000) return access.token;
    const iat = Math.floor(now() / 1000);
    const url = sa.token_uri ?? GOOGLE_TOKEN_URL;
    const assertion = await signJwt({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: url,
      iat,
      exp: iat + 3600,
    }, sa.private_key);
    const res = await deps.fetch(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) throw new Error(`Google token ${res.status}: ${await res.text()}`);
    const out = await res.json() as { access_token: string; expires_in: number };
    access = { token: out.access_token, until: now() + out.expires_in * 1000 };
    return access.token;
  }

  return handler(async (req) => {
    if (!deps.secret || !safeEqual(req.headers.get("x-push-secret") ?? "", deps.secret)) {
      throw new HttpError(401, "UNAUTHORIZED", "Bad push secret.");
    }
    if (!deps.serviceAccount) {
      console.log("send-push: FCM_SERVICE_ACCOUNT is not set, so phone notifications are off. Nothing sent.");
      return json({ sent: 0, off: true });
    }
    const body = await readJson(req);
    const { title, body: text, link, kind, id, tokens } = body;
    if (
      typeof title !== "string" || typeof text !== "string" || !Array.isArray(tokens) || tokens.length > 20 ||
      tokens.some((t) => typeof t !== "string" || !/^[A-Za-z0-9_:-]{20,1000}$/.test(t))
    ) {
      throw new HttpError(400, "BAD_REQUEST", "Need title, body and up to 20 tokens.");
    }
    const sa = JSON.parse(deps.serviceAccount) as ServiceAccount;
    const bearer = await accessToken(sa);
    const dead: string[] = [];
    let sent = 0;
    await Promise.all((tokens as string[]).map(async (token) => {
      const res = await deps.fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body: text },
            data: { link: typeof link === "string" ? link : "", kind: String(kind ?? ""), id: String(id ?? "") },
            android: { priority: "high" },
          },
        }),
        signal: AbortSignal.timeout(10_000),
      }).catch((e) => (console.error("send-push:", e), null));
      if (res?.ok) return void sent++;
      if (res?.status === 404) return void dead.push(token); // UNREGISTERED: that install is gone
      if (res) console.error(`send-push: FCM ${res.status}: ${await res.text()}`);
    }));
    if (dead.length) await deps.forget(dead);
    return json({ sent, failed: tokens.length - sent - dead.length, removed: dead.length });
  });
}
