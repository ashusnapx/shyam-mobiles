import assert from "node:assert/strict";
import { test } from "node:test";
import { fakeGateway } from "./fake_gateway.js";
import { createPayment, type Deps, phonepeWebhook, startRefund, verifyPayment } from "./flows.js";
import { GatewayError } from "./gateway.js";
import { PaymentError } from "./service.js";
import { fakeFirestore, fakeSettlement } from "./testing.js";

const NOW = Date.UTC(2026, 10, 3, 10, 0, 0);
const MIN = 60_000;
const CREDS = { username: "shop", password: "pass word" };
const AUTH = "ecf65f2b38ae5fd07a5da70d523b45364b85eecfe88945635b4050dd21439062"; // sha256("shop:pass word")
const MID = "SM100001-aaaaaaaa"; // the first PhonePe order id these tests make
const MID2 = "SM100001-bbbbbbbb";

const order = (over: Record<string, unknown> = {}) => ({
  uid: "u1", number: "SM100001", status: "pending_payment", paymentMethod: "online", paymentStatus: "pending",
  totalPaise: 129900, reservedUntil: new Date(NOW + 10 * MIN), events: [],
  items: [
    { id: "v1", productName: "Galaxy A55", unitPricePaise: 60000, qty: 2, discountPaise: 5000 },
    { id: "v2", productName: "Charger", unitPricePaise: 14900, qty: 1, discountPaise: 0 },
  ],
  ...over,
});

function world(seed: Record<string, Record<string, unknown>> = { "orders/o1": order() }) {
  const fs = fakeFirestore(seed);
  const pp = fakeGateway();
  const settlement = fakeSettlement(NOW);
  const randoms = ["aaaaaaaa-1111", "bbbbbbbb-2222", "cccccccc-3333", "dddddddd-4444"];
  const deps: Deps = { db: fs.firestore, gateway: pp.gateway, settlement: settlement.make(fs.firestore), now: () => NOW, random: () => randoms.shift()! };
  const doc = <T = Record<string, unknown>>(path: string) => fs.db.docs.get(path) as T;
  const pay = (id = "o1", uid = "u1") => createPayment({ orderId: id }, uid, deps);
  const hook = (event: string, payload: Record<string, unknown>, auth = AUTH) => phonepeWebhook(auth, JSON.stringify({ event, payload }), CREDS, deps);
  const completed = (mid = MID, amountPaise = 129900, transactionId = "OM1") =>
    pp.orders.set(mid, { state: "completed", amountPaise, transactionId });
  return { fs, pp, settlement, deps, doc, pay, hook, completed };
}

async function reason(p: Promise<unknown>) {
  const e = await p.then(() => null, (x) => x);
  assert.ok(e instanceof PaymentError, `expected a PaymentError, got ${e}`);
  return e.reason;
}

// createPayment ------------------------------------------------------------------------------------------------------

test("createPayment: refuses what can't be paid, before PhonePe is asked", async () => {
  const w = world({
    "orders/o1": order(), "orders/cod": order({ paymentMethod: "cod", status: "confirmed" }),
    "orders/late": order({ reservedUntil: new Date(NOW - 1) }), "orders/gone": order({ status: "cancelled" }),
  });
  assert.equal(await reason(createPayment({}, "u1", w.deps)), "BAD_REQUEST");
  assert.equal(await reason(createPayment({ orderId: "../x" }, "u1", w.deps)), "BAD_REQUEST");
  assert.equal(await reason(w.pay("o1", "someone-else")), "NOT_FOUND");
  assert.equal(await reason(w.pay("nope")), "NOT_FOUND");
  assert.equal(await reason(w.pay("cod")), "ORDER_NOT_PAYABLE");
  assert.equal(await reason(w.pay("gone")), "ORDER_NOT_PAYABLE");
  assert.equal(await reason(w.pay("late")), "ORDER_EXPIRED");
  assert.deepEqual(w.pp.calls, []);
});

test("createPayment: a PhonePe order for the order's own total, window = the stock hold", async () => {
  const w = world();
  assert.deepEqual(await w.pay(), { merchantId: "PPFAKEMERCHANT", token: "tok1", orderId: "OMO1", env: "SANDBOX" });
  assert.deepEqual(w.pp.calls, [`createOrder ${MID}`]);
  assert.deepEqual(w.pp.orders.get(MID), { state: "pending", amountPaise: 129900, transactionId: null });
  assert.deepEqual(w.doc(`orders/o1/payments/${MID}`), {
    state: "pending", amountPaise: 129900, phonepeOrderId: "OMO1", token: "tok1", expireAt: new Date(NOW + 10 * MIN),
    transactionId: null, createdAt: new Date(NOW), updatedAt: new Date(NOW),
  });
});

