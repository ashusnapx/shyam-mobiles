import assert from "node:assert/strict";
import { test } from "node:test";
import { expireAfterSeconds, merchantOrderId, merchantRefundId, orderNumberOf, PaymentError, planRefund, type RefundableOrder } from "./service.js";

const MIN = 60_000;

test("expireAfterSeconds: the hold left, within PhonePe's 5–60 minutes", () => {
  assert.equal(expireAfterSeconds(10 * MIN, 0), 600);
  assert.equal(expireAfterSeconds(2 * MIN, 0), 300);
  assert.equal(expireAfterSeconds(300 * MIN, 0), 3600);
});

test("merchant ids carry the order number, and only ours parse back", () => {
  assert.equal(merchantOrderId("SM100001", "3fa2b9c1d4e5"), "SM100001-3fa2b9c1");
  assert.equal(merchantRefundId("SM100001", "3fa2b9c1d4e5"), "SM100001-R3fa2b9c");
  assert.equal(orderNumberOf("SM100001-3fa2b9c1"), "SM100001");
  assert.equal(orderNumberOf("SM100001-R3fa2b9c"), "SM100001");
  for (const bad of ["SM100001", "XX100001-3fa2b9c1", "SM100001-3fa2b9c1/../x", "SM100001-ZZZZZZZZ", 42, null]) {
    assert.equal(orderNumberOf(bad), null, String(bad));
  }
});

const order = (over: Partial<RefundableOrder> = {}): RefundableOrder => ({
  status: "delivered", paymentStatus: "paid", totalPaise: 129900,
  payment: { gateway: "phonepe", merchantOrderId: "SM100001-3fa2b9c1" },
  items: [
    { id: "v1", unitPricePaise: 60000, qty: 2, discountPaise: 5000 },
    { id: "v2", unitPricePaise: 14900, qty: 1, discountPaise: 0 },
  ],
  ...over,
});
const reason = (f: () => unknown) => {
  try {
    f();
  } catch (e) {
    assert.ok(e instanceof PaymentError);
    return e.reason;
  }
  assert.fail("expected a refusal");
};

test("planRefund: everything left on a delivered or cancelled order, delivery included", () => {
  assert.deepEqual(planRefund(order(), 0, null), { amountPaise: 129900, lineIds: ["v1", "v2"], fullRefund: true, merchantOrderId: "SM100001-3fa2b9c1" });
  assert.equal(planRefund(order({ status: "cancelled" }), 14900, null).amountPaise, 115000, "less what was refunded already");
  assert.equal(reason(() => planRefund(order({ status: "confirmed" }), 0, null)), "REFUND_NOT_ALLOWED");
});

test("planRefund: lines at what was paid for them; never twice, never past what's left", () => {
  assert.deepEqual(planRefund(order({ status: "confirmed" }), 0, ["v1"]).amountPaise, 115000, "2 × ₹600 − ₹50 off");
  const once = order({ items: [{ id: "v1", unitPricePaise: 60000, qty: 2, discountPaise: 5000, refundId: "SM1-Rx" },
    { id: "v2", unitPricePaise: 14900, qty: 1, discountPaise: 0 }] });
  assert.equal(reason(() => planRefund(once, 0, ["v1"])), "BAD_REQUEST");
  assert.equal(reason(() => planRefund(order(), 0, ["nope"])), "BAD_REQUEST");
  assert.equal(reason(() => planRefund(order({ status: "cancelled" }), 0, ["v1"])), "REFUND_NOT_ALLOWED");
  assert.equal(reason(() => planRefund(order(), 129900, null)), "REFUND_NOT_ALLOWED", "nothing left");
  assert.equal(reason(() => planRefund(order(), 129000, ["v1"])), "REFUND_NOT_ALLOWED", "more than what's left");
});

test("planRefund: only orders PhonePe was paid for", () => {
  assert.equal(reason(() => planRefund(order({ paymentStatus: "pending" }), 0, null)), "REFUND_NOT_ALLOWED");
  assert.equal(reason(() => planRefund(order({ paymentStatus: "refunded" }), 0, null)), "REFUND_NOT_ALLOWED");
  assert.equal(reason(() => planRefund(order({ payment: null }), 0, null)), "REFUND_NOT_ALLOWED", "COD or marked paid by hand");
});
