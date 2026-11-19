import { getDownloadURL, getStorage } from "firebase-admin/storage";
import { defineSecret, defineString } from "firebase-functions/params";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db } from "../shared/db.js";
import { log } from "../shared/log.js";
import { BACKGROUND } from "../shared/options.js";
import { autoPost, type Deps, postLiveBanners, syncInstagram } from "./flows.js";
import { metaClient } from "./meta.js";

// The shop's Instagram feed and offer auto-posting (docs/SOCIAL.md). The secrets are bound only to these two functions.
const INSTAGRAM_TOKEN = defineSecret("INSTAGRAM_TOKEN"); // the first long-lived token; refreshed ones go to private/instagramToken
const FB_PAGE_TOKEN = defineSecret("FB_PAGE_TOKEN");
const FB_PAGE_ID = defineString("FB_PAGE_ID", { default: "me" }); // "me" with a Page token is that Page; the id pins it
const secrets = [INSTAGRAM_TOKEN, FB_PAGE_TOKEN];

const deps = (): Deps => ({
  db: db(), // initialises the app getStorage() uses
  meta: metaClient(),
  secretToken: INSTAGRAM_TOKEN.value(),
  pageId: FB_PAGE_ID.value(),
  pageToken: FB_PAGE_TOKEN.value(),
  imageUrl: (imagePath) => getDownloadURL(getStorage().bucket().file(`product-images/${imagePath}`)),
  now: () => new Date(),
});

export const socialHourly = onSchedule({ schedule: "every 60 minutes", timeZone: "Asia/Kolkata", ...BACKGROUND, secrets }, async () => {
  const d = deps();
  const [feed, posts] = await Promise.allSettled([syncInstagram(d), postLiveBanners(d)]);
  if (feed.status === "rejected") log.error("instagram feed sync failed", { error: feed.reason });
  if (posts.status === "rejected") log.error("social auto-post sweep failed", { error: posts.reason });
});

export const autoPostBanner = onDocumentWritten({ document: "banners/{id}", ...BACKGROUND, secrets, retry: false }, async (event) => {
  if (event.data?.after.data()?.isActive !== true) return; // deleted or hidden: nothing to post
  const outcome = await autoPost(deps(), event.params.id);
  log.info("social auto-post", { bannerId: event.params.id, outcome });
});