test("createPayment again while PhonePe's order is open: the same token after asking PhonePe, never a second order", async () => {
  const w = world();
  await w.pay();
  assert.deepEqual(await w.pay(), { merchantId: "PPFAKEMERCHANT", token: "tok1", orderId: "OMO1", env: "SANDBOX" });
  assert.deepEqual(w.pp.calls, [`createOrder ${MID}`, `orderStatus ${MID}`]);
});

test("createPayment after the customer paid, before the webhook: {paid: true} and the order is settled", async () => {
  const w = world();
  await w.pay();
  w.completed();
  assert.deepEqual(await w.pay(), { paid: true });
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "paid");
  assert.equal(w.pp.made, 1);
});

test("createPayment after PhonePe's order FAILED: a fresh one", async () => {
  const w = world();
  await w.pay();
  w.pp.orders.set(MID, { state: "failed", amountPaise: 129900, transactionId: null });
  assert.equal((await w.pay() as { token: string }).token, "tok2");
  assert.equal(w.doc<{ state: string }>(`orders/o1/payments/${MID}`).state, "failed");
  assert.equal(w.doc<{ state: string }>(`orders/o1/payments/${MID2}`).state, "pending");
});

test("createPayment: PhonePe refuses or times out -> GATEWAY_ERROR, the attempt closed, a retry works", async () => {
  const w = world();
  w.pp.fail = (m) => (m === "createOrder" ? new GatewayError(0, "UNREACHABLE", "timed out") : null);
  assert.equal(await reason(w.pay()), "GATEWAY_ERROR");
  assert.equal(w.doc<{ state: string }>(`orders/o1/payments/${MID}`).state, "failed");
  w.pp.fail = null;
  assert.equal((await w.pay() as { token: string }).token, "tok1");
});

test("createPayment: an attempt still being made blocks for a minute, then is closed", async () => {
  const stuck = { state: "pending", amountPaise: 129900, phonepeOrderId: null, token: null, expireAt: new Date(NOW), transactionId: null };
  const w = world({ "orders/o1": order(), "orders/o1/payments/SM100001-99999999": { ...stuck, createdAt: new Date(NOW - 10_000) } });
  assert.equal(await reason(w.pay()), "PAYMENT_IN_PROGRESS");
  assert.deepEqual(w.pp.calls, []);
  w.fs.db.docs.set("orders/o1/payments/SM100001-99999999", { ...stuck, createdAt: new Date(NOW - 2 * MIN) });
  assert.equal((await w.pay() as { token: string }).token, "tok1");
  assert.equal(w.doc<{ state: string }>("orders/o1/payments/SM100001-99999999").state, "failed");
});

test("two taps at once: one PhonePe order", async () => {
  const w = world();
  const results = await Promise.allSettled([w.pay(), w.pay()]);
  assert.equal(w.pp.made, 1);
  const refusedOne = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
  assert.equal(refusedOne.reason.reason, "PAYMENT_IN_PROGRESS");
});

// verifyPayment ------------------------------------------------------------------------------------------------------

test("verifyPayment: PhonePe's status decides, never the phone", async () => {
  const w = world();
  await w.pay();
  assert.deepEqual(await verifyPayment({ orderId: "o1" }, "u1", w.deps), { status: "pending_payment", paymentStatus: "pending" });
  assert.equal(await reason(verifyPayment({ orderId: "o1" }, "u2", w.deps)), "NOT_FOUND");
  w.completed();
  assert.deepEqual(await verifyPayment({ orderId: "o1" }, "u1", w.deps), { status: "confirmed", paymentStatus: "paid" });
  assert.deepEqual(w.settlement.calls, [`payment ${MID} pending`, `payment ${MID} completed`]);
  await verifyPayment({ orderId: "o1" }, "u1", w.deps);
  assert.equal(w.settlement.calls.length, 2, "a paid order isn't checked again");
});

test("verifyPayment: the settlement's refusal (an amount that doesn't match) reaches the app", async () => {
  const w = world();
  await w.pay();
  w.completed(MID, 100);
  assert.equal(await reason(verifyPayment({ orderId: "o1" }, "u1", w.deps)), "AMOUNT_MISMATCH");
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "pending");
});

// phonepeWebhook ---------------------------------------------------------------------------------------------------

