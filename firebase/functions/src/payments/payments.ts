import { randomUUID } from "node:crypto";
import type { Db, Tx } from "./db.js";
import { PaymentError, type PhonePe, PhonePeError, type PhonePeOrder, webhookAuthorized } from "./phonepe.js";

// Paying for an order with PhonePe, and refunding it (docs/PHONEPE.md). Amounts always come from the order document,
// never from the phone; whether money arrived is always PhonePe's order status API, never the SDK's reply or a
// webhook body. Documents (field names are the contract with the rest of the backend):
//   orders/{orderId}          read: userId, number, status, paymentMethod ("online" | "cod"), paymentStatus,
//                             totalPaise, reservedUntil (ms or Timestamp), items[{id, name, unitPricePaise, qty,
//                             discountPaise, refundId}]; written here: paymentStatus, status, reservedUntil, payment,
//                             phonepeOpen, refundPending, refundedPaise, items[].refundId
//   orders/{orderId}/events   {status, note, at}: the order's timeline
//   phonepeOrders/{merchantOrderId}  one PhonePe order (an attempt to pay); server only
//   refunds/{refundId}        one refund; its id is PhonePe's merchantRefundId; server only

export type Order = {
  userId: string | null;
  number: string;
  status: string;
  paymentMethod: string;
  paymentStatus: string;
  totalPaise: number;
  reservedUntil?: number | { toMillis(): number } | null;
  items?: Item[];
  phonepeOpen?: string | null; // the open PhonePe order: at most one, so never two payments in flight
  refundPending?: string | null; // the refund in flight: at most one
  refundedPaise?: number;
  payment?: { gateway: "phonepe"; merchantOrderId: string; transactionId: string | null; amountPaise: number; at: number } | null;
};
export type Item = { id: string; name?: string; unitPricePaise: number; qty: number; discountPaise?: number; refundId?: string | null };
export type Attempt = {
  orderId: string;
  amountPaise: number;
  state: "PENDING" | "COMPLETED" | "FAILED";
  phonepeOrderId: string | null;
  token: string | null; // the SDK's order token: null until PhonePe made the order
  expiresAt: number;
  transactionId: string | null;
  createdAt: number;
  updatedAt: number;
};
export type Refund = {
  orderId: string;
  amountPaise: number;
  fullRefund: boolean;
  itemIds: string[];
  restock: boolean;
  status: "pending" | "processed" | "failed";
  merchantOrderId: string;
  failure: string | null;
  createdBy: string;
  createdAt: number;
  updatedAt: number;
};

export type Deps = { db: Db; pp: PhonePe; now?: () => number; newId?: () => string };

const ID = /^[A-Za-z0-9_-]{1,128}$/; // Firestore ids we make or accept
const ms = (v: Order["reservedUntil"]) => (v == null ? null : typeof v === "number" ? v : v.toMillis());
const event = (tx: Tx, orderId: string, status: string, note: string, at: number) =>
  tx.add(`orders/${orderId}/events`, { status, note, at });

// ₹ in Indian grouping, as the app's formatInr: 12999900 → ₹1,29,999, 4950 → ₹49.50
export function inr(paise: number): string {
  const rupees = String(Math.floor(paise / 100)).replace(/(\d)(?=(\d\d)+\d$)/g, "$1,");
  return `₹${rupees}${paise % 100 ? `.${String(paise % 100).padStart(2, "0")}` : ""}`;
}

async function ownOrder(deps: Deps, orderId: unknown, userId: string): Promise<[string, Order]> {
  if (typeof orderId !== "string" || !ID.test(orderId)) throw new PaymentError(400, "BAD_REQUEST", "order_id is required.");
  const order = await deps.db.get<Order>(`orders/${orderId}`);
  if (!order || order.userId !== userId) throw new PaymentError(404, "NOT_FOUND", "Order not found.");
  return [orderId, order];
}

