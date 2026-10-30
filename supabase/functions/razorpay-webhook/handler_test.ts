import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { hmacSha256Hex } from "../_shared/crypto.ts";
import { handleWebhook, type Store } from "./handler.ts";

const SECRET = "whsec_test";
const ORDER = { id: "0b8f5a3e-1111-4222-8333-944445555666", total_paise: 54900 };

function fakeStore(rpcError: string | null = null) {
  const seen = new Set<string>();
  const state = { rpcError, calls: [] as [string, Record<string, unknown>][], forgotten: [] as string[] };
  const store: Store = {
    async recordEvent(id) {
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    },
    async forgetEvent(id) {
      seen.delete(id);
      state.forgotten.push(id);
    },
    async findOrder(rzp, id) {
      return rzp === "order_RZP1" || id === ORDER.id ? ORDER : null;
    },
    async rpc(fn, args) {
      // refunds made in the Razorpay dashboard aren't in our refunds table
      if (fn === "settle_refund" && args.p_refund_id === null && args.p_razorpay_refund_id !== "rfnd_ours") return "NOT_FOUND";
      state.calls.push([fn, args]);
      return state.rpcError;
    },
  };
  return Object.assign(state, { store });
}

async function post(store: Store, body: unknown, { eventId = "evt_1", signature }: { eventId?: string; signature?: string } = {}) {
  const raw = JSON.stringify(body);
  const req = new Request("http://localhost/razorpay-webhook", {
    method: "POST",
    headers: { "x-razorpay-event-id": eventId, "x-razorpay-signature": signature ?? await hmacSha256Hex(SECRET, raw) },
    body: raw,
  });
  const res = await handleWebhook(req, SECRET, store);
  return { status: res.status, body: await res.json() };
}

const captured = (amount = ORDER.total_paise) => ({
  event: "payment.captured",
  payload: { payment: { entity: { id: "pay_1", order_id: "order_RZP1", amount, status: "captured", notes: {} } } },
});

Deno.test("bad or missing signature -> 401, nothing recorded", async () => {
  const { store, calls } = fakeStore();
  assertEquals((await post(store, captured(), { signature: "0".repeat(64) })).status, 401);
  assertEquals((await post(store, captured(), { signature: "" })).status, 401);
  assertEquals(calls, []);
});

Deno.test("signature is over the exact raw body", async () => {
  const { store } = fakeStore();
  const raw = JSON.stringify(captured());
  const req = new Request("http://x", {
    method: "POST",
    headers: { "x-razorpay-event-id": "evt_1", "x-razorpay-signature": await hmacSha256Hex(SECRET, raw) },
    body: raw + " ", // same JSON, different bytes
  });
  assertEquals((await handleWebhook(req, SECRET, store)).status, 401);
});

Deno.test("payment.captured marks the order paid", async () => {
  const { store, calls } = fakeStore();
  const res = await post(store, captured());
  assertEquals(res, { status: 200, body: { result: "paid" } });
  assertEquals(calls, [["mark_order_paid", { p_order_id: ORDER.id, p_razorpay_payment_id: "pay_1" }]]);
});

Deno.test("duplicate event id -> 200 without reprocessing", async () => {
  const { store, calls } = fakeStore();
  await post(store, captured());
  assertEquals(await post(store, captured()), { status: 200, body: { result: "duplicate" } });
  assertEquals(calls.length, 1);
});

Deno.test("order.paid finds the order via notes when the Razorpay id is unknown", async () => {
  const { store, calls } = fakeStore();
  const res = await post(store, {
    event: "order.paid",
    payload: {
      payment: { entity: { id: "pay_2", order_id: "order_OTHER", amount: ORDER.total_paise } },
      order: { entity: { id: "order_OTHER", notes: { order_id: ORDER.id } } },
    },
  });
  assertEquals(res.body.result, "paid");
  assertEquals(calls[0][1].p_razorpay_payment_id, "pay_2");
});

Deno.test("amount mismatch is acknowledged but not marked paid", async () => {
  const { store, calls } = fakeStore();
  assertEquals(await post(store, captured(100)), { status: 200, body: { result: "amount_mismatch" } });
  assertEquals(calls, []);
});

