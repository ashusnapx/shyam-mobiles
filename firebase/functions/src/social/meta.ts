// Meta's Graph APIs (docs/SOCIAL.md): the Instagram API with Instagram Login on graph.instagram.com, and Facebook Pages
// on graph.facebook.com. Pass a fake fetch in tests. Tokens travel only in the query or form body of a request to Meta;
// errors carry Meta's message and HTTP status, never a URL, so no token reaches a log.

export const VERSION = "v27.0"; // Graph API v27.0, 4 Nov 2026 (developers.facebook.com/docs/graph-api/changelog)
const IG = "https://graph.instagram.com";
const FB = "https://graph.facebook.com";
export const FEED_FIELDS = "id,media_type,media_url,thumbnail_url,permalink,caption,timestamp";

export class MetaError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "MetaError";
  }
}

export type Json = Record<string, unknown>;
const str = (v: unknown, what: string): string => {
  if (typeof v === "string" && v) return v;
  throw new MetaError(200, `unexpected reply: no ${what}`);
};

export function metaClient(fetcher: typeof fetch = fetch) {
  async function call(url: string, form?: Record<string, string>): Promise<Json> {
    let res: Response;
    try {
      res = await fetcher(url, { method: form ? "POST" : "GET", body: form ? new URLSearchParams(form) : undefined, signal: AbortSignal.timeout(20_000) });
    } catch (e) {
      throw new MetaError(0, `unreachable (${e instanceof Error ? e.name : "error"})`);
    }
    const body = (await res.json().catch(() => null)) as (Json & { error?: { message?: unknown } }) | null;
    if (!res.ok || !body || body.error) {
      const m = body?.error?.message;
      throw new MetaError(res.status, typeof m === "string" ? m.slice(0, 300) : `HTTP ${res.status}`);
    }
    return body;
  }
  const get = (url: string, q: Record<string, string>) => call(`${url}?${new URLSearchParams(q).toString()}`);

  return {
    /** The account's latest posts, newest first. */
    async media(token: string, limit = 12): Promise<Json[]> {
      const r = await get(`${IG}/${VERSION}/me/media`, { fields: FEED_FIELDS, limit: String(limit), access_token: token });
      return Array.isArray(r.data) ? (r.data as Json[]) : [];
    },

    /** A long-lived token (≥ 24 h old, not expired) for a fresh one good for 60 more days. */
    async refresh(token: string): Promise<{ token: string; expiresIn: number }> {
      const r = await get(`${IG}/refresh_access_token`, { grant_type: "ig_refresh_token", access_token: token });
      return { token: str(r.access_token, "access_token"), expiresIn: typeof r.expires_in === "number" ? r.expires_in : 60 * 86_400 };
    },

    /** Posts one JPEG (a public URL) to the account: a container, then media_publish. Returns the media id. */
    async instagramPhoto(token: string, imageUrl: string, caption: string): Promise<string> {
      const me = await get(`${IG}/${VERSION}/me`, { fields: "user_id", access_token: token });
      // The docs show user_id both at the top level and inside data[0].
      const igId = str(me.user_id ?? (me.data as Json[] | undefined)?.[0]?.user_id, "user_id");
      const box = await call(`${IG}/${VERSION}/${igId}/media`, { image_url: imageUrl, caption, access_token: token });
      const done = await call(`${IG}/${VERSION}/${igId}/media_publish`, { creation_id: str(box.id, "container id"), access_token: token });
      return str(done.id, "media id");
    },

    /** Posts one photo (a public URL) to the Page with a Page access token. Returns the post id. */
    async facebookPhoto(pageId: string, pageToken: string, imageUrl: string, caption: string): Promise<string> {
      const r = await call(`${FB}/${VERSION}/${pageId}/photos`, { url: imageUrl, caption, access_token: pageToken });
      return str(r.post_id ?? r.id, "post id");
    },
  };
}

export type MetaClient = ReturnType<typeof metaClient>;