const state = async (deps: Deps, orderId: string) => {
  const o = await deps.db.get<Order>(`orders/${orderId}`);
  return { order_id: orderId, status: o?.status ?? null, payment: o?.paymentStatus ?? null };
};

// PhonePe's order status -> our documents. Idempotent: paid / failed / pending / duplicate. COMPLETED counts even on a
// PhonePe order we closed (money is money); a second payment on a paid order goes on the timeline for staff to refund.
export async function settle(deps: Deps, merchantOrderId: string): Promise<string> {
  const now = deps.now?.() ?? Date.now();
  const s = await deps.pp.call<PhonePeOrder>(`/checkout/v2/order/${encodeURIComponent(merchantOrderId)}/status?details=false`);
  const pp = s.state === "COMPLETED" || s.state === "FAILED" ? s.state : "PENDING";
  const paid = s.paymentDetails?.find((p) => p.state === "COMPLETED") ?? s.paymentDetails?.[0];
  return await deps.db.tx(async (tx) => {
    const a = await tx.get<Attempt>(`phonepeOrders/${merchantOrderId}`);
    if (!a) throw new PaymentError(404, "NOT_FOUND", "Payment not found.");
    const o = await tx.get<Order>(`orders/${a.orderId}`);
    if (!o) throw new PaymentError(404, "NOT_FOUND", "Order not found.");
    if (a.state === "COMPLETED") return "paid";
    const open = o.phonepeOpen === merchantOrderId ? { phonepeOpen: null } : {};
    if (pp === "FAILED") {
      if (a.state === "PENDING") {
        tx.update(`phonepeOrders/${merchantOrderId}`, { state: "FAILED", updatedAt: now });
        // the order stays payable (with a new PhonePe order) until it expires
        const change = { ...open, ...(o.paymentStatus === "pending" ? { paymentStatus: "failed" } : {}) };
        if (Object.keys(change).length) tx.update(`orders/${a.orderId}`, change); // Firestore refuses an empty update
      }
      return "failed";
    }
    if (pp === "PENDING") return "pending";
    if (s.amount !== a.amountPaise) {
      console.error("phonepe amount mismatch", { merchantOrderId, amount: s.amount, expected: a.amountPaise });
      throw new PaymentError(409, "AMOUNT_MISMATCH", "Payment does not match this order. Contact the store.");
    }
    const transactionId = typeof paid?.transactionId === "string" ? paid.transactionId : null;
    tx.update(`phonepeOrders/${merchantOrderId}`, { state: "COMPLETED", transactionId, updatedAt: now });
    if (o.paymentStatus === "paid" || o.paymentStatus === "refunded") {
      if (Object.keys(open).length) tx.update(`orders/${a.orderId}`, open);
      event(tx, a.orderId, o.status, `A second payment of ${inr(a.amountPaise)} came in through PhonePe (order ${merchantOrderId}). A refund is due.`, now);
      return "duplicate";
    }
    const payment = { gateway: "phonepe", merchantOrderId, transactionId, amountPaise: a.amountPaise, at: now };
    if (o.status === "pending_payment") {
      tx.update(`orders/${a.orderId}`, { status: "confirmed", paymentStatus: "paid", reservedUntil: null, phonepeOpen: null, payment });
      event(tx, a.orderId, "confirmed", "Payment received", now);
    } else {
      // shortcut: a payment after the order expired or was cancelled is recorded, not revived (no stock check here);
      // upgrade by calling the orders code's revive once it exists
      tx.update(`orders/${a.orderId}`, { paymentStatus: "paid", phonepeOpen: null, payment });
      event(tx, a.orderId, o.status, "Payment received after cancellation. A refund is due.", now);
    }
    return "paid";
  });
}

