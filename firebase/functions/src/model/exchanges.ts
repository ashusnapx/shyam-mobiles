import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Growth (docs/GROWTH.md §2c). "Exchange your old phone": the customer describes it, staff reply with an estimate.
// No price is shown until the shop gives one, and an estimate always says the final value is set when the shop
// checks the phone.

export type ExchangeAge = "under_1" | "1_2" | "2_3" | "over_3"; // years
export type ExchangeCondition = "like_new" | "good" | "fair" | "damaged";

/** exchanges/{id} (S: requestExchange creates, estimateExchange answers; the customer and staff read it) */
export interface ExchangeDoc {
  uid: string;
  brand: string; // ≤ 40
  model: string; // ≤ 60
  age: ExchangeAge;
  condition: ExchangeCondition;
  photos: string[]; // ≤ 3 Storage keys under exchange-photos/{uid}/ (customer and staff read)
  forProductId: string | null; // the phone page it was asked from
  status: "new" | "estimated";
  estimate: { lowPaise: number; highPaise: number; note: string; at: Timestamp } | null; // staff, ≤ ₹10,00,000
  createdAt: Timestamp;
  updatedAt: Timestamp;
  purgeAt: Timestamp; // 180 days: an old estimate means nothing
}

export const retention: Record<string, Retention> = {
  exchanges: { kind: "ttl", field: "purgeAt", days: 180 },
};
