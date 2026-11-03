import { FieldValue, type Transaction } from "firebase-admin/firestore";
import type { OrderDoc, RefundDoc } from "../model/orders.js";
import type { GatewayState } from "../payments/gateway.js";
import { fail } from "../shared/errors.js";
import { log } from "../shared/log.js";
import { inr, type Paise } from "../shared/money.js";
import { db } from "../shared/db.js";
import { doc, moveStock, readUndo, type Variant } from "./repository.js";

// Owner: engineer C. The gateway-neutral settlement state machine that payments (engineer D) calls inside its own
// transaction; the call shape is payments/flows.ts `Settlement`. Ports mark_order_paid / mark_payment_failed
// (20261028000200_rpcs.sql) and settle_refund (20261030000500_refunds.sql). Vectors: test-vectors/settlement.json.

const at = (now: Date) => ({ by: "system", at: now });
const PAID_NOTE = "Payment received";
const LATE_NOTE = "Payment received after cancellation. A refund is due.";

export type Outcome = "paid" | "revived" | "needs_refund" | "already_paid" | "failed" | "pending";

/** Marks the order paid only on `completed` with exactly its totalPaise; idempotent; revives an expired order only
 * if stock allows (and gives its coupon use back to it), else records that a refund is due. */
export async function settleOnlinePayment(
  tx: Transaction,
  orderId: string,
  p: { merchantOrderId: string; transactionId: string | null; amountPaise: number | null; state: GatewayState },
): Promise<{ outcome: Outcome }> {
  const ref = doc(`orders/${orderId}`);
  const o = (await tx.get(ref)).data() as OrderDoc | undefined;
  const attemptRef = doc(`orders/${orderId}/payments/${p.merchantOrderId}`);
  const attempt = await tx.get(attemptRef);
  if (!o || !attempt.exists) fail("NOT_FOUND");
  const now = new Date();
  const paid = o.paymentStatus === "paid" || o.paymentStatus === "refunded";
  if (p.state === "pending") return { outcome: "pending" };
  if (p.state === "failed") {
    if (attempt.get("state") === "pending") tx.update(attemptRef, { state: "failed", updatedAt: now });
    if (o.status === "pending_payment" && o.paymentStatus === "pending") tx.update(ref, { paymentStatus: "failed", updatedAt: now });
    return { outcome: "failed" };
  }
  const done = { state: "completed", transactionId: p.transactionId, updatedAt: now };
  if (paid) {
    // shortcut: a second, different payment on a paid order is only logged; refund it from the PhonePe dashboard
    if (attempt.get("state") !== "completed") {
      tx.update(attemptRef, done);
      log.warn("second payment on a paid order", { orderId, merchantOrderId: p.merchantOrderId });
    }
    return { outcome: "already_paid" };
  }
  if (o.paymentMethod !== "online") fail("INVALID_TRANSITION");
  if (p.amountPaise !== o.totalPaise) fail("PAYMENT_MISMATCH");
  const payment = { gateway: "phonepe", merchantOrderId: p.merchantOrderId, ...(p.transactionId ? { transactionId: p.transactionId } : {}), paidAt: now };

  let outcome: Outcome = "paid";
  if (o.status === "cancelled") {
    const undo = o.cancelledBy === "expiry" ? await readUndo(tx, orderId, o) : null;
    const inStock = undo?.variants.every((s, k) => s.exists && (s.data() as Variant).stock >= (o.items[k]?.qty ?? Infinity)) ?? false;
    if (!undo || !inStock) {
      tx.update(attemptRef, done);
      tx.update(ref, { paymentStatus: "paid", payment, events: FieldValue.arrayUnion({ status: "cancelled", note: LATE_NOTE, ...at(now) }), updatedAt: now });
      return { outcome: "needs_refund" };
    }
    undo.write(1, now);
    outcome = "revived";
  } else if (o.status !== "pending_payment") {
    fail("INVALID_TRANSITION");
  }
  tx.update(attemptRef, done);
  tx.update(ref, {
    status: "confirmed", paymentStatus: "paid", reservedUntil: null, payment,
    events: FieldValue.arrayUnion({ status: "confirmed", note: PAID_NOTE, ...at(now) }), updatedAt: now,
  });
  return { outcome };
}

/** Settles orders/{id}/refunds/{refundId}: pending → records the gateway's refund id (so one refund stays in flight);
 * processed → restocks if asked, a timeline note, paymentStatus refunded once everything is back; failed →
 * pendingRefundId cleared and the lines freed. Idempotent: a settled refund stays as it is. */
export async function settleRefund(
  tx: Transaction,
  orderId: string,
  refundId: string,
  r: { state: GatewayState; gatewayRefundId: string | null; failure: string | null },
): Promise<{ status: RefundDoc["status"] }> {
  const ref = doc(`orders/${orderId}`);
  const refundRef = doc(`orders/${orderId}/refunds/${refundId}`);
  const f = (await tx.get(refundRef)).data() as RefundDoc | undefined;
  const o = (await tx.get(ref)).data() as OrderDoc | undefined;
  if (!f || !o) fail("NOT_FOUND");
  if (f.status !== "pending") return { status: f.status };
  const now = new Date();
  const gatewayRefundId = f.gatewayRefundId ?? r.gatewayRefundId ?? null;
  if (r.state === "pending") {
    if (gatewayRefundId !== (f.gatewayRefundId ?? null)) tx.update(refundRef, { gatewayRefundId, updatedAt: now });
    return { status: "pending" };
  }
  const freeLines = { pendingRefundId: null, updatedAt: now };
  if (r.state === "failed") {
    const failure = (r.failure?.trim() || "PhonePe couldn’t complete it.").slice(0, 300);
    tx.update(refundRef, { status: "failed", failure, gatewayRefundId, updatedAt: now });
    tx.update(ref, { ...freeLines, items: o.items.map((i) => (i.refundId === refundId ? { ...i, refundId: null } : i)) });
    return { status: "failed" };
  }

  const lines = o.items.filter((i) => i.refundId === refundId);
  const processed = await tx.get(db().collection(`orders/${orderId}/refunds`).where("status", "==", "processed"));
  const back = processed.docs.reduce((s, d) => s + (d.get("amountPaise") as number), 0) + f.amountPaise;
  const vs = f.restock && lines.length ? await tx.getAll(...lines.map((i) => doc(`variants/${i.id}`))) : [];
  for (const [k, s] of vs.entries()) if (s.exists) moveStock(tx, s.id, s.data() as Variant, lines[k]?.qty ?? 0, "refund", now);
  const names = [...lines].sort((a, b) => b.unitPricePaise - a.unitPricePaise || (a.id < b.id ? -1 : 1)).map((i) => i.productName).join(", ");
  const note = `Refund of ${inr(f.amountPaise as Paise)}${f.fullRefund ? "" : ` for ${names}`} issued to your original payment method. Banks usually take 5–7 working days to show it.`.slice(0, 500);
  const all = back >= o.totalPaise;
  const status = all && o.status === "delivered" ? "refunded" : o.status;
  tx.update(refundRef, { status: "processed", gatewayRefundId, updatedAt: now });
  tx.update(ref, {
    ...freeLines, ...(all ? { paymentStatus: "refunded", status } : {}),
    events: FieldValue.arrayUnion({ status, note, ...at(now) }),
  });
  return { status: "processed" };
}
