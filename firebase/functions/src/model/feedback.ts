import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Owner: engineer D. docs/FIREBASE.md §3. Id: order_{orderId} / repair_{repairId} (one rating each) / auto.

export type FeedbackKind = "general" | "order" | "repair" | "product" | "bug";

/** feedback/{id} (S; staff update status/adminNote under Rules) */
export interface FeedbackDoc {
  uid: string | null;
  kind: FeedbackKind;
  rating?: number; // 1..5
  message: string; // ≤ 1000
  orderId?: string;
  repairId?: string;
  productId?: string;
  screen?: string;
  appVersion?: string;
  status: "new" | "seen" | "resolved";
  adminNote?: string; // ≤ 500
  createdAt: Timestamp;
  updatedAt: Timestamp;
  purgeAt: Timestamp; // 2 years
}

export const retention: Record<string, Retention> = {
  feedback: { kind: "ttl", field: "purgeAt", days: 2 * 366 },
};