// {order_id} -> {gateway, environment, merchant_id, phonepe_order_id, token, order_number, amount, reserved_until}
// for the app's PhonePe SDK, or {order_id, status, payment: "paid"} when PhonePe already has the money.
export async function createPayment(body: Record<string, unknown>, userId: string, deps: Deps) {
  const now = deps.now?.() ?? Date.now();
  const [orderId, order] = await ownOrder(deps, body.order_id, userId);
  if (order.paymentStatus === "paid" || order.paymentStatus === "refunded") return await state(deps, orderId);
  if (order.status !== "pending_payment" || order.paymentMethod !== "online") {
    throw new PaymentError(409, "ORDER_NOT_PAYABLE", "This order can't be paid online.");
  }
  const until = ms(order.reservedUntil);
  if (!until || until <= now) throw new PaymentError(409, "ORDER_EXPIRED", "Payment time ran out. Place the order again.");

  if (order.phonepeOpen) {
    const open = await deps.db.get<Attempt>(`phonepeOrders/${order.phonepeOpen}`);
    if (open?.token) {
      const result = await settle(deps, order.phonepeOpen); // never a second PhonePe order while this one can still pay
      if (result === "paid" || result === "duplicate") return await state(deps, orderId);
      if (result === "pending") return reply(deps, order, open.phonepeOrderId!, open.token, until);
    } else if (open && now - open.createdAt < 60_000) {
      throw new PaymentError(409, "PAYMENT_IN_PROGRESS", "Your payment is being set up. Try again in a moment.");
    } else {
      await close(deps, orderId, order.phonepeOpen, now); // died before PhonePe answered: its token never left the server
    }
  }

  const merchantOrderId = `${order.number}-${(deps.newId?.() ?? randomUUID()).replace(/-/g, "").slice(0, 8)}`;
  const expireAfter = Math.min(3600, Math.max(300, Math.floor((until - now) / 1000))); // PhonePe's window: 5–60 minutes
  await deps.db.tx(async (tx) => {
    const o = await tx.get<Order>(`orders/${orderId}`);
    if (o?.phonepeOpen) throw new PaymentError(409, "PAYMENT_IN_PROGRESS", "Your payment is being set up. Try again in a moment.");
    tx.set(`phonepeOrders/${merchantOrderId}`, {
      orderId, amountPaise: order.totalPaise, state: "PENDING", phonepeOrderId: null, token: null,
      expiresAt: now + expireAfter * 1000, transactionId: null, createdAt: now, updatedAt: now,
    } satisfies Attempt);
    tx.update(`orders/${orderId}`, { phonepeOpen: merchantOrderId });
  });

  let made: { orderId?: string; token?: string; expireAt?: number };
  try {
    made = await deps.pp.call("/checkout/v2/sdk/order", {
      merchantOrderId,
      amount: order.totalPaise,
      expireAfter,
      metaInfo: { udf1: orderId, udf2: order.number },
      paymentFlow: { type: "PG_CHECKOUT" },
    });
    if (typeof made.orderId !== "string" || typeof made.token !== "string" || !made.token) {
      throw new Error("phonepe create order: no orderId/token");
    }
  } catch (e) {
    await close(deps, orderId, merchantOrderId, now);
    if (e instanceof PaymentError) throw new PaymentError(502, "GATEWAY_ERROR", "Payment service error. Try again.");
    throw e;
  }
  await deps.db.update(`phonepeOrders/${merchantOrderId}`, {
    phonepeOrderId: made.orderId, token: made.token, updatedAt: now,
    ...(Number.isFinite(made.expireAt) ? { expiresAt: made.expireAt } : {}),
  });
  return reply(deps, order, made.orderId, made.token, until);
}

// A PhonePe order whose token we never handed out: nobody can have paid it, so it is closed here (kept on record).
async function close(deps: Deps, orderId: string, merchantOrderId: string, now: number) {
  await deps.db.tx(async (tx) => {
    const [a, o] = [await tx.get<Attempt>(`phonepeOrders/${merchantOrderId}`), await tx.get<Order>(`orders/${orderId}`)];
    if (a?.state === "PENDING" && !a.token) tx.update(`phonepeOrders/${merchantOrderId}`, { state: "FAILED", updatedAt: now });
    if (o?.phonepeOpen === merchantOrderId) tx.update(`orders/${orderId}`, { phonepeOpen: null });
  });
}

