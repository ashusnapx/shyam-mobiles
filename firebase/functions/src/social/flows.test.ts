import { describe, expect, test } from "vitest";
import { fakeFetch, fakeFirestore } from "../payments/testing.js";
import { autoPost, captionOf, type Deps, LEASE_MS, postLiveBanners, syncInstagram, toPosts } from "./flows.js";
import { type MetaClient, metaClient, MetaError } from "./meta.js";

const DAY = 86_400_000;
const T0 = new Date("2026-11-19T06:00:00Z");

/** An in-memory Meta: `calls` records "method arg"; `fail(method)` returning an error makes that call refuse. */
function fakeMeta() {
  const m = {
    calls: [] as string[],
    media: [] as Record<string, unknown>[],
    fail: null as null | ((method: string) => MetaError | null),
  };
  const check = (method: string, arg: string) => {
    m.calls.push(`${method} ${arg}`);
    const e = m.fail?.(method);
    if (e) throw e;
  };
  const client: MetaClient = {
    async media(token) { check("media", token); return Promise.resolve(m.media); },
    async refresh(token) { check("refresh", token); return Promise.resolve({ token: `${token}+r`, expiresIn: 60 * 86_400 }); },
    async instagramPhoto(token, url, caption) { check("instagramPhoto", `${token} ${url} ${caption}`); return Promise.resolve("ig1"); },
    async facebookPhoto(pageId, pageToken, url) { check("facebookPhoto", `${pageId} ${pageToken} ${url}`); return Promise.resolve("fb1"); },
  };
  return Object.assign(m, { client });
}

function setup(seed: Record<string, Record<string, unknown>> = {}, now = T0) {
  const { db, firestore } = fakeFirestore(seed);
  const meta = fakeMeta();
  const clock = { now };
  const d: Deps = {
    db: firestore, meta: meta.client, secretToken: "IGSECRET", pageId: "PAGE1", pageToken: "PAGETOKEN",
    imageUrl: (p) => Promise.resolve(`https://img.test/${p}`), now: () => clock.now,
  };
  return { db, meta, clock, d, doc: (path: string) => db.docs.get(path) };
}

const banner = (over: Record<string, unknown> = {}) => ({
  title: "Diwali sale", subtitle: "10% off all phones", ctaLabel: "Shop", link: "/offers", imagePath: "banners/diwali.jpg",
  tone: 0, sort: 0, isActive: true, startsAt: new Date(T0.getTime() - DAY), endsAt: null, ...over,
});
const ON = { "settings/social": { autoPost: true } };

describe("Instagram feed", () => {
  test("maps media to posts: video thumbnails, 200-character captions, bad items dropped", () => {
    const long = `${"a".repeat(199)}😀😀`;
    const posts = toPosts([
      { id: "1", media_type: "IMAGE", media_url: "https://cdn/1.jpg", permalink: "https://ig/p/1", caption: "  Hi  ", timestamp: "2026-11-01T10:00:00+0000" },
      { id: "2", media_type: "VIDEO", media_url: "https://cdn/2.mp4", thumbnail_url: "https://cdn/2.jpg", permalink: "https://ig/p/2", caption: long, timestamp: "2026-11-02T10:00:00+0000" },
      { id: "3", media_type: "VIDEO", thumbnail_url: "https://cdn/3.jpg", permalink: "https://ig/p/3", timestamp: "2026-11-03T10:00:00+0000" },
      { id: "4", media_type: "IMAGE", permalink: "https://ig/p/4", timestamp: "2026-11-04T10:00:00+0000" }, // no media_url
      { id: "5", media_type: "STORY", media_url: "https://cdn/5.jpg", permalink: "https://ig/p/5", timestamp: "2026-11-05T10:00:00+0000" },
    ]);
    expect(posts.map((p) => p.id)).toEqual(["1", "2", "3"]);
    expect(posts[0]).toEqual({ id: "1", mediaUrl: "https://cdn/1.jpg", thumbUrl: "https://cdn/1.jpg", permalink: "https://ig/p/1", caption: "Hi", mediaType: "IMAGE", takenAt: new Date("2026-11-01T10:00:00Z") });
    expect(posts[1]!.thumbUrl).toBe("https://cdn/2.jpg");
    expect(Array.from(posts[1]!.caption)).toHaveLength(200);
    expect(posts[1]!.caption.endsWith("😀")).toBe(true);
    expect(posts[2]).toMatchObject({ mediaUrl: null, caption: "" });
    expect(toPosts(Array.from({ length: 20 }, (_, i) => ({ id: `${i}`, media_type: "IMAGE", media_url: "u", permalink: "p", timestamp: "2026-11-01T10:00:00+0000" })))).toHaveLength(12);
  });

  test("first run refreshes the secret's token, stores it, and writes social/instagram", async () => {
    const s = setup();
    s.meta.media = [{ id: "1", media_type: "IMAGE", media_url: "u", permalink: "p", timestamp: "2026-11-01T10:00:00+0000" }];
    expect(await syncInstagram(s.d)).toBe(1);
    expect(s.meta.calls).toEqual(["refresh IGSECRET", "media IGSECRET+r"]);
    expect(s.doc("private/instagramToken")).toMatchObject({ token: "IGSECRET+r", refreshedAt: T0, expiresAt: new Date(T0.getTime() + 60 * DAY) });
    expect(s.doc("social/instagram")).toMatchObject({ updatedAt: T0, posts: [{ id: "1", thumbUrl: "u" }] });
  });

  test("refreshes weekly, uses the stored token in between, and a new secret replaces the stored one", async () => {
    const s = setup();
    await syncInstagram(s.d);
    s.clock.now = new Date(T0.getTime() + 6 * DAY);
    await syncInstagram(s.d);
    s.clock.now = new Date(T0.getTime() + 7 * DAY);
    await syncInstagram(s.d);
    expect(s.meta.calls).toEqual(["refresh IGSECRET", "media IGSECRET+r", "media IGSECRET+r", "refresh IGSECRET+r", "media IGSECRET+r+r"]);
    s.meta.calls.length = 0;
    s.d.secretToken = "NEWSECRET";
    await syncInstagram(s.d);
    expect(s.meta.calls).toEqual(["refresh NEWSECRET", "media NEWSECRET+r"]);
  });

  test("a refused refresh (token under 24 hours old) still syncs with the current token", async () => {
    const s = setup();
    s.meta.fail = (m) => (m === "refresh" ? new MetaError(400, "token too new") : null);
    await syncInstagram(s.d);
    expect(s.meta.calls).toEqual(["refresh IGSECRET", "media IGSECRET"]);
    expect(s.doc("private/instagramToken")).toBeUndefined();
    expect(s.doc("social/instagram")).toBeDefined();
  });
});

