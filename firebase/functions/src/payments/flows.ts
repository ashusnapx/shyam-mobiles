import { randomUUID } from "node:crypto";
import type { DocumentReference, Firestore, Transaction } from "firebase-admin/firestore";
import { ORDER_RETENTION_DAYS, type PaymentStatus } from "../model/orders.js";
import { DAY_MS } from "../model/retention.js";
import { GatewayError, type GatewayState, type PaymentGateway } from "./gateway.js";
import { webhookAuthorized } from "./phonepe.js";
import { expireAfterSeconds, merchantOrderId, merchantRefundId, orderNumberOf, PaymentError, planRefund, type RefundableOrder } from "./service.js";

// The PhonePe payment flows behind the callables (docs/FIREBASE.md §5, docs/PHONEPE.md). Amounts come from the order;
// whether money moved comes from the gateway's status APIs, never from the phone or a webhook body. Order-side effects
// (paid, failed, refunded, timeline, stock) are orders/settlement.ts's, called inside our transactions:
//   orders/{id}                       read here: uid, number, status, paymentMethod, paymentStatus, totalPaise,
//                                     reservedUntil, payment, pendingRefundId, items; written here: pendingRefundId and
//                                     items[].refundId when a refund starts
//   orders/{id}/payments/{merchantOrderId}  { state, amountPaise, phonepeOrderId, token, expireAt, transactionId?,
//                                     createdAt, updatedAt, purgeAt }: created and closed here; settleOnlinePayment moves
//                                     it to completed / failed
//   orders/{id}/refunds/{refundId}    { amountPaise, fullRefund, itemIds, restock, status, gatewayRefundId, failure,
//                                     createdBy, createdAt, updatedAt, purgeAt }: created here, and gatewayRefundId set
//                                     here when PhonePe accepts it; settleRefund settles it (completed / failed) and
//                                     clears pendingRefundId (and items[].refundId when it failed)

/** orders/settlement.ts (engineer C), as these flows call it. Both are idempotent. */
export interface Settlement {
  settleOnlinePayment(tx: Transaction, orderId: string,
    p: { merchantOrderId: string; transactionId: string | null; amountPaise: number | null; state: GatewayState }): Promise<unknown>;
  settleRefund(tx: Transaction, orderId: string, refundId: string,
    r: { state: GatewayState; gatewayRefundId: string | null; failure: string | null }): Promise<unknown>;
}

export type Deps = { db: Firestore; gateway: PaymentGateway; settlement: Settlement; now?: () => number; random?: () => string };

type Order = RefundableOrder & {
  paymentStatus: PaymentStatus;
  uid: string | null;
  number: string;
  paymentMethod: string;
  reservedUntil?: Stamp | null;
  pendingRefundId?: string | null;
};
type Attempt = { state: GatewayState; amountPaise: number; phonepeOrderId: string | null; token: string | null; createdAt: Stamp };
type Refund = { amountPaise: number; status: "pending" | "processed" | "failed"; gatewayRefundId?: string | null };
type Stamp = Date | { toMillis(): number } | number;

const ID = /^[A-Za-z0-9]{1,40}$/; // Firestore auto ids
const ms = (v: Stamp | null | undefined) => (v == null ? null : typeof v === "number" ? v : v instanceof Date ? v.getTime() : v.toMillis());
const hex = (deps: Deps) => (deps.random?.() ?? randomUUID()).replace(/-/g, "");
const IN_PROGRESS = () => new PaymentError(409, "PAYMENT_IN_PROGRESS", "Your payment is being set up. Try again in a moment.");
const GATEWAY = () => new PaymentError(502, "GATEWAY_ERROR", "Payment service error. Try again.");
const purgeAt = (now: number) => new Date(now + ORDER_RETENTION_DAYS * DAY_MS); // kept with the order (GST records)

function orderId(body: unknown): string {
  const id = (body as { orderId?: unknown } | null)?.orderId;
  if (typeof id !== "string" || !ID.test(id)) throw new PaymentError(400, "BAD_REQUEST", "orderId is required.");
  return id;
}

async function ownOrder(deps: Deps, id: string, uid: string): Promise<Order> {
  const order = (await deps.db.doc(`orders/${id}`).get()).data() as Order | undefined;
  if (!order || order.uid !== uid) throw new PaymentError(404, "NOT_FOUND", "Order not found.");
  return order;
}

