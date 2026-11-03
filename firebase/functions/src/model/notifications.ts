import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Owner: engineer D. docs/FIREBASE.md §3, §6. Id: <sourceId>_<eventIndex>_<kind>_<recipient>, written with create().

/** users/{uid}/notifications/{id} (S; the owner may set readAt only) */
export interface NotificationDoc {
  kind: string;
  title: string; // ≤ 80
  body: string; // ≤ 300
  link: string; // an app route (appRoute rule), never a URL
  orderId?: string;
  repairId?: string;
  imagePath?: string;
  readAt: Timestamp | null;
  createdAt: Timestamp;
  expireAt: Timestamp; // 90 days
}

export const retention: Record<string, Retention> = {
  "users/*/notifications": { kind: "ttl", field: "expireAt", days: 90 },
};