describe("auto-post", () => {
  test("off unless settings/social.autoPost is true", async () => {
    for (const seed of [{}, { "settings/social": { autoPost: false } }] as Record<string, Record<string, unknown>>[]) {
      const s = setup({ ...seed, "banners/b1": banner() });
      expect(await autoPost(s.d, "b1")).toBe("off");
      expect(await postLiveBanners(s.d)).toEqual([]);
      expect(s.meta.calls).toEqual([]);
      expect(s.doc("socialPosts/b1")).toBeUndefined();
    }
  });

  test("posts a live banner once to the Page and Instagram, with the caption", async () => {
    const s = setup({ ...ON, "banners/b1": banner() });
    expect(captionOf(banner())).toBe("Diwali sale · 10% off all phones · Shop on the Shyam Mobiles app");
    expect(captionOf(banner({ subtitle: "" }))).toBe("Diwali sale · Shop on the Shyam Mobiles app");
    expect(await autoPost(s.d, "b1")).toBe("done");
    expect(await autoPost(s.d, "b1")).toBe("skip");
    expect(await postLiveBanners(s.d)).toEqual(["skip"]);
    expect(s.meta.calls).toEqual([
      "facebookPhoto PAGE1 PAGETOKEN https://img.test/banners/diwali.jpg",
      "instagramPhoto IGSECRET https://img.test/banners/diwali.jpg Diwali sale · 10% off all phones · Shop on the Shyam Mobiles app",
    ]);
    expect(s.doc("socialPosts/b1")).toMatchObject({ status: "done", attempts: 1, facebookPostId: "fb1", instagramMediaId: "ig1", lastError: null });
  });

  test("two runs at once post once", async () => {
    const s = setup({ ...ON, "banners/b1": banner() });
    expect((await Promise.all([autoPost(s.d, "b1"), autoPost(s.d, "b1")])).sort()).toEqual(["done", "skip"]);
    expect(s.meta.calls.filter((c) => c.startsWith("facebookPhoto"))).toHaveLength(1);
  });

  test("a retry posts only the network that failed", async () => {
    const s = setup({ ...ON, "banners/b1": banner() });
    s.meta.fail = (m) => (m === "instagramPhoto" ? new MetaError(400, "Only photo or video can be accepted as media type.") : null);
    expect(await autoPost(s.d, "b1")).toBe("failed");
    expect(s.doc("socialPosts/b1")).toMatchObject({ status: "failed", attempts: 1, facebookPostId: "fb1", lastError: "400: Only photo or video can be accepted as media type." });
    s.meta.fail = null;
    expect(await postLiveBanners(s.d)).toEqual(["done"]);
    expect(s.meta.calls.filter((c) => c.startsWith("facebookPhoto"))).toHaveLength(1);
    expect(s.doc("socialPosts/b1")).toMatchObject({ status: "done", attempts: 2, facebookPostId: "fb1", instagramMediaId: "ig1" });
  });

  test("gives up after 3 attempts", async () => {
    const s = setup({ ...ON, "banners/b1": banner() });
    s.meta.fail = () => new MetaError(0, "unreachable (TimeoutError)");
    expect([await autoPost(s.d, "b1"), await autoPost(s.d, "b1"), await autoPost(s.d, "b1"), await autoPost(s.d, "b1")])
      .toEqual(["failed", "failed", "failed", "skip"]);
    expect(s.meta.calls).toHaveLength(3);
    expect(s.doc("socialPosts/b1")).toMatchObject({ status: "failed", attempts: 3 });
  });

  test("a run that died mid-post is taken over only after the lease", async () => {
    const s = setup({ ...ON, "banners/b1": banner(), "socialPosts/b1": { status: "posting", attempts: 1, claimedAt: T0 } });
    expect(await autoPost(s.d, "b1")).toBe("skip");
    s.clock.now = new Date(T0.getTime() + LEASE_MS);
    expect(await autoPost(s.d, "b1")).toBe("done");
    expect(s.doc("socialPosts/b1")).toMatchObject({ attempts: 2 });
  });

  test("waits for a banner to go live, and skips hidden, expired, photo-less and WebP banners", async () => {
    const s = setup({
      ...ON,
      "banners/later": banner({ startsAt: new Date(T0.getTime() + DAY) }),
      "banners/hidden": banner({ isActive: false }),
      "banners/over": banner({ endsAt: new Date(T0.getTime() - 1) }),
      "banners/nophoto": banner({ imagePath: undefined }),
      "banners/webp": banner({ imagePath: "banners/x.webp" }),
    });
    expect(await postLiveBanners(s.d)).toEqual(["not live", "not live", "not live", "not jpeg"]);
    expect(await autoPost(s.d, "hidden")).toBe("not live");
    s.clock.now = new Date(T0.getTime() + DAY);
    expect(await autoPost(s.d, "later")).toBe("done");
    expect(s.meta.calls).toHaveLength(2);
  });
});