const isPaid = (o: Order) => o.paymentStatus === "paid" || o.paymentStatus === "refunded";

async function pendingAttempt(deps: Deps, id: string, tx?: Transaction) {
  const q = deps.db.collection(`orders/${id}/payments`).where("state", "==", "pending").limit(1);
  const snap = tx ? await tx.get(q) : await q.get();
  const doc = snap.docs[0];
  return doc ? { ref: doc.ref, id: doc.id, a: doc.data() as Attempt } : null;
}

// The gateway's word on one PhonePe order, handed to settleOnlinePayment.
async function settle(deps: Deps, id: string, merchantOrder: string): Promise<void> {
  let s;
  try {
    s = await deps.gateway.orderStatus(merchantOrder);
  } catch (e) {
    throw e instanceof GatewayError ? GATEWAY() : e;
  }
  await deps.db.runTransaction((tx) => deps.settlement.settleOnlinePayment(tx, id, { merchantOrderId: merchantOrder, ...s }));
}

// {orderId} -> {merchantId, token, orderId (PhonePe's), env} for the app's PhonePe SDK, or {paid: true} when the
// order is already paid (PhonePe had the money before the webhook said so).
export async function createPayment(body: unknown, uid: string, deps: Deps) {
  const now = deps.now?.() ?? Date.now();
  const id = orderId(body);
  let order = await ownOrder(deps, id, uid);
  if (isPaid(order)) return { paid: true as const };
  if (order.status !== "pending_payment" || order.paymentMethod !== "online") {
    throw new PaymentError(409, "ORDER_NOT_PAYABLE", "This order can't be paid online.");
  }
  const until = ms(order.reservedUntil);
  if (!until || until <= now) throw new PaymentError(409, "ORDER_EXPIRED", "Payment time ran out. Place the order again.");

  const open = await pendingAttempt(deps, id);
  if (open?.a.token && open.a.phonepeOrderId) {
    await settle(deps, id, open.id); // never a second PhonePe order while this one can still be paid
    const after = (await open.ref.get()).data() as Attempt;
    if (after.state === "pending") return reply(deps, open.a.phonepeOrderId, open.a.token);
    order = await ownOrder(deps, id, uid);
    if (isPaid(order)) return { paid: true as const };
  } else if (open) {
    if (now - (ms(open.a.createdAt) ?? 0) < 60_000) throw IN_PROGRESS(); // another tap is making it right now
    await close(deps, open.ref); // died before PhonePe answered: its token never left the server, nobody can pay it
  }

  const mid = merchantOrderId(order.number, hex(deps));
  const expireAfter = expireAfterSeconds(until, now);
  const ref = deps.db.doc(`orders/${id}/payments/${mid}`);
  await deps.db.runTransaction(async (tx) => {
    if (await pendingAttempt(deps, id, tx)) throw IN_PROGRESS();
    tx.create(ref, {
      state: "pending", amountPaise: order.totalPaise, phonepeOrderId: null, token: null,
      expireAt: new Date(now + expireAfter * 1000), transactionId: null, createdAt: new Date(now), updatedAt: new Date(now),
      purgeAt: purgeAt(now),
    });
  });

  let made;
  try {
    made = await deps.gateway.createOrder({
      merchantOrderId: mid, amountPaise: order.totalPaise, expireAfterSeconds: expireAfter, orderId: id, orderNumber: order.number,
    });
  } catch (e) {
    await close(deps, ref);
    throw e instanceof GatewayError ? GATEWAY() : e;
  }
  await ref.update({
    phonepeOrderId: made.phonepeOrderId, token: made.token, updatedAt: new Date(now), ...(made.expireAt ? { expireAt: made.expireAt } : {}),
  });
  return reply(deps, made.phonepeOrderId, made.token);
}

const reply = (deps: Deps, phonepeOrderId: string, token: string) =>
  ({ merchantId: deps.gateway.merchantId, token, orderId: phonepeOrderId, env: deps.gateway.env });