const reply = (deps: Deps, order: Order, phonepeOrderId: string, token: string, until: number) => ({
  gateway: "phonepe",
  environment: deps.pp.environment, // the SDK's init must match the API host
  merchant_id: deps.pp.config.merchantId,
  phonepe_order_id: phonepeOrderId,
  token,
  order_number: order.number,
  amount: order.totalPaise,
  reserved_until: new Date(until).toISOString(),
});

// {order_id} -> {order_id, status, payment}: after the SDK closes (whatever it said), and when the order screen asks.
export async function checkPayment(body: Record<string, unknown>, userId: string, deps: Deps) {
  const [orderId, order] = await ownOrder(deps, body.order_id, userId);
  if (order.phonepeOpen && order.paymentStatus !== "paid" && order.paymentStatus !== "refunded") {
    const open = await deps.db.get<Attempt>(`phonepeOrders/${order.phonepeOpen}`);
    if (open?.token) await settle(deps, order.phonepeOpen);
  }
  return await state(deps, orderId);
}

// PhonePe webhook (HTTP, no Firebase auth): header check in constant time, then the facts from PhonePe's status APIs.
// -> [status, body]. Business refusals are acknowledged (200) so PhonePe stops retrying; anything else throws (500),
// and PhonePe retries.
export async function webhook(authorization: string | undefined, rawBody: string, creds: { username: string; password: string },
  deps: Deps): Promise<[number, { result: string }]> {
  if (!webhookAuthorized(authorization, creds.username, creds.password)) return [401, { result: "unauthorized" }];
  let body: { event?: unknown; type?: unknown; payload?: Record<string, unknown> } = {};
  try {
    body = JSON.parse(rawBody) ?? {};
  } catch { /* not JSON */ }
  // "checkout.order.completed", or the SDKs' type CHECKOUT_ORDER_COMPLETED for the same thing
  const event = typeof body.event === "string" ? body.event : typeof body.type === "string" ? body.type.toLowerCase().replace(/_/g, ".") : null;
  const payload = body.payload;
  if (!event || typeof payload !== "object" || !payload) return [400, { result: "bad_request" }];
  try {
    if (event.startsWith("checkout.order.") || event.startsWith("checkout.transaction.")) {
      const id = payload.merchantOrderId;
      if (typeof id !== "string" || !ID.test(id) || !(await deps.db.get(`phonepeOrders/${id}`))) return [200, { result: "unknown_order" }];
      return [200, { result: await settle(deps, id) }];
    }
    if (event.startsWith("pg.refund.")) {
      const id = payload.merchantRefundId;
      // a refund made in the PhonePe dashboard isn't ours: staff mark it by hand
      if (typeof id !== "string" || !ID.test(id) || !(await deps.db.get(`refunds/${id}`))) return [200, { result: "unknown_refund" }];
      return [200, { result: await settleRefund(deps, id, refundState(await refundStatus(deps, id))) }];
    }
    return [200, { result: "ignored" }];
  } catch (e) {
    if (e instanceof PaymentError && ["NOT_FOUND", "AMOUNT_MISMATCH"].includes(e.code)) return [200, { result: e.code.toLowerCase() }];
    throw e;
  }
}

// Refunds ----------------------------------------------------------------------------------------------------------

type Start = { refundId: string; amountPaise: number; merchantOrderId: string; retry: boolean };

const refundStatus = (deps: Deps, refundId: string) =>
  deps.pp.call<{ state?: string }>(`/payments/v2/refund/${encodeURIComponent(refundId)}/status`);
const refundState = (r: { state?: string }) => (r.state === "COMPLETED" ? "processed" : r.state === "FAILED" ? "failed" : "pending");

