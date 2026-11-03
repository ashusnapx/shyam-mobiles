import type { CallableRequest } from "firebase-functions/v2/https";
import { beforeEach, expect, test } from "vitest";
import * as orders from "../../src/orders/handlers.js";
import { settleOnlinePayment, settleRefund } from "../../src/orders/settlement.js";
import { fakeGateway } from "../../src/payments/fake_gateway.js";
import { createPayment, startRefund, verifyPayment } from "../../src/payments/flows.js";
import { db } from "../../src/shared/db.js";

// A whole sale on the Firestore emulator, engineer C's handlers with engineer D's payment flows and fake PhonePe:
// quote → place (online) → pay → pack → ship → deliver → full refund, and quote → place (COD) → deliver → paid.

const host = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
const as = (uid: string, role?: string) => (data: unknown) => ({
  data, rawRequest: {},
  auth: { uid, token: { uid, auth_time: Date.now() / 1000, firebase: { sign_in_provider: "google.com", ...(role ? { sign_in_second_factor: "totp" } : {}) }, ...(role ? { role } : {}) } },
}) as unknown as CallableRequest;
const alice = as("alice");
const staff = as("staff", "staff");
const order = async (id: string) => (await db().doc(`orders/${id}`).get()).data()!;
const stock = async () => (await db().doc("variants/v1").get()).get("stock") as number;

beforeEach(async () => {
  await fetch(`http://${host}/emulator/v1/projects/${process.env.GCLOUD_PROJECT ?? "demo-shyam-mobiles"}/databases/(default)/documents`, { method: "DELETE" });
  const seed: Record<string, Record<string, unknown>> = {
    "settings/store": { deliveryFeePaise: 4900, freeDeliveryMinPaise: 99900, codEnabled: true, codMaxPaise: 2500000, onlinePaymentEnabled: true,
      referral: { enabled: true, friendPaise: 20000, rewardPaise: 20000, minOrderPaise: 199900, monthlyCap: 10 } },
    "users/alice": { fullName: "Alice" },
    "users/staff": { fullName: "Staff", role: "staff" },
    "users/alice/addresses/a0": { name: "Alice", phone: "+919876543210", line1: "1 Rajeev Complex", city: "Waidhan", state: "Madhya Pradesh", stateCode: "23", pincode: "486886", label: "home" },
    "products/phone": { name: "Phone", brandId: "b", brandName: "B", categoryId: "c", categoryKind: "phone", gstRateBp: 1800, isActive: true, images: [] },
    "variants/v1": { productId: "phone", productName: "Phone", sku: "P-1", name: "8 GB", pricePaise: 50000, mrpPaise: 50000, stock: 5, isActive: true, productActive: true },
    "carts/alice": { lines: { v1: { qty: 2, addedAt: new Date() } } },
  };
  const batch = db().batch();
  for (const [path, d] of Object.entries(seed)) batch.set(db().doc(path), d);
  await batch.commit();
});

test("online: quote, place, pay with PhonePe, ship, deliver, refund in full", async () => {
  const pg = fakeGateway();
  const deps = { db: db(), gateway: pg.gateway, settlement: { settleOnlinePayment, settleRefund } };
  expect(await orders.quoteOrder.run(alice({ paymentMethod: "online" }))).toMatchObject({ subtotalPaise: 100000, deliveryFeePaise: 0, totalPaise: 100000 });
  const { orderId } = await orders.placeOrder.run(alice({ addressId: "a0", paymentMethod: "online" }));
  expect(await stock()).toBe(3);
  expect(await order(orderId)).toMatchObject({ status: "pending_payment", number: "SM100001", totalPaise: 100000 });

  const pay = await createPayment({ orderId }, "alice", deps);
  expect(pay).toMatchObject({ merchantId: "PPFAKEMERCHANT", token: "tok1" });
  const [mid] = [...pg.orders.keys()];
  pg.orders.set(mid!, { state: "completed", amountPaise: 100000, transactionId: "TX1" });
  expect(await verifyPayment({ orderId }, "alice", deps)).toEqual({ status: "confirmed", paymentStatus: "paid" });

  for (const status of ["packed", "shipped", "delivered"] as const) await orders.adminUpdateOrder.run(staff({ orderId, status, ...(status === "shipped" ? { courier: "Delhivery", trackingNumber: "DL1" } : {}) }));
  expect(await order(orderId)).toMatchObject({ status: "delivered", paymentStatus: "paid", courier: "Delhivery" });

  const refund = await startRefund({ orderId }, "staff", deps);
  expect(refund).toMatchObject({ amountPaise: 100000, status: "pending", retry: false });
  pg.refunds.set(refund.refundId, { ...pg.refunds.get(refund.refundId)!, state: "completed" });
  await db().runTransaction((tx) => settleRefund(tx, orderId, refund.refundId, { state: "completed", gatewayRefundId: "OMR1", failure: null }));
  const done = await order(orderId);
  expect(done).toMatchObject({ status: "refunded", paymentStatus: "refunded", pendingRefundId: null });
  expect((done.events as { note?: string }[]).at(-1)?.note).toBe("Refund of ₹1,000 issued to your original payment method. Banks usually take 5–7 working days to show it.");
  expect(await stock()).toBe(3); // a full refund restocks only when staff ask
});

test("cash on delivery: confirmed at once, paid when delivered, and a second order is numbered next", async () => {
  const { orderId } = await orders.placeOrder.run(alice({ addressId: "a0", paymentMethod: "cod" }));
  expect(await order(orderId)).toMatchObject({ status: "confirmed", paymentStatus: "pending", reservedUntil: null });
  for (const status of ["packed", "shipped", "delivered"] as const) await orders.adminUpdateOrder.run(staff({ orderId, status }));
  expect(await order(orderId)).toMatchObject({ status: "delivered", paymentStatus: "paid" });
  await db().doc("carts/alice").set({ lines: { v1: { qty: 1, addedAt: new Date() } } });
  const second = await orders.placeOrder.run(alice({ addressId: "a0", paymentMethod: "cod" }));
  expect(await order(second.orderId)).toMatchObject({ number: "SM100002" });
  await orders.cancelOrder.run(alice({ orderId: second.orderId }));
  expect(await stock()).toBe(3);
});