// A PhonePe order whose token never left the server is closed here, not by the gateway's word.
async function close(deps: Deps, ref: DocumentReference) {
  await deps.db.runTransaction(async (tx) => {
    const a = (await tx.get(ref)).data() as Attempt | undefined;
    if (a?.state === "pending" && !a.token) tx.update(ref, { state: "failed", updatedAt: new Date(deps.now?.() ?? Date.now()) });
  });
}

// {orderId} -> {status, paymentStatus}: after the SDK closes (whatever it said), and when the order screen asks.
export async function verifyPayment(body: unknown, uid: string, deps: Deps) {
  const id = orderId(body);
  let order = await ownOrder(deps, id, uid);
  if (!isPaid(order)) {
    const open = await pendingAttempt(deps, id);
    if (open?.a.token) {
      await settle(deps, id, open.id);
      order = await ownOrder(deps, id, uid);
    }
  }
  return { status: order.status, paymentStatus: order.paymentStatus };
}

// PhonePe's webhook -> [HTTP status, body]. The header is checked in constant time; the body only names the order or
// refund, and the facts come from the status APIs. Refusals that won't change on a retry (an unknown id, an amount that
// doesn't match) are acknowledged with 200 so PhonePe stops; outages throw (500) so PhonePe retries.
export async function phonepeWebhook(authorization: string | undefined, rawBody: string,
  creds: { username: string; password: string }, deps: Deps): Promise<[number, { result: string }]> {
  if (!webhookAuthorized(authorization, creds.username, creds.password)) return [401, { result: "unauthorized" }];
  let body: { event?: unknown; type?: unknown; payload?: unknown } = {};
  try {
    body = (JSON.parse(rawBody) as typeof body | null) ?? {};
  } catch { /* not JSON */ }
  // "checkout.order.completed", or the SDKs' type CHECKOUT_ORDER_COMPLETED for the same thing
  const event = typeof body.event === "string" ? body.event : typeof body.type === "string" ? body.type.toLowerCase().replace(/_/g, ".") : null;
  if (!event || typeof body.payload !== "object" || body.payload === null) return [400, { result: "bad_request" }];
  const payload = body.payload as Record<string, unknown>;

  const refund = event.startsWith("pg.refund.");
  if (!refund && !event.startsWith("checkout.")) return [200, { result: "ignored" }];
  const ref = refund ? payload.merchantRefundId : payload.merchantOrderId;
  const number = orderNumberOf(ref);
  const found = number ? (await deps.db.collection("orders").where("number", "==", number).limit(1).get()).docs[0] : undefined;
  const doc = found && (await deps.db.doc(`orders/${found.id}/${refund ? "refunds" : "payments"}/${ref as string}`).get());
  // a refund or order made in the PhonePe dashboard isn't ours: staff handle it by hand
  if (!found || !doc?.exists) return [200, { result: refund ? "unknown_refund" : "unknown_order" }];

  try {
    if (!refund) {
      await settle(deps, found.id, ref as string);
    } else {
      const r = await deps.gateway.refundStatus(ref as string);
      if (!r) return [200, { result: "unknown_refund" }];
      await deps.db.runTransaction((tx) => deps.settlement.settleRefund(tx, found.id, ref as string, { ...r, failure: null }));
    }
    return [200, { result: "settled" }];
  } catch (e) {
    const reason = reasonOf(e);
    if (reason && reason !== "GATEWAY_ERROR") return [200, { result: reason.toLowerCase() }];
    throw e;
  }
}

// PaymentError here, HttpsError details.reason from orders/settlement.ts
const reasonOf = (e: unknown): string | null =>
  e instanceof PaymentError ? e.reason : ((e as { details?: { reason?: unknown } } | null)?.details?.reason as string | undefined) ?? null;

// Refunds ----------------------------------------------------------------------------------------------------------

