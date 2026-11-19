import { createHash } from "node:crypto";
import type { Firestore } from "firebase-admin/firestore";
import type { InstagramPost, SocialPostDoc } from "../model/social.js";
import { log } from "../shared/log.js";
import { type Json, MetaError, type MetaClient } from "./meta.js";

// The social flows (docs/SOCIAL.md). Pure apart from what Deps hands in, so unit tests run them on an in-memory
// Firestore and a fake Meta.

const DAY_MS = 86_400_000;
/** Weekly: past Meta's 24-hour minimum age, far inside the token's 60-day life. */
export const REFRESH_EVERY_MS = 7 * DAY_MS;
export const MAX_ATTEMPTS = 3;
/** A claim older than this belongs to a run that died (functions time out after 120 s). */
export const LEASE_MS = 10 * 60_000;

export type Deps = {
  db: Firestore;
  meta: MetaClient;
  secretToken: string; // INSTAGRAM_TOKEN
  pageId: string;
  pageToken: string;
  imageUrl: (imagePath: string) => Promise<string>; // a public download URL of product-images/{imagePath}
  now: () => Date;
};

/** A Firestore Timestamp (or a Date, in tests) in ms. */
const ms = (t: unknown): number => (t instanceof Date ? t.getTime() : (t as { toMillis?: () => number } | null)?.toMillis?.() ?? NaN);
const TYPES = new Set(["IMAGE", "VIDEO", "CAROUSEL_ALBUM"]);

/** Meta's media list as social/instagram posts; items with nothing to show are dropped. */
export function toPosts(items: Json[]): (Omit<InstagramPost, "takenAt"> & { takenAt: Date })[] {
  return items.flatMap((m) => {
    const type = m.media_type;
    const thumb = type === "VIDEO" ? m.thumbnail_url : m.media_url;
    const takenAt = new Date(typeof m.timestamp === "string" ? m.timestamp : NaN);
    if (typeof m.id !== "string" || typeof type !== "string" || !TYPES.has(type) || typeof thumb !== "string"
      || typeof m.permalink !== "string" || Number.isNaN(takenAt.getTime())) return [];
    return [{
      id: m.id, mediaUrl: typeof m.media_url === "string" ? m.media_url : null, thumbUrl: thumb, permalink: m.permalink,
      caption: Array.from(typeof m.caption === "string" ? m.caption.trim() : "").slice(0, 200).join(""), // whole emoji
      mediaType: type as InstagramPost["mediaType"], takenAt,
    }];
  }).slice(0, 12);
}

export const refreshDue = (refreshedAt: unknown, now: Date): boolean => !(now.getTime() - ms(refreshedAt) < REFRESH_EVERY_MS);

/** The newest Instagram token: the refreshed one in private/instagramToken, unless INSTAGRAM_TOKEN was set again. */
async function instagramToken(d: Deps) {
  const secretHash = createHash("sha256").update(d.secretToken).digest("hex").slice(0, 16);
  const saved = (await d.db.doc("private/instagramToken").get()).data();
  const own = saved?.secretHash === secretHash && typeof saved.token === "string" ? saved : undefined;
  return { token: (own?.token as string | undefined) ?? d.secretToken, refreshedAt: own?.refreshedAt as unknown, secretHash };
}

/** Hourly: refresh the token when due, then write the latest 12 posts to social/instagram. */
export async function syncInstagram(d: Deps): Promise<number> {
  const now = d.now();
  const saved = await instagramToken(d);
  let token = saved.token;
  if (refreshDue(saved.refreshedAt, now)) {
    try {
      const r = await d.meta.refresh(token);
      token = r.token;
      await d.db.doc("private/instagramToken").set({ token, refreshedAt: now, expiresAt: new Date(now.getTime() + r.expiresIn * 1000), secretHash: saved.secretHash });
    } catch (e) {
      // A token under 24 hours old can't be refreshed yet: keep using it and try again next hour.
      log.warn("instagram token refresh failed", { status: e instanceof MetaError ? e.status : null, error: e });
    }
  }
  const posts = toPosts(await d.meta.media(token));
  await d.db.doc("social/instagram").set({ posts, updatedAt: now });
  return posts.length;
}

