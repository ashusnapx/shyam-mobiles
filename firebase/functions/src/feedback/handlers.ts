import { Timestamp } from "firebase-admin/firestore";
import { DAY_MS } from "../model/retention.js";
import { requireUser } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { db } from "../shared/db.js";
import { fail } from "../shared/errors.js";
import { takeRateLimit } from "../shared/rateLimit.js";
import * as c from "./contract.js";

// Owner: engineer D. A port of send_feedback (supabase/migrations/20261030000270_feedback_links.sql): the link must
// be the caller's own order or repair (or a real product); rating an order or a repair again replaces the earlier one
// (doc id order_{id} / repair_{id}) and puts it back to new; FEEDBACK_LIMIT past 10 a day.

const PURGE_MS = 2 * 366 * DAY_MS; // model/feedback.ts retention

export const sendFeedback = callable(c.sendFeedback, async (f, req) => {
  const { uid } = requireUser(req);
  const needs = { order: f.orderId, repair: f.repairId, product: f.productId } as Record<string, string | null | undefined>;
  if (f.kind in needs && !needs[f.kind]) fail("BAD_REQUEST", [`${f.kind}Id`]);
  const id = f.kind === "order" ? `order_${f.orderId ?? ""}` : f.kind === "repair" ? `repair_${f.repairId ?? ""}` : null;
  const ref = id ? db().doc(`feedback/${id}`) : db().collection("feedback").doc();
  await db().runTransaction(async (tx) => {
    const [before, order, repair, product] = await Promise.all([
      id ? tx.get(ref) : null,
      f.orderId ? tx.get(db().doc(`orders/${f.orderId}`)) : null,
      f.repairId ? tx.get(db().doc(`repairs/${f.repairId}`)) : null,
      f.productId ? tx.get(db().doc(`products/${f.productId}`)) : null,
    ]);
    if ((order && order.get("uid") !== uid) || (repair && repair.get("uid") !== uid) || (product && !product.exists)) fail("NOT_FOUND");
    await takeRateLimit(tx, uid, "sendFeedback"); // its read comes last: transactions read before they write
    const at = Timestamp.now();
    const doc = {
      uid, kind: f.kind, rating: f.rating ?? null, message: f.message, orderId: f.orderId ?? null, repairId: f.repairId ?? null,
      productId: f.productId ?? null, screen: f.screen ?? null, appVersion: f.appVersion ?? null, status: "new", updatedAt: at,
    };
    if (before?.exists) tx.update(ref, doc); // keeps createdAt and the staff note
    else tx.create(ref, { ...doc, createdAt: at, purgeAt: Timestamp.fromMillis(at.toMillis() + PURGE_MS) });
  });
  return { id: ref.id };
});
