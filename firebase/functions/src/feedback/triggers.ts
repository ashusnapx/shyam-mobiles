import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { DAY_MS } from "../model/retention.js";
import { db } from "../shared/db.js";
import { BACKGROUND } from "../shared/options.js";
import { istDate } from "../shared/time.js";
import { ratingStats } from "./ratings.js";
import { addSold, addWith, counts, gone, units } from "./stats.js";

// Growth (docs/GROWTH.md §2a, b): productStats/{id} and reviewIndex/public follow the visible reviews and the orders.

/** Recounts the product's visible reviews on every write: idempotent, so a retried or reordered run ends right. */
export const reviewStats = onDocumentWritten({ document: "reviews/{id}", ...BACKGROUND, retry: true }, async (event) => {
  const productId = (event.data?.after.data() ?? event.data?.before.data())?.productId as unknown;
  if (typeof productId !== "string") return;
  await db().runTransaction(async (tx) => {
    // shortcut: reads every visible rating of the product; keep running sums once a product passes ~2,000 reviews
    const snap = await tx.get(db().collection("reviews").where("productId", "==", productId).where("hidden", "==", false).select("rating"));
    const s = ratingStats(snap.docs.map((d) => d.get("rating") as unknown));
    const at = Timestamp.now();
    tx.set(db().doc(`productStats/${productId}`), { ratingCount: s.count, ratingSum: s.sum, stars: s.stars, updatedAt: at }, { merge: true });
    tx.set(db().doc("reviewIndex/public"),
      { cards: { [productId]: s.count > 0 ? { a: s.avg10, n: s.count } : FieldValue.delete() }, updatedAt: at }, { merge: true });
  });
});

/** "N bought this week" and the co-purchase counts follow the orders: an order counts once, when it is first paid or
 * delivered, and is taken back on a cancel or refund. statsEvents/{orderId} makes each step happen once, retries and
 * all. A revived order (paid after expiry) isn't counted again: an undercount, never an overcount. */
export const productSales = onDocumentWritten({ document: "orders/{id}", ...BACKGROUND, retry: true }, async (event) => {
  const after = event.data?.after.data();
  if (!after) return;
  const add = counts(after);
  if (!add && !gone(after)) return;
  const markRef = db().doc(`statsEvents/${event.params.id}`);
  await db().runTransaction(async (tx) => {
    const mark = await tx.get(markRef);
    if (add ? mark.exists : !mark.exists || mark.get("reversed") === true) return;
    const now = new Date();
    const u = add ? units(after.items) : ((mark.get("units") ?? {}) as Record<string, number>);
    const day = add ? istDate(now) : String(mark.get("day"));
    const ids = Object.keys(u);
    const refs = ids.map((p) => db().doc(`productStats/${p}`));
    const docs = refs.length > 0 ? await tx.getAll(...refs) : [];
    const at = Timestamp.fromDate(now), sign = add ? 1 : -1;
    docs.forEach((d, i) => {
      const p = ids[i] ?? "";
      tx.set(d.ref, {
        sold: addSold(d.get("sold") as Record<string, number> | undefined, day, sign * (u[p] ?? 0), istDate(now)),
        with: addWith(d.get("with") as Record<string, number> | undefined, p, ids, sign),
        updatedAt: at,
      }, { mergeFields: ["sold", "with", "updatedAt"] });
    });
    if (add) tx.create(markRef, { day, units: u, reversed: false, createdAt: at, expireAt: Timestamp.fromMillis(now.getTime() + 90 * DAY_MS) });
    else tx.update(markRef, { reversed: true });
  });
});
