import assert from "node:assert/strict";
import { test } from "node:test";
import { memoryDb } from "./db.js";
import { checkPayment, createPayment, type Deps, inr, refund, webhook } from "./payments.js";
import { PaymentError, phonePe } from "./phonepe.js";
import { type Call, CONFIG, fakeFetch, ok, refused, SANDBOX, token, TOKEN_URL } from "./testing.js";

const NOW = Date.UTC(2026, 10, 3, 10, 0, 0);
const MIN = 60_000;
const CREDS = { username: "shop", password: "pass word" };
const AUTH = "ecf65f2b38ae5fd07a5da70d523b45364b85eecfe88945635b4050dd21439062"; // sha256("shop:pass word")

const order = (over: Record<string, unknown> = {}) => ({
  userId: "u1", number: "SM100001", status: "pending_payment", paymentMethod: "online", paymentStatus: "pending",
  totalPaise: 129900, reservedUntil: NOW + 10 * MIN,
  items: [
    { id: "i1", name: "Galaxy A55", unitPricePaise: 60000, qty: 2, discountPaise: 5000 },
    { id: "i2", name: "Charger", unitPricePaise: 14900, qty: 1, discountPaise: 0 },
  ],
  ...over,
});

// PhonePe's side, as far as these functions can see it
function world(seed: Record<string, Record<string, unknown>> = { "orders/o1": order() }) {
  const pp = {
    orders: new Map<string, { state: string; amount: number; txn?: string }>(),
    refunds: new Map<string, { state: string; amount: number }>(),
    made: 0,
    fail: null as null | ((c: Call) => Response | Promise<Response> | null),
  };
  const f = fakeFetch(async (c) => {
    if (c.url === TOKEN_URL) return token();
    const hijack = pp.fail?.(c);
    if (hijack) return await hijack;
    const path = c.url.slice(SANDBOX.length);
    const body = c.body as Record<string, unknown>;
    if (path === "/checkout/v2/sdk/order") {
      pp.orders.set(body.merchantOrderId as string, { state: "PENDING", amount: body.amount as number });
      pp.made++;
      return ok({ orderId: `OMO${pp.made}`, state: "PENDING", expireAt: NOW + (body.expireAfter as number) * 1000, token: `tok${pp.made}` });
    }
    let m = path.match(/^\/checkout\/v2\/order\/([^/]+)\/status/);
    if (m) {
      const o = pp.orders.get(decodeURIComponent(m[1]));
      if (!o) return refused(404, "ORDER_NOT_FOUND", "No order");
      return ok({ state: o.state, amount: o.amount, paymentDetails: o.txn ? [{ transactionId: o.txn, state: "COMPLETED", amount: o.amount }] : [] });
    }
    if (path === "/payments/v2/refund") {
      pp.refunds.set(body.merchantRefundId as string, { state: "PENDING", amount: body.amount as number });
      return ok({ refundId: "OMR1", amount: body.amount, state: "PENDING" });
    }
    m = path.match(/^\/payments\/v2\/refund\/([^/]+)\/status$/);
    if (m) {
      const r = pp.refunds.get(decodeURIComponent(m[1]));
      return r ? ok(r) : refused(404, "REFUND_NOT_FOUND", "No refund");
    }
    return refused(404, "NO_ROUTE", path);
  });
  const db = memoryDb(seed);
  let ids = 0;
  const deps: Deps = { db, pp: phonePe(CONFIG, f.fetcher), now: () => NOW, newId: () => `id${++ids}aaaaaaaaaa` };
  const pay = (id = "o1", user = "u1") => createPayment({ order_id: id }, user, deps);
  const doc = <T = Record<string, unknown>>(path: string) => db.docs.get(path) as T;
  const events = (id = "o1") => db.under(`orders/${id}/events`).map(([, e]) => e.note);
  const hook = (event: string, payload: Record<string, unknown>, auth = AUTH) =>
    webhook(auth, JSON.stringify({ event, payload }), CREDS, deps);
  return { pp, f, db, deps, pay, doc, events, hook };
}