describe("auto-post photo", () => {
  test("posts the JPEG copy in socialImagePath; a WebP photo without one is skipped", async () => {
    const s = setup({ ...ON, "banners/b1": banner({ imagePath: "banners/x.webp", socialImagePath: "banners/x.jpg" }), "banners/b2": banner({ imagePath: "banners/y.webp" }) });
    expect(await postLiveBanners(s.d)).toEqual(["done", "not jpeg"]);
    expect(s.meta.calls[0]).toBe("facebookPhoto PAGE1 PAGETOKEN https://img.test/banners/x.jpg");
    expect(s.meta.calls).toHaveLength(2);
  });
});

describe("Meta client", () => {
  test("calls the documented endpoints; tokens never appear in errors", async () => {
    const f = fakeFetch((c) => {
      if (c.url.includes("/me?")) return Response.json({ user_id: "17841" });
      if (c.url.endsWith("/17841/media")) return Response.json({ id: "box1" });
      if (c.url.endsWith("/media_publish")) return Response.json({ id: "ig9" });
      if (c.url.includes("/photos")) return Response.json({ id: "ph1", post_id: "PAGE1_9" });
      if (c.url.includes("refresh_access_token")) return Response.json({ access_token: "NEW", token_type: "bearer", expires_in: 5_183_944 });
      if (c.url.includes("/me/media?")) return Response.json({ data: [{ id: "1" }] });
      return Response.json({ error: { message: "Invalid OAuth access token - Cannot parse access token" } }, { status: 400 });
    });
    const meta = metaClient(f.fetcher);
    expect(await meta.media("TOK")).toEqual([{ id: "1" }]);
    expect(await meta.refresh("TOK")).toEqual({ token: "NEW", expiresIn: 5_183_944 });
    expect(await meta.instagramPhoto("TOK", "https://img/x.jpg", "cap")).toBe("ig9");
    expect(await meta.facebookPhoto("PAGE1", "PTOK", "https://img/x.jpg", "cap")).toBe("PAGE1_9");
    expect(f.calls.map((c) => `${c.method} ${c.url.split("?")[0]!}`)).toEqual([
      "GET https://graph.instagram.com/v27.0/me/media",
      "GET https://graph.instagram.com/refresh_access_token",
      "GET https://graph.instagram.com/v27.0/me",
      "POST https://graph.instagram.com/v27.0/17841/media",
      "POST https://graph.instagram.com/v27.0/17841/media_publish",
      "POST https://graph.facebook.com/v27.0/PAGE1/photos",
    ]);
    expect(new URL(f.calls[0]!.url).searchParams.get("fields")).toBe("id,media_type,media_url,thumbnail_url,permalink,caption,timestamp");
    expect(new URL(f.calls[1]!.url).searchParams.get("grant_type")).toBe("ig_refresh_token");
    expect(f.calls[3]!.body).toEqual({ image_url: "https://img/x.jpg", caption: "cap", access_token: "TOK" });
    expect(f.calls[4]!.body).toEqual({ creation_id: "box1", access_token: "TOK" });
    expect(f.calls[5]!.body).toEqual({ url: "https://img/x.jpg", caption: "cap", access_token: "PTOK" });

    const bad = metaClient(fakeFetch(() => Response.json({ error: { message: "Invalid OAuth access token" } }, { status: 400 })).fetcher);
    const e = await bad.media("SECRET-TOKEN").catch((x: unknown) => x);
    expect(e).toBeInstanceOf(MetaError);
    expect(e).toMatchObject({ status: 400, message: "Invalid OAuth access token" });
    expect(JSON.stringify(e) + String(e)).not.toContain("SECRET-TOKEN");
  });
});
