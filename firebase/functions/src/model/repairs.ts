import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Owner: engineer D. docs/FIREBASE.md §3.

export type RepairStatus = "requested" | "confirmed" | "in_progress" | "ready" | "completed" | "cancelled";
export type QuoteStatus = "none" | "pending" | "approved" | "declined";

/** repairs/{autoId} (S) */
export interface RepairDoc {
  number: string; // RP100001
  uid: string | null;
  deviceBrand: string;
  deviceModel: string;
  issue: "screen" | "battery" | "charging" | "camera" | "audio" | "water_damage" | "software" | "other";
  description: string;
  preferredDate: string; // 'YYYY-MM-DD' IST, today..+30
  slot: "morning" | "afternoon" | "evening";
  contactPhone: string;
  status: RepairStatus;
  quote: { paise: number | null; status: QuoteStatus; decidedAt?: Timestamp };
  events: { status: RepairStatus; quoteStatus?: QuoteStatus; quotePaise?: number; note?: string; by: "customer" | "staff" | "system"; byUid?: string; at: Timestamp }[];
  createdAt: Timestamp;
  updatedAt: Timestamp;
  purgeAt: Timestamp; // 3 years
}

export const retention: Record<string, Retention> = {
  repairs: { kind: "ttl", field: "purgeAt", days: 3 * 366 },
};