async function code(p: Promise<unknown>) {
  const e = await p.then(() => null, (x) => x);
  assert.ok(e instanceof PaymentError, `expected a PaymentError, got ${e}`);
  return [e.status, e.code];
}

test("inr: Indian grouping, paise only when there are any", () => {
  assert.deepEqual([inr(12999900), inr(4950), inr(100), inr(10000000)], ["₹1,29,999", "₹49.50", "₹1", "₹1,00,000"]);
});

// Starting a payment --------------------------------------------------------------------------------------------------

test("createPayment: refuses what can't be paid, before calling PhonePe", async () => {
  const w = world({
    "orders/o1": order(), "orders/cod": order({ paymentMethod: "cod", status: "confirmed" }),
    "orders/late": order({ reservedUntil: NOW - 1 }), "orders/gone": order({ status: "cancelled" }),
  });
  assert.deepEqual(await code(createPayment({}, "u1", w.deps)), [400, "BAD_REQUEST"]);
  assert.deepEqual(await code(createPayment({ order_id: "../x" }, "u1", w.deps)), [400, "BAD_REQUEST"]);
  assert.deepEqual(await code(w.pay("o1", "someone-else")), [404, "NOT_FOUND"]);
  assert.deepEqual(await code(w.pay("nope")), [404, "NOT_FOUND"]);
  assert.deepEqual(await code(w.pay("cod")), [409, "ORDER_NOT_PAYABLE"]);
  assert.deepEqual(await code(w.pay("gone")), [409, "ORDER_NOT_PAYABLE"]);
  assert.deepEqual(await code(w.pay("late")), [409, "ORDER_EXPIRED"]);
  assert.equal(w.f.api().length, 0);
});

test("createPayment: one PhonePe order for the order's own amount, window = the stock hold", async () => {
  const w = world();
  const r = await w.pay();
  assert.deepEqual(r, {
    gateway: "phonepe", environment: "SANDBOX", merchant_id: "PPFAKEMERCHANT", phonepe_order_id: "OMO1", token: "tok1",
    order_number: "SM100001", amount: 129900, reserved_until: new Date(NOW + 10 * MIN).toISOString(),
  });
  const [made] = w.f.api();
  assert.equal(made.url, `${SANDBOX}/checkout/v2/sdk/order`);
  assert.deepEqual(made.body, {
    merchantOrderId: "SM100001-id1aaaaa", amount: 129900, expireAfter: 600,
    metaInfo: { udf1: "o1", udf2: "SM100001" }, paymentFlow: { type: "PG_CHECKOUT" },
  });
  assert.equal(w.doc<{ phonepeOpen: string }>("orders/o1").phonepeOpen, "SM100001-id1aaaaa");
  assert.deepEqual(w.doc("phonepeOrders/SM100001-id1aaaaa"), {
    orderId: "o1", amountPaise: 129900, state: "PENDING", phonepeOrderId: "OMO1", token: "tok1", expiresAt: NOW + 10 * MIN,
    transactionId: null, createdAt: NOW, updatedAt: NOW,
  });
});

test("createPayment: PhonePe's window is never under 5 minutes or over an hour", async () => {
  const w = world({ "orders/o1": order({ reservedUntil: NOW + 2 * MIN }), "orders/o2": order({ number: "SM2", reservedUntil: NOW + 300 * MIN }) });
  await w.pay("o1");
  await w.pay("o2");
  assert.deepEqual(w.f.api().map((c) => (c.body as { expireAfter: number }).expireAfter), [300, 3600]);
});

test("createPayment again while PhonePe's order is open: the same token, never a second order", async () => {
  const w = world();
  await w.pay();
  const again = await w.pay();
  assert.equal((again as { token: string }).token, "tok1");
  assert.equal(w.pp.made, 1);
  assert.equal(w.f.api()[1].url, `${SANDBOX}/checkout/v2/order/SM100001-id1aaaaa/status?details=false`, "asked PhonePe first");
});

