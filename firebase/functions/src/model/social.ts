import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// The social domain (docs/SOCIAL.md): the shop's Instagram feed in the app, and offers posted to Facebook and Instagram.

/** One post as the app shows it. thumbUrl is the video's thumbnail, else the image itself. */
export interface InstagramPost {
  id: string;
  mediaUrl: string | null; // Instagram omits it for some videos (licensed audio)
  thumbUrl: string;
  permalink: string;
  caption: string; // ≤ 200 characters
  mediaType: "IMAGE" | "VIDEO" | "CAROUSEL_ALBUM";
  takenAt: Timestamp;
}

/** social/instagram (S, public read): the shop's latest 12 posts, rewritten every hour by socialHourly. */
export interface InstagramFeedDoc {
  posts: InstagramPost[];
  updatedAt: Timestamp;
}

/** private/instagramToken (S, no client access, not even staff): the refreshed long-lived token. secretHash names the
 * INSTAGRAM_TOKEN secret it grew from, so setting a new secret replaces it. */
export interface InstagramTokenDoc {
  token: string;
  refreshedAt: Timestamp;
  expiresAt: Timestamp;
  secretHash: string;
}

/** settings/social (St, staff read and write): autoPost is off until the owner turns it on. */
export interface SocialSettingsDoc {
  autoPost: boolean;
  updatedAt: Timestamp;
}

/** socialPosts/{bannerId} (S): one banner's posts. A network's id, once set, is never posted again. */
export interface SocialPostDoc {
  status: "posting" | "done" | "failed";
  attempts: number; // ≤ 3
  facebookPostId?: string;
  instagramMediaId?: string;
  lastError?: string | null; // Meta's status and message, never a token
  claimedAt: Timestamp;
  updatedAt: Timestamp;
}

export const retention: Record<string, Retention> = {
  social: { kind: "shop" },
  private: { kind: "shop" },
  socialPosts: { kind: "shop" },
};