// What to refund, from the order. item_ids absent: everything not yet refunded (delivery included), only on a cancelled
// or delivered order. Otherwise those lines at what was paid for them (price × qty − their discount). A refund still
// in flight is handed back as it is, so a retry reuses its id and never pays out twice.
async function startRefund(deps: Deps, staffId: string, orderId: string, itemIds: string[] | null, restock: boolean): Promise<Start> {
  const now = deps.now?.() ?? Date.now();
  const refundId = deps.newId?.() ?? randomUUID();
  return await deps.db.tx(async (tx) => {
    const o = await tx.get<Order>(`orders/${orderId}`);
    if (!o) throw new PaymentError(404, "NOT_FOUND", "Order not found.");
    if (o.refundPending) {
      const r = await tx.get<Refund>(`refunds/${o.refundPending}`);
      if (r) return { refundId: o.refundPending, amountPaise: r.amountPaise, merchantOrderId: r.merchantOrderId, retry: true };
    }
    if (o.paymentStatus !== "paid" || o.payment?.gateway !== "phonepe") {
      throw new PaymentError(409, "REFUND_NOT_ALLOWED", "Only an order paid online, and not yet refunded, can be refunded here.");
    }
    const left = o.totalPaise - (o.refundedPaise ?? 0);
    const items = o.items ?? [];
    let lines: Item[];
    let amount: number;
    if (itemIds === null) {
      if (o.status !== "cancelled" && o.status !== "delivered") {
        throw new PaymentError(409, "REFUND_NOT_ALLOWED", "Cancel the order first, or refund single items.");
      }
      lines = items.filter((i) => !i.refundId);
      amount = left;
    } else {
      if (o.status === "cancelled") throw new PaymentError(409, "REFUND_NOT_ALLOWED", "A cancelled order is refunded in full.");
      lines = items.filter((i) => itemIds.includes(i.id) && !i.refundId);
      if (lines.length !== new Set(itemIds).size) throw new PaymentError(400, "BAD_REQUEST", "Pick items of this order that aren’t refunded yet.");
      amount = lines.reduce((sum, i) => sum + i.unitPricePaise * i.qty - (i.discountPaise ?? 0), 0);
    }
    if (amount < 100 || amount > left) throw new PaymentError(409, "REFUND_NOT_ALLOWED", "There’s nothing left to refund on this order.");

    tx.set(`refunds/${refundId}`, {
      orderId, amountPaise: amount, fullRefund: itemIds === null, itemIds: lines.map((i) => i.id),
      restock: restock && o.status !== "cancelled", // a cancel already restocked
      status: "pending", merchantOrderId: o.payment.merchantOrderId, failure: null, createdBy: staffId, createdAt: now, updatedAt: now,
    } satisfies Refund);
    const mine = new Set(lines.map((i) => i.id));
    tx.update(`orders/${orderId}`, { refundPending: refundId, items: items.map((i) => (mine.has(i.id) ? { ...i, refundId } : i)) });
    return { refundId, amountPaise: amount, merchantOrderId: o.payment.merchantOrderId, retry: false };
  });
}