Deno.test("unknown order and unknown event types -> 200", async () => {
  const { store, calls } = fakeStore();
  const stranger = captured();
  stranger.payload.payment.entity.order_id = "order_NOPE";
  assertEquals((await post(store, stranger)).body.result, "unknown_order");
  assertEquals(await post(store, { event: "payout.processed", payload: {} }, { eventId: "evt_2" }), { status: 200, body: { result: "ignored" } });
  assertEquals(calls, []);
});

Deno.test("payment.failed marks the payment failed", async () => {
  const { store, calls } = fakeStore();
  const res = await post(store, { event: "payment.failed", payload: { payment: { entity: { id: "pay_3", order_id: "order_RZP1" } } } });
  assertEquals(res.body.result, "failed");
  assertEquals(calls, [["mark_payment_failed", { p_order_id: ORDER.id }]]);
});

Deno.test("refund.processed: full refund marks refunded, partial is skipped", async () => {
  const { store, calls } = fakeStore();
  const refund = (refunded: number) => ({
    event: "refund.processed",
    payload: {
      refund: { entity: { id: "rfnd_1", payment_id: "pay_1", amount: refunded } },
      payment: { entity: { id: "pay_1", amount: 54900, amount_refunded: refunded } },
    },
  });
  assertEquals((await post(store, refund(1000), { eventId: "evt_a" })).body.result, "partial_refund");
  assertEquals((await post(store, refund(54900), { eventId: "evt_b" })).body.result, "refunded");
  assertEquals(calls, [["mark_order_refunded", { p_razorpay_payment_id: "pay_1" }]]);
});

Deno.test("refund.processed without the payment totals is not taken as a full refund", async () => {
  const { store, calls } = fakeStore();
  const refund = { id: "rfnd_2", payment_id: "pay_1", amount: 54900 };
  assertEquals((await post(store, { event: "refund.processed", payload: { refund: { entity: refund } } }, { eventId: "evt_c" })).body.result, "partial_refund");
  const noRefunded = { refund: { entity: refund }, payment: { entity: { id: "pay_1", amount: 54900 } } };
  assertEquals((await post(store, { event: "refund.processed", payload: noRefunded }, { eventId: "evt_d" })).body.result, "partial_refund");
  assertEquals(calls, []);
});

Deno.test("business error from the RPC is acknowledged", async () => {
  const { store, forgotten } = fakeStore("NOT_FOUND");
  assertEquals(await post(store, captured()), { status: 200, body: { result: "not_found" } });
  assertEquals(forgotten, []);
});

Deno.test("infrastructure error forgets the event so Razorpay's retry runs", async () => {
  const fake = fakeStore("TypeError: fetch failed");
  await assertRejects(() => post(fake.store, captured()));
  assertEquals(fake.forgotten, ["evt_1"]);
  fake.rpcError = null; // DB back up; same event id retried
  assertEquals((await post(fake.store, captured())).body.result, "paid");
});

Deno.test("signed but malformed body -> 400", async () => {
  const { store } = fakeStore();
  const req = new Request("http://x", {
    method: "POST",
    headers: { "x-razorpay-event-id": "evt_1", "x-razorpay-signature": await hmacSha256Hex(SECRET, "not json") },
    body: "not json",
  });
  assertEquals((await handleWebhook(req, SECRET, store)).status, 400);
});

const REFUND_ID = "0b8f5a3e-1111-4222-8333-944445555777";
const ourRefund = (event: string, notes: Record<string, string> = { refund_id: REFUND_ID }) => ({
  event,
  payload: {
    refund: { entity: { id: "rfnd_1", payment_id: "pay_1", amount: 1000, speed_processed: "instant", notes } },
    payment: { entity: { id: "pay_1", amount: 54900, amount_refunded: 1000 } },
  },
});

