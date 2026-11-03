import { expect, test } from "vitest";
import * as notices from "../../src/notifications/notices.js";
import { loadVectors, resolveTimes } from "../vectors.js";
import { matches } from "./match.js";

// test-vectors/notifications.json through the pure notices.ts: the copy, who hears it, and each notice's key.
const file = loadVectors("notifications");
const now = new Date(file.now);
type I = Record<"id" | "before" | "after" | "orderId" | "refundId" | "refund" | "order" | "uid" | "coupon" | "feedback" | "about" | "imagePath" | "variant" | "key" | "variantId", never>;
/** ISO instants in the vectors are Timestamps in Firestore: Dates here (notices.ts takes either). */
const dates = (v: unknown): unknown =>
  typeof v === "string" && /^\d{4}-\d\d-\d\dT/.test(v) ? new Date(v)
    : Array.isArray(v) ? v.map(dates) : v !== null && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([a, b]) => [a, dates(b)])) : v;
const calls: Record<string, (i: I) => unknown> = {
  orderNotices: (i) => notices.orderNotices(i.id, i.before, i.after),
  refundNotices: (i) => notices.refundNotices(i.orderId, i.refundId, i.before, i.refund, i.order),
  repairNotices: (i) => notices.repairNotices(i.id, i.before, i.after),
  couponNotice: (i) => notices.couponNotice(i.id, i.uid, i.coupon),
  feedbackNotices: (i) => notices.feedbackNotices(i.id, i.before, i.feedback, i.about, i.imagePath),
  stockNotices: (i) => notices.stockNotices(i.before, i.variant, i.key),
  backInStock: (i) => { const n = notices.backInStock(i.variantId, i.before, i.variant); return n ? [n] : []; },
};

test.each(file.cases.map((k) => [k.id, k] as const))("%s", (_id, k) => {
  const got = calls[k.call]?.(dates(resolveTimes(k.input, now)) as I);
  matches(got, (k.expect as { notices: unknown }).notices);
  for (const n of got as { title: string; body: string }[]) expect(Array.from(n.title).length <= 80 && Array.from(n.body).length <= 300).toBe(true);
});
