import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Growth (docs/GROWTH.md §2a, b). Reviews are written by saveReview; the stats and the tile index by triggers.

/** reviews/{productId}_{uid} (S; staff set `hidden` under Rules). One per customer per product: saving again replaces it. */
export interface ReviewDoc {
  productId: string;
  uid: string;
  name: string; // "Ravi K.": first name and last initial, taken from the profile when saved
  rating: number; // 1..5
  text: string; // ≤ 1000
  photos: string[]; // ≤ 3 Storage keys under review-photos/{uid}/
  orderId: string; // the delivered order that makes it a verified purchase
  hidden: boolean; // staff: abuse, personal data or spam; never for being negative
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** productStats/{productId} (S, public read): what the product page shows. */
export interface ProductStatsDoc {
  ratingCount: number; // visible reviews
  ratingSum: number;
  stars: number[]; // [1★ count, …, 5★ count]
  sold?: Record<string, number>; // { 'YYYY-MM-DD' IST: units on orders that became paid or delivered that day }, last 7 days kept
  with?: Record<string, number>; // { productId: orders that held both }
  updatedAt: Timestamp;
}

/** reviewIndex/public (S, public read): { cards: { [productId]: { a: average × 10, n: count } } } for tiles. */
export interface ReviewIndexDoc {
  cards: Record<string, { a: number; n: number }>;
  updatedAt: Timestamp;
}

/** statsEvents/{orderId} (S): what an order added to productStats, so it is added once and taken back once. */
export interface StatsEventDoc {
  day: string; // the IST day it was counted on
  units: Record<string, number>; // productId → units
  reversed: boolean; // taken back after a cancel or refund
  createdAt: Timestamp;
  expireAt: Timestamp; // 90 days
}

export const retention: Record<string, Retention> = {
  reviews: { kind: "account" },
  productStats: { kind: "shop" },
  reviewIndex: { kind: "shop" },
  statsEvents: { kind: "ttl", field: "expireAt", days: 90 },
};