Deno.test("refund.processed / refund.failed for a refund made in the app -> settle_refund", async () => {
  const { store, calls } = fakeStore();
  assertEquals((await post(store, ourRefund("refund.processed"), { eventId: "evt_r1" })).body.result, "refund_processed");
  assertEquals((await post(store, ourRefund("refund.failed"), { eventId: "evt_r2" })).body.result, "refund_failed");
  assertEquals(calls, [
    ["settle_refund", { p_refund_id: REFUND_ID, p_razorpay_refund_id: "rfnd_1", p_status: "processed", p_speed: "instant" }],
    ["settle_refund", { p_refund_id: REFUND_ID, p_razorpay_refund_id: "rfnd_1", p_status: "failed", p_speed: "instant" }],
  ]);
});

Deno.test("a refund without our id is found by Razorpay's id; junk ids are ignored", async () => {
  const { store, calls } = fakeStore();
  const byRazorpayId = ourRefund("refund.processed", { refund_id: "not-a-uuid" });
  byRazorpayId.payload.refund.entity.id = "rfnd_ours";
  assertEquals((await post(store, byRazorpayId)).body.result, "refund_processed");
  assertEquals(calls[0][1].p_refund_id, null);
  assertEquals((await post(store, ourRefund("refund.failed", {}), { eventId: "evt_r3" })).body.result, "unknown_refund");
});

Deno.test("payment_link.paid -> mark_link_paid with the payment's amount; closed links", async () => {
  const { store, calls } = fakeStore();
  const paid = (amount: unknown) => ({
    event: "payment_link.paid",
    payload: {
      payment_link: { entity: { id: "plink_1", amount: 44900, status: "paid", notes: { link_id: REFUND_ID } } },
      payment: { entity: { id: "pay_9", amount, order_id: "order_LINK", notes: { link_id: REFUND_ID } } },
      order: { entity: { id: "order_LINK" } },
    },
  });
  assertEquals((await post(store, paid(44900), { eventId: "evt_l1" })).body.result, "link_paid");
  assertEquals((await post(store, paid("44900"), { eventId: "evt_l2" })).body.result, "amount_mismatch");
  assertEquals((await post(store, { event: "payment_link.expired", payload: { payment_link: { entity: { id: "plink_2" } } } }, { eventId: "evt_l3" })).body.result, "link_expired");
  assertEquals((await post(store, { event: "payment_link.cancelled", payload: { payment_link: { entity: { id: "plink_3" } } } }, { eventId: "evt_l4" })).body.result, "link_cancelled");
  assertEquals((await post(store, { event: "payment_link.paid", payload: {} }, { eventId: "evt_l5" })).body.result, "ignored");
  assertEquals(calls, [
    ["mark_link_paid", { p_razorpay_link_id: "plink_1", p_razorpay_payment_id: "pay_9", p_amount_paise: 44900 }],
    ["close_payment_link", { p_razorpay_link_id: "plink_2", p_status: "expired" }],
    ["close_payment_link", { p_razorpay_link_id: "plink_3", p_status: "cancelled" }],
  ]);
});

Deno.test("a link's payment.captured is left to payment_link.paid (no order_id in its notes)", async () => {
  const { store, calls } = fakeStore();
  const res = await post(store, { event: "payment.captured", payload: { payment: { entity: {
    id: "pay_9", order_id: "order_LINK", amount: 44900, notes: { link_id: REFUND_ID, shop_order_id: ORDER.id } } } } });
  assertEquals(res.body.result, "unknown_order");
  assertEquals(calls, []);
});

Deno.test("payment.dispute.* -> record_dispute; an empty dispute is ignored", async () => {
  const { store, calls } = fakeStore();
  const res = await post(store, { event: "payment.dispute.created", payload: { dispute: { entity: {
    id: "disp_1", payment_id: "pay_1", amount: 54900, status: "open", phase: "chargeback", reason_code: "fraudulent",
    reason_description: "Card holder says they didn't buy it", respond_by: 1793961000 } } } });
  assertEquals(res.body.result, "dispute");
  assertEquals(calls, [["record_dispute", { p_id: "disp_1", p_payment_id: "pay_1", p_amount_paise: 54900, p_status: "open",
    p_phase: "chargeback", p_reason_code: "fraudulent", p_reason: "Card holder says they didn't buy it",
    p_respond_by: "2026-11-06T10:30:00.000Z" }]]);
  assertEquals((await post(store, { event: "payment.dispute.won", payload: {} }, { eventId: "evt_d2" })).body.result, "ignored");
});