type Banner = { title?: unknown; subtitle?: unknown; imagePath?: unknown; socialImagePath?: unknown; isActive?: unknown; startsAt?: unknown; endsAt?: unknown };

export const captionOf = (b: Banner): string =>
  [b.title, b.subtitle, "Shop on the Shyam Mobiles app"].map((s) => (typeof s === "string" ? s.trim() : "")).filter(Boolean).join(" · ");

const live = (b: Banner, now: number) =>
  b.isActive === true && ms(b.startsAt) <= now && (b.endsAt == null || ms(b.endsAt) > now);

export type Outcome = "off" | "not live" | "not jpeg" | "skip" | "done" | "failed";

/**
 * Posts banners/{id} (staff banners and savePromotion's promotion banners) once to the Page and to Instagram, when
 * settings/social.autoPost is on and the banner is live with a photo. socialPosts/{id} is the claim: done is never
 * posted again, a network that already has an id is skipped, and a failure is retried by socialHourly up to 3 attempts.
 */
export async function autoPost(d: Deps, id: string): Promise<Outcome> {
  const now = d.now();
  const [settings, snap] = await Promise.all([d.db.doc("settings/social").get(), d.db.doc(`banners/${id}`).get()]);
  if (settings.data()?.autoPost !== true) return "off";
  const banner = snap.data() as Banner | undefined;
  if (!banner || typeof banner.imagePath !== "string" || !live(banner, now.getTime())) return "not live";
  // Instagram takes JPEG only and Facebook doesn't list WebP: the app stores a JPEG copy of the WebP photo as socialImagePath.
  const photo = typeof banner.socialImagePath === "string" ? banner.socialImagePath : banner.imagePath;
  if (!/\.jpe?g$/i.test(photo)) return "not jpeg";

  const ref = d.db.doc(`socialPosts/${id}`);
  const rec = await d.db.runTransaction(async (tx) => {
    const r = (await tx.get(ref)).data() as SocialPostDoc | undefined;
    if (r && (r.status === "done" || r.attempts >= MAX_ATTEMPTS)) return null;
    if (r?.status === "posting" && now.getTime() - ms(r.claimedAt) < LEASE_MS) return null; // another run has it
    const next = { ...r, status: "posting" as const, attempts: (r?.attempts ?? 0) + 1, claimedAt: now, updatedAt: now };
    tx.set(ref, next);
    return next;
  });
  if (!rec) return "skip";

  try {
    const url = await d.imageUrl(photo);
    const caption = captionOf(banner);
    if (!rec.facebookPostId) {
      rec.facebookPostId = await d.meta.facebookPhoto(d.pageId, d.pageToken, url, caption);
      await ref.update({ facebookPostId: rec.facebookPostId }); // kept even if Instagram fails
    }
    if (!rec.instagramMediaId) {
      rec.instagramMediaId = await d.meta.instagramPhoto((await instagramToken(d)).token, url, caption);
    }
    await ref.update({ status: "done", instagramMediaId: rec.instagramMediaId, lastError: null, updatedAt: d.now() });
    return "done";
  } catch (e) {
    const lastError = e instanceof MetaError ? `${e.status}: ${e.message}` : e instanceof Error ? e.name : "error";
    log.warn("social post failed", { bannerId: id, attempt: rec.attempts, lastError });
    await ref.update({ status: "failed", lastError, updatedAt: d.now() });
    return "failed";
  }
}

/** Hourly: banners that went live on their own schedule, and failed posts with attempts left. */
export async function postLiveBanners(d: Deps): Promise<Outcome[]> {
  if ((await d.db.doc("settings/social").get()).data()?.autoPost !== true) return [];
  const live = await d.db.collection("banners").where("isActive", "==", true).get();
  const out: Outcome[] = [];
  for (const b of live.docs) out.push(await autoPost(d, b.id));
  return out;
}
