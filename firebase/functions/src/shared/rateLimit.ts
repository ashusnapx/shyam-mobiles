import { Timestamp, type Transaction } from "firebase-admin/firestore";
import { fail, type Reason } from "./errors.js";
import { db } from "./db.js";

// Per-user rolling windows in one rateLimits/{uid} doc (docs/SECURITY.md §2.6): { [key]: Timestamp[], expireAt }.
// The doc's TTL (1 day) cleans it up. Counted inside the caller's transaction when it has one, so a refused call
// leaves no trace and two parallel calls can't both slip under the limit.

export const LIMITS = {
  quoteOrder: { max: 30, windowMs: 60_000 },
  placeOrder: { max: 5, windowMs: 600_000 },
  couponFails: { max: 10, windowMs: 600_000, reason: "COUPON_RATE_LIMIT" },
  createPayment: { max: 10, windowMs: 600_000 },
  verifyPayment: { max: 20, windowMs: 600_000 },
  applyReferralCode: { max: 5, windowMs: 3_600_000 },
  sendFeedback: { max: 10, windowMs: 86_400_000, reason: "FEEDBACK_LIMIT" },
  exportMyData: { max: 1, windowMs: 86_400_000 },
} as const satisfies Record<string, { max: number; windowMs: number; reason?: Reason }>;

export type LimitKey = keyof typeof LIMITS;

/** Pure: the hits still inside the window plus this one, or null when the limit is reached. */
export function nextHits(hits: readonly number[], nowMs: number, { max, windowMs }: { max: number; windowMs: number }): number[] | null {
  const recent = hits.filter((t) => t > nowMs - windowMs);
  return recent.length >= max ? null : [...recent, nowMs];
}

/** Counts one call of [key] for [uid] in [tx] (a read: call it before the transaction writes anything); fails with the
 * limit's reason (default RATE_LIMITED) when over. */
export async function takeRateLimit(tx: Transaction, uid: string, key: LimitKey, nowMs = Date.now()): Promise<void> {
  const ref = db().doc(`rateLimits/${uid}`);
  const snap = await tx.get(ref);
  const hits = ((snap.get(key) as Timestamp[] | undefined) ?? []).map((t) => t.toMillis());
  const limit = LIMITS[key];
  const next = nextHits(hits, nowMs, limit);
  if (next === null) fail("reason" in limit ? limit.reason : "RATE_LIMITED");
  tx.set(ref, { [key]: next.map((t) => Timestamp.fromMillis(t)), expireAt: Timestamp.fromMillis(nowMs + 86_400_000) }, { merge: true });
}