// PhonePe's answer for one of our refunds. Idempotent: a settled refund stays as it is. Processed: refundedPaise, the
// timeline note, and once everything is paid back paymentStatus "refunded" (a delivered order becomes "refunded").
// Failed: the lines are free to refund again.
export async function settleRefund(deps: Deps, refundId: string, status: Refund["status"], failure: string | null = null): Promise<string> {
  const now = deps.now?.() ?? Date.now();
  return await deps.db.tx(async (tx) => {
    const r = await tx.get<Refund>(`refunds/${refundId}`);
    if (!r) throw new PaymentError(404, "NOT_FOUND", "Refund not found.");
    if (r.status !== "pending" || status === "pending") return r.status;
    const o = await tx.get<Order>(`orders/${r.orderId}`);
    if (!o) throw new PaymentError(404, "NOT_FOUND", "Order not found.");
    const done = { refundPending: o.refundPending === refundId ? null : o.refundPending ?? null };
    if (status === "failed") {
      const why = (failure ?? "").trim().slice(0, 300) || "PhonePe couldn’t complete it.";
      tx.update(`refunds/${refundId}`, { status, failure: why, updatedAt: now });
      tx.update(`orders/${r.orderId}`, { ...done, items: (o.items ?? []).map((i) => (i.refundId === refundId ? { ...i, refundId: null } : i)) });
      return "failed"; // staff see it on the refund; the customer's timeline only hears about money that moved
    }
    // shortcut: restock is recorded on the refund, not applied; the inventory code should act on processed refunds
    const refunded = (o.refundedPaise ?? 0) + r.amountPaise;
    const all = refunded >= o.totalPaise;
    tx.update(`refunds/${refundId}`, { status, updatedAt: now });
    tx.update(`orders/${r.orderId}`, {
      ...done, refundedPaise: refunded,
      ...(all ? { paymentStatus: "refunded", status: o.status === "delivered" ? "refunded" : o.status } : {}),
    });
    const what = r.fullRefund ? "" : ` for ${(o.items ?? []).filter((i) => i.refundId === refundId).map((i) => i.name ?? "an item").join(", ")}`;
    event(tx, r.orderId, all && o.status === "delivered" ? "refunded" : o.status,
      `Refund of ${inr(r.amountPaise)}${what} issued to your original payment method. Banks usually take 5–7 working days to show it.`, now);
    return "processed";
  });
}

// Definite "no" from PhonePe (bad request, unknown order); anything else may have gone through, so it stays pending.
const refused = (e: unknown) => e instanceof PhonePeError && (e.gatewayStatus === 400 || e.gatewayStatus === 404) &&
  !/duplicate|already|in progress/i.test(`${e.gatewayCode} ${e.description}`);

// {order_id, item_ids?, restock?} -> {refund_id, amount_paise, status, retry}. Staff only: the caller checks that.
// Our refund id is PhonePe's merchantRefundId; a retry asks PhonePe for that refund first, and sends it only if
// PhonePe has never heard of it.
export async function refund(body: Record<string, unknown>, staffId: string, deps: Deps) {
  const { order_id, item_ids = null, restock = false } = body;
  const items = item_ids === null || (Array.isArray(item_ids) && item_ids.length > 0 && item_ids.length <= 20 &&
    item_ids.every((i) => typeof i === "string" && ID.test(i)));
  if (typeof order_id !== "string" || !ID.test(order_id) || !items || typeof restock !== "boolean") {
    throw new PaymentError(400, "BAD_REQUEST", "order_id is required; item_ids is a list of order item ids.");
  }
  const start = await startRefund(deps, staffId, order_id, item_ids as string[] | null, restock);

  let ppState: { state?: string } | null = null;
  if (start.retry) {
    try {
      ppState = await refundStatus(deps, start.refundId);
    } catch (e) {
      if (!(e instanceof PhonePeError && (e.gatewayStatus === 400 || e.gatewayStatus === 404))) throw unconfirmed();
    }
  }
  if (!ppState) {
    try {
      ppState = await deps.pp.call<{ state?: string }>("/payments/v2/refund", {
        merchantRefundId: start.refundId, originalMerchantOrderId: start.merchantOrderId, amount: start.amountPaise,
      });
    } catch (e) {
      if (refused(e)) {
        const why = (e as PhonePeError).description || (e as PhonePeError).gatewayCode || "no reason given";
        await settleRefund(deps, start.refundId, "failed", why);
        throw new PaymentError(409, "REFUND_REFUSED", `PhonePe refused the refund: ${why}`);
      }
      throw unconfirmed();
    }
  }
  const status = await settleRefund(deps, start.refundId, refundState(ppState));
  return { refund_id: start.refundId, amount_paise: start.amountPaise, status, retry: start.retry };
}

const unconfirmed = () =>
  new PaymentError(502, "REFUND_UNCONFIRMED", "PhonePe didn't confirm the refund. Tap Refund again: it retries this same refund, never a second one.");