test("webhook: wrong or missing Authorization -> 401, and PhonePe isn't even asked", async () => {
  const w = world();
  await w.pay();
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: MID }, "0".repeat(64)), [401, { result: "unauthorized" }]);
  assert.deepEqual(await phonepeWebhook(undefined, "{}", CREDS, w.deps), [401, { result: "unauthorized" }]);
  assert.deepEqual(w.pp.calls, [`createOrder ${MID}`]);
});

test("webhook: the body is a hint; PhonePe's status API is the fact", async () => {
  const w = world();
  await w.pay();
  // a forged "completed" with the right header but no money at PhonePe
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: MID, state: "COMPLETED", amount: 129900 }),
    [200, { result: "settled" }]);
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "pending");
  w.completed();
  await w.hook("checkout.order.completed", { merchantOrderId: MID });
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "paid");
});

test("webhook: the SDKs' `type` form; unknown ids, junk and other events are acknowledged", async () => {
  const w = world();
  await w.pay();
  w.completed();
  assert.deepEqual(await phonepeWebhook(AUTH, JSON.stringify({ type: "CHECKOUT_ORDER_COMPLETED", payload: { merchantOrderId: MID } }), CREDS, w.deps),
    [200, { result: "settled" }]);
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: "SM999999-aaaaaaaa" }), [200, { result: "unknown_order" }]);
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: "SM100001-cafecafe" }), [200, { result: "unknown_order" }]);
  assert.deepEqual(await w.hook("pg.refund.completed", { merchantRefundId: "dashboard-refund" }), [200, { result: "unknown_refund" }]);
  assert.deepEqual(await w.hook("subscription.paused", {}), [200, { result: "ignored" }]);
  assert.deepEqual(await phonepeWebhook(AUTH, "not json", CREDS, w.deps), [400, { result: "bad_request" }]);
});

test("webhook: an amount mismatch is acknowledged; PhonePe unreachable throws, so PhonePe retries", async () => {
  const w = world();
  await w.pay();
  w.completed(MID, 100);
  assert.deepEqual(await w.hook("checkout.order.completed", { merchantOrderId: MID }), [200, { result: "amount_mismatch" }]);
  w.pp.fail = () => new GatewayError(0, "UNREACHABLE", "timed out");
  assert.equal(await reason(w.hook("checkout.order.completed", { merchantOrderId: MID })), "GATEWAY_ERROR");
});

// startRefund ------------------------------------------------------------------------------------------------------

async function paid(w: ReturnType<typeof world>, status = "delivered") {
  await w.pay();
  w.completed();
  await verifyPayment({ orderId: "o1" }, "u1", w.deps);
  w.fs.db.docs.set("orders/o1", { ...w.doc("orders/o1"), status });
}
const RID = "SM100001-Rbbbbbbb"; // the refund id after paid() used the first random

test("startRefund: everything left, our id as merchantRefundId, then the webhook settles it via refund status", async () => {
  const w = world();
  await paid(w);
  assert.deepEqual(await startRefund({ orderId: "o1" }, "staff1", w.deps), { refundId: RID, amountPaise: 129900, status: "pending", retry: false });
  assert.deepEqual(w.pp.refunds.get(RID), { state: "pending", gatewayRefundId: "OMR1", amountPaise: 129900 });
  assert.deepEqual(w.doc(`orders/o1/refunds/${RID}`), {
    amountPaise: 129900, fullRefund: true, restock: false, status: "pending", gatewayRefundId: null, failure: null,
    createdBy: "staff1", createdAt: new Date(NOW), updatedAt: new Date(NOW),
  });
  const o = w.doc<{ pendingRefundId: string; items: { refundId?: string }[] }>("orders/o1");
  assert.deepEqual([o.pendingRefundId, o.items.map((i) => i.refundId)], [RID, [RID, RID]]);

  w.pp.refunds.set(RID, { state: "completed", gatewayRefundId: "OMR1", amountPaise: 129900 });
  assert.deepEqual(await w.hook("pg.refund.completed", { merchantRefundId: RID }), [200, { result: "settled" }]);
  assert.equal(w.doc<{ status: string }>(`orders/o1/refunds/${RID}`).status, "processed");
  assert.equal(w.doc<{ paymentStatus: string }>("orders/o1").paymentStatus, "refunded");
});