test("createPayment after the customer paid but before the webhook: it says paid, and the order is confirmed", async () => {
  const w = world();
  await w.pay();
  w.pp.orders.set("SM100001-id1aaaaa", { state: "COMPLETED", amount: 129900, txn: "OM1" });
  assert.deepEqual(await w.pay(), { order_id: "o1", status: "confirmed", payment: "paid" });
  assert.equal(w.pp.made, 1);
});

test("createPayment after PhonePe's order FAILED: a fresh PhonePe order", async () => {
  const w = world();
  await w.pay();
  w.pp.orders.set("SM100001-id1aaaaa", { state: "FAILED", amount: 129900 });
  const r = (await w.pay()) as { token: string };
  assert.equal(r.token, "tok2");
  assert.equal(w.doc<{ state: string }>("phonepeOrders/SM100001-id1aaaaa").state, "FAILED");
  assert.equal(w.doc<{ phonepeOpen: string }>("orders/o1").phonepeOpen, "SM100001-id2aaaaa");
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "failed", "the app can say the last try failed");
});

test("createPayment: PhonePe refuses or times out -> GATEWAY_ERROR, nothing left open, a retry works", async () => {
  const w = world();
  w.pp.fail = (c) => (c.url.endsWith("/sdk/order") ? refused(500, "INTERNAL_SERVER_ERROR", "down") : null);
  assert.deepEqual(await code(w.pay()), [502, "GATEWAY_ERROR"]);
  assert.equal(w.doc<{ phonepeOpen: unknown }>("orders/o1").phonepeOpen, null);
  assert.equal(w.doc<{ state: string }>("phonepeOrders/SM100001-id1aaaaa").state, "FAILED", "kept on record, closed");
  w.pp.fail = null;
  assert.equal(((await w.pay()) as { token: string }).token, "tok1");
});

test("createPayment: a PhonePe order still being made blocks for a minute, then is closed", async () => {
  const stuck = { orderId: "o1", amountPaise: 129900, state: "PENDING", phonepeOrderId: null, token: null, expiresAt: NOW + 5 * MIN,
    transactionId: null, updatedAt: NOW };
  const w = world({ "orders/o1": order({ phonepeOpen: "SM100001-stuck" }), "phonepeOrders/SM100001-stuck": { ...stuck, createdAt: NOW - 10_000 } });
  assert.deepEqual(await code(w.pay()), [409, "PAYMENT_IN_PROGRESS"]);
  assert.equal(w.f.api().length, 0);
  w.db.docs.set("phonepeOrders/SM100001-stuck", { ...stuck, createdAt: NOW - 2 * MIN });
  assert.equal(((await w.pay()) as { token: string }).token, "tok1");
  assert.equal(w.doc<{ state: string }>("phonepeOrders/SM100001-stuck").state, "FAILED");
});

test("two taps at once: one PhonePe order", async () => {
  const w = world();
  const results = await Promise.allSettled([w.pay(), w.pay()]);
  assert.equal(w.pp.made, 1);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const refusedOne = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
  assert.equal(refusedOne.reason.code, "PAYMENT_IN_PROGRESS");
});

// Confirming ---------------------------------------------------------------------------------------------------------

test("checkPayment: PhonePe's status decides, never the phone; repeats change nothing", async () => {
  const w = world();
  await w.pay();
  assert.deepEqual(await checkPayment({ order_id: "o1" }, "u1", w.deps), { order_id: "o1", status: "pending_payment", payment: "pending" });
  assert.deepEqual(await code(checkPayment({ order_id: "o1" }, "u2", w.deps)), [404, "NOT_FOUND"]);

  w.pp.orders.set("SM100001-id1aaaaa", { state: "COMPLETED", amount: 129900, txn: "OM9" });
  assert.deepEqual(await checkPayment({ order_id: "o1" }, "u1", w.deps), { order_id: "o1", status: "confirmed", payment: "paid" });
  const o = w.doc<Record<string, unknown>>("orders/o1");
  assert.deepEqual([o.reservedUntil, o.phonepeOpen, o.payment], [null, null,
    { gateway: "phonepe", merchantOrderId: "SM100001-id1aaaaa", transactionId: "OM9", amountPaise: 129900, at: NOW }]);
  await checkPayment({ order_id: "o1" }, "u1", w.deps);
  await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id1aaaaa", state: "COMPLETED" });
  assert.deepEqual(w.events(), ["Payment received"], "one timeline entry however often it is confirmed");
});