// {orderId, itemIds?, restock?} -> {refundId, amountPaise, status, retry}. Staff only: the handler checks the claim.
// One refund in flight per order (orders.pendingRefundId): REFUND_IN_PROGRESS once PhonePe has accepted it (its
// gatewayRefundId is recorded). Our refund id is PhonePe's merchantRefundId; a retry of one PhonePe never confirmed asks
// PhonePe for that refund first and sends it only if PhonePe has never heard of it, so it never pays out twice.
export async function startRefund(body: unknown, staffUid: string, deps: Deps) {
  const now = deps.now?.() ?? Date.now();
  const { itemIds = null, restock = false } = (body ?? {}) as { itemIds?: unknown; restock?: unknown };
  const id = orderId(body);
  const items = itemIds === null || (Array.isArray(itemIds) && itemIds.length > 0 && itemIds.length <= 10 &&
    itemIds.every((i) => typeof i === "string" && ID.test(i)));
  if (!items || typeof restock !== "boolean") throw new PaymentError(400, "BAD_REQUEST", "itemIds is a list of order item ids.");

  const orderRef = deps.db.doc(`orders/${id}`);
  const start = await deps.db.runTransaction(async (tx) => {
    const o = (await tx.get(orderRef)).data() as Order | undefined;
    if (!o) throw new PaymentError(404, "NOT_FOUND", "Order not found.");
    if (o.pendingRefundId) {
      const r = (await tx.get(deps.db.doc(`orders/${id}/refunds/${o.pendingRefundId}`))).data() as Refund | undefined;
      if (r?.gatewayRefundId) {
        throw new PaymentError(409, "REFUND_IN_PROGRESS", "A refund for this order is already with PhonePe. Wait until it’s done, then refresh.");
      }
      if (r && o.payment) return { refundId: o.pendingRefundId, amountPaise: r.amountPaise, merchantOrderId: o.payment.merchantOrderId, retry: true };
    }
    const processed = await tx.get(deps.db.collection(`orders/${id}/refunds`).where("status", "==", "processed"));
    const refunded = processed.docs.reduce((sum, d) => sum + (d.data() as Refund).amountPaise, 0);
    const plan = planRefund(o, refunded, itemIds as string[] | null);
    const refundId = merchantRefundId(o.number, hex(deps));
    tx.create(deps.db.doc(`orders/${id}/refunds/${refundId}`), {
      amountPaise: plan.amountPaise, fullRefund: plan.fullRefund, itemIds: plan.lineIds,
      restock: restock && o.status !== "cancelled", // a cancel already restocked
      status: "pending", gatewayRefundId: null, failure: null, createdBy: staffUid, createdAt: new Date(now), updatedAt: new Date(now),
      purgeAt: purgeAt(now),
    });
    tx.update(orderRef, {
      pendingRefundId: refundId, updatedAt: new Date(now),
      items: o.items.map((i) => (plan.lineIds.includes(i.id) ? { ...i, refundId } : i)),
    });
    return { refundId, amountPaise: plan.amountPaise, merchantOrderId: plan.merchantOrderId, retry: false };
  });

  const settleWith = (r: { state: GatewayState; gatewayRefundId: string | null; failure: string | null }) =>
    deps.db.runTransaction((tx) => deps.settlement.settleRefund(tx, id, start.refundId, r));
  let r;
  try {
    r = (start.retry ? await deps.gateway.refundStatus(start.refundId) : null) ??
      await deps.gateway.refund({ merchantRefundId: start.refundId, merchantOrderId: start.merchantOrderId, amountPaise: start.amountPaise });
  } catch (e) {
    if (!(e instanceof GatewayError)) throw e;
    if (e.definite) {
      const why = e.description || e.code || "no reason given";
      await settleWith({ state: "failed", gatewayRefundId: null, failure: why });
      throw new PaymentError(409, "REFUND_REFUSED", `PhonePe refused the refund: ${why}`);
    }
    throw new PaymentError(502, "REFUND_UNCONFIRMED",
      "PhonePe didn't confirm the refund. Tap Refund again: it retries this same refund, never a second one.");
  }
  if (r.state === "pending") {
    // accepted, not paid out yet: its id marks it in flight; the webhook settles it
    const refundRef = deps.db.doc(`orders/${id}/refunds/${start.refundId}`);
    await deps.db.runTransaction(async (tx) => {
      const f = (await tx.get(refundRef)).data() as Refund | undefined;
      if (f?.status === "pending" && r.gatewayRefundId) tx.update(refundRef, { gatewayRefundId: r.gatewayRefundId, updatedAt: new Date(now) });
    });
  } else {
    await settleWith({ ...r, failure: null });
  }
  const after = (await deps.db.doc(`orders/${id}/refunds/${start.refundId}`).get()).data() as Refund;
  return { refundId: start.refundId, amountPaise: start.amountPaise, status: after.status, retry: start.retry };
}