test("startRefund items: what was paid for those lines; restock recorded", async () => {
  const w = world();
  await paid(w, "confirmed");
  const r = await startRefund({ orderId: "o1", itemIds: ["v1"], restock: true }, "staff1", w.deps);
  assert.deepEqual([r.amountPaise, r.status], [115000, "pending"]);
  assert.equal(w.doc<{ restock: boolean }>(`orders/o1/refunds/${RID}`).restock, true);
  assert.deepEqual(w.doc<{ items: { refundId?: string }[] }>("orders/o1").items.map((i) => i.refundId ?? null), [RID, null]);
});

test("startRefund retry after a lost reply: PhonePe is asked first, so it is sent once", async () => {
  const w = world();
  await paid(w);
  w.pp.fail = (m, id) => {
    if (m !== "refund") return null;
    w.pp.refunds.set(id, { state: "pending", gatewayRefundId: "OMR1", amountPaise: 129900 }); // it reached PhonePe
    return new GatewayError(0, "UNREACHABLE", "timed out");
  };
  assert.equal(await reason(startRefund({ orderId: "o1" }, "staff1", w.deps)), "REFUND_UNCONFIRMED");
  w.pp.fail = null;
  assert.deepEqual(await startRefund({ orderId: "o1" }, "staff1", w.deps), { refundId: RID, amountPaise: 129900, status: "pending", retry: true });
  assert.equal(w.pp.calls.filter((c) => c.startsWith("refund ")).length, 1);

  // the first send never reached PhonePe: the retry sends it, once
  const v = world();
  await paid(v);
  v.pp.fail = (m) => (m === "refund" ? new GatewayError(0, "UNREACHABLE", "timed out") : null);
  await reason(startRefund({ orderId: "o1" }, "staff1", v.deps));
  v.pp.fail = null;
  assert.equal((await startRefund({ orderId: "o1" }, "staff1", v.deps)).retry, true);
  assert.deepEqual(v.pp.calls.filter((c) => c.startsWith("refund")), [`refund ${RID}`, `refundStatus ${RID}`, `refund ${RID}`]);
  assert.equal(v.pp.refunds.get(RID)?.amountPaise, 129900);
});

test("startRefund refused by PhonePe: settled failed with PhonePe's reason; 'duplicate' is not a refusal", async () => {
  const w = world();
  await paid(w, "confirmed");
  w.pp.fail = (m) => (m === "refund" ? new GatewayError(400, "INSUFFICIENT_BALANCE", "Not enough balance for this refund") : null);
  const e = await startRefund({ orderId: "o1", itemIds: ["v2"] }, "staff1", w.deps).catch((x) => x);
  assert.deepEqual([e.reason, e.message], ["REFUND_REFUSED", "PhonePe refused the refund: Not enough balance for this refund"]);
  assert.deepEqual(w.settlement.calls.at(-1), `refund ${RID} failed`);
  assert.equal(w.doc<{ failure: string }>(`orders/o1/refunds/${RID}`).failure, "Not enough balance for this refund");

  w.pp.fail = (m) => (m === "refund" ? new GatewayError(400, "DUPLICATE_REQUEST", "Duplicate merchantRefundId") : null);
  assert.equal(await reason(startRefund({ orderId: "o1", itemIds: ["v2"] }, "staff1", w.deps)), "REFUND_UNCONFIRMED");
});

test("startRefund: only PhonePe-paid orders, full refunds on cancelled or delivered ones, bad bodies", async () => {
  const w = world({ "orders/o1": order(), "orders/cod": order({ paymentMethod: "cod", status: "delivered", paymentStatus: "paid" }) });
  assert.equal(await reason(startRefund({ orderId: "o1" }, "staff1", w.deps)), "REFUND_NOT_ALLOWED");
  assert.equal(await reason(startRefund({ orderId: "cod" }, "staff1", w.deps)), "REFUND_NOT_ALLOWED");
  assert.equal(await reason(startRefund({ orderId: "nope" }, "staff1", w.deps)), "NOT_FOUND");
  for (const body of [{}, { orderId: "o1", itemIds: [] }, { orderId: "o1", itemIds: "v1" }, { orderId: "o1", restock: "yes" }]) {
    assert.equal(await reason(startRefund(body, "staff1", w.deps)), "BAD_REQUEST", JSON.stringify(body));
  }
  const v = world();
  await paid(v, "confirmed");
  assert.equal(await reason(startRefund({ orderId: "o1" }, "staff1", v.deps)), "REFUND_NOT_ALLOWED", "cancel first");
  assert.deepEqual(v.pp.calls.filter((c) => c.startsWith("refund")), []);
});