test("a different amount at PhonePe is never marked paid", async () => {
  const w = world();
  await w.pay();
  w.pp.orders.set("SM100001-id1aaaaa", { state: "COMPLETED", amount: 100, txn: "OM9" });
  assert.deepEqual(await code(checkPayment({ order_id: "o1" }, "u1", w.deps)), [409, "AMOUNT_MISMATCH"]);
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "pending");
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id1aaaaa" }), [200, { result: "amount_mismatch" }]);
});

test("paid after the order expired: the money is recorded and flagged for a refund", async () => {
  const w = world();
  await w.pay();
  w.db.docs.set("orders/o1", { ...w.doc("orders/o1"), status: "cancelled" }); // the expiry job ran
  w.pp.orders.set("SM100001-id1aaaaa", { state: "COMPLETED", amount: 129900, txn: "OM9" });
  assert.deepEqual((await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id1aaaaa" }))[1], { result: "paid" });
  assert.deepEqual([w.doc<{ status: string }>("orders/o1").status, w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus], ["cancelled", "paid"]);
  assert.deepEqual(w.events(), ["Payment received after cancellation. A refund is due."]);
});

test("money on a PhonePe order we closed still counts; a second payment is flagged", async () => {
  const w = world();
  await w.pay();
  w.pp.orders.set("SM100001-id1aaaaa", { state: "FAILED", amount: 129900 });
  await w.pay(); // a fresh one, SM100001-id2aaaaa
  w.pp.orders.set("SM100001-id1aaaaa", { state: "COMPLETED", amount: 129900, txn: "OMa" }); // late success at PhonePe
  w.pp.orders.set("SM100001-id2aaaaa", { state: "COMPLETED", amount: 129900, txn: "OMb" });
  assert.deepEqual((await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id1aaaaa" }))[1], { result: "paid" });
  assert.deepEqual((await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id2aaaaa" }))[1], { result: "duplicate" });
  assert.deepEqual(w.events(), ["Payment received",
    "A second payment of ₹1,299 came in through PhonePe (order SM100001-id2aaaaa). A refund is due."]);
});

// Webhook ----------------------------------------------------------------------------------------------------------

test("webhook: wrong or missing Authorization -> 401, and PhonePe isn't even asked", async () => {
  const w = world();
  await w.pay();
  const before = w.f.api().length;
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id1aaaaa" }, "0".repeat(64)), [401, { result: "unauthorized" }]);
  assert.deepEqual(await webhook(undefined, "{}", CREDS, w.deps), [401, { result: "unauthorized" }]);
  assert.equal(w.f.api().length, before);
});

test("webhook: the body is a hint; PhonePe's status API is the fact", async () => {
  const w = world();
  await w.pay();
  // a forged "completed" with the right header but no money at PhonePe
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id1aaaaa", state: "COMPLETED", amount: 129900 }),
    [200, { result: "pending" }]);
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "pending");
  w.pp.orders.set("SM100001-id1aaaaa", { state: "FAILED", amount: 129900 });
  assert.deepEqual(await w.hook("checkout.order.failed", { merchantOrderId: "SM100001-id1aaaaa" }), [200, { result: "failed" }]);
});

test("webhook: the SDKs' `type` form, unknown orders, junk and other events", async () => {
  const w = world();
  await w.pay();
  w.pp.orders.set("SM100001-id1aaaaa", { state: "COMPLETED", amount: 129900, txn: "OM1" });
  assert.deepEqual(await webhook(AUTH, JSON.stringify({ type: "CHECKOUT_ORDER_COMPLETED", payload: { merchantOrderId: "SM100001-id1aaaaa" } }), CREDS, w.deps),
    [200, { result: "paid" }]);
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: "SM999-x" }), [200, { result: "unknown_order" }]);
  assert.deepEqual(await w.hook("pg.refund.completed", { merchantRefundId: "not-ours" }), [200, { result: "unknown_refund" }]);
  assert.deepEqual(await w.hook("subscription.paused", {}), [200, { result: "ignored" }]);
  assert.deepEqual(await webhook(AUTH, "not json", CREDS, w.deps), [400, { result: "bad_request" }]);
});

test("webhook: PhonePe unreachable -> throws (500), so PhonePe retries", async () => {
  const w = world();
  await w.pay();
  w.pp.fail = () => Promise.reject(new TypeError("timed out"));
  assert.deepEqual(await code(w.hook("checkout.order.completed", { merchantOrderId: "SM100001-id1aaaaa" })), [502, "GATEWAY_ERROR"]);
});

// Refunds ----------------------------------------------------------------------------------------------------------

async function paid(w: ReturnType<typeof world>, status = "delivered") {
  await w.pay();
  w.pp.orders.set("SM100001-id1aaaaa", { state: "COMPLETED", amount: 129900, txn: "OM1" });
  await checkPayment({ order_id: "o1" }, "u1", w.deps);
  w.db.docs.set("orders/o1", { ...w.doc("orders/o1"), status });
}

test("refund: everything left, our id as merchantRefundId, settled by the webhook through PhonePe's refund status", async () => {
  const w = world();
  await paid(w);
  const r = await refund({ order_id: "o1" }, "staff1", w.deps);
  assert.deepEqual(r, { refund_id: "id2aaaaaaaaaa", amount_paise: 129900, status: "pending", retry: false });
  assert.deepEqual(w.f.api().at(-1)!.body, { merchantRefundId: "id2aaaaaaaaaa", originalMerchantOrderId: "SM100001-id1aaaaa", amount: 129900 });
  assert.equal(w.doc<{ refundPending: string }>("orders/o1").refundPending, "id2aaaaaaaaaa");

  w.pp.refunds.set("id2aaaaaaaaaa", { state: "COMPLETED", amount: 129900 });
  assert.deepEqual(await w.hook("pg.refund.completed", { merchantRefundId: "id2aaaaaaaaaa", state: "COMPLETED" }), [200, { result: "processed" }]);
  const o = w.doc<Record<string, unknown>>("orders/o1");
  assert.deepEqual([o.status, o.paymentStatus, o.refundedPaise, o.refundPending], ["refunded", "refunded", 129900, null]);
  assert.equal(w.events().at(-1), "Refund of ₹1,299 issued to your original payment method. Banks usually take 5–7 working days to show it.");
  assert.deepEqual(await w.hook("pg.refund.completed", { merchantRefundId: "id2aaaaaaaaaa" }), [200, { result: "processed" }], "repeat: no-op");
  assert.equal(w.events().length, 2);
});

test("refund items: what was paid for those lines; the order stays paid", async () => {
  const w = world();
  await paid(w, "confirmed");
  w.pp.fail = (c) => (c.url.endsWith("/payments/v2/refund") ? ok({ refundId: "OMR1", state: "COMPLETED" }) : null);
  const r = await refund({ order_id: "o1", item_ids: ["i1"], restock: true }, "staff1", w.deps);
  assert.deepEqual([r.amount_paise, r.status], [115000, "processed"]);
  const o = w.doc<{ paymentStatus: string; refundedPaise: number; items: { refundId?: string }[] }>("orders/o1");
  assert.deepEqual([o.paymentStatus, o.refundedPaise, o.items.map((i) => i.refundId ?? null)], ["paid", 115000, ["id2aaaaaaaaaa", null]]);
  assert.equal(w.doc<{ restock: boolean }>("refunds/id2aaaaaaaaaa").restock, true);
  assert.equal(w.events().at(-1), "Refund of ₹1,150 for Galaxy A55 issued to your original payment method. Banks usually take 5–7 working days to show it.");
  assert.deepEqual(await code(refund({ order_id: "o1", item_ids: ["i1"] }, "staff1", w.deps)), [400, "BAD_REQUEST"], "already refunded");
});

test("refund retry after a timeout: PhonePe is asked first, so it is never sent twice", async () => {
  // the first send reached PhonePe, but the reply was lost
  const w = world();
  await paid(w);
  w.pp.fail = (c) => {
    if (!c.url.endsWith("/payments/v2/refund")) return null;
    w.pp.refunds.set((c.body as { merchantRefundId: string }).merchantRefundId, { state: "PENDING", amount: 129900 });
    return Promise.reject(new TypeError("timed out"));
  };
  assert.deepEqual(await code(refund({ order_id: "o1" }, "staff1", w.deps)), [502, "REFUND_UNCONFIRMED"]);
  w.pp.fail = null;
  const r = await refund({ order_id: "o1" }, "staff1", w.deps);
  assert.deepEqual([r.refund_id, r.retry, r.status], ["id2aaaaaaaaaa", true, "pending"]);
  assert.equal(w.f.api().filter((c) => c.method === "POST" && c.url.endsWith("/payments/v2/refund")).length, 1);

  // the first send never reached PhonePe: the retry sends it, once
  const v = world();
  await paid(v);
  v.pp.fail = (c) => (c.url.endsWith("/payments/v2/refund") ? Promise.reject(new TypeError("timed out")) : null);
  await code(refund({ order_id: "o1" }, "staff1", v.deps));
  v.pp.fail = null;
  assert.equal((await refund({ order_id: "o1" }, "staff1", v.deps)).retry, true);
  assert.equal(v.pp.refunds.get("id2aaaaaaaaaa")?.amount, 129900);
});

test("refund refused by PhonePe: failed, PhonePe's reason for staff, lines free again", async () => {
  const w = world();
  await paid(w, "confirmed");
  w.pp.fail = (c) => (c.url.endsWith("/payments/v2/refund") ? refused(400, "INSUFFICIENT_BALANCE", "Not enough balance for this refund") : null);
  const e = await refund({ order_id: "o1", item_ids: ["i2"] }, "staff1", w.deps).catch((x) => x);
  assert.deepEqual([e.code, e.message], ["REFUND_REFUSED", "PhonePe refused the refund: Not enough balance for this refund"]);
  assert.deepEqual(w.doc("refunds/id2aaaaaaaaaa").status, "failed");
  const o = w.doc<{ refundPending: unknown; items: { refundId?: unknown }[] }>("orders/o1");
  assert.deepEqual([o.refundPending, o.items[1].refundId], [null, null]);
  // "duplicate" isn't a definite no: it stays pending for a safe retry
  w.pp.fail = (c) => (c.url.endsWith("/payments/v2/refund") ? refused(400, "DUPLICATE_REQUEST", "Duplicate merchantRefundId") : null);
  assert.deepEqual(await code(refund({ order_id: "o1", item_ids: ["i2"] }, "staff1", w.deps)), [502, "REFUND_UNCONFIRMED"]);
});

test("refund: only paid PhonePe orders; full refunds on cancelled or delivered ones; bad bodies", async () => {
  const w = world({ "orders/o1": order(), "orders/cod": order({ paymentMethod: "cod", status: "delivered", paymentStatus: "paid" }) });
  assert.deepEqual(await code(refund({ order_id: "o1" }, "staff1", w.deps)), [409, "REFUND_NOT_ALLOWED"], "unpaid");
  assert.deepEqual(await code(refund({ order_id: "cod" }, "staff1", w.deps)), [409, "REFUND_NOT_ALLOWED"], "cash");
  assert.deepEqual(await code(refund({ order_id: "nope" }, "staff1", w.deps)), [404, "NOT_FOUND"]);
  for (const body of [{}, { order_id: "o1", item_ids: [] }, { order_id: "o1", item_ids: "i1" }, { order_id: "o1", restock: "yes" }]) {
    assert.deepEqual(await code(refund(body, "staff1", w.deps)), [400, "BAD_REQUEST"], JSON.stringify(body));
  }
  const v = world();
  await paid(v, "confirmed");
  assert.deepEqual(await code(refund({ order_id: "o1" }, "staff1", v.deps)), [409, "REFUND_NOT_ALLOWED"], "cancel first");
  assert.equal(v.f.api().filter((c) => c.url.includes("/refund")).length, 0);
});
