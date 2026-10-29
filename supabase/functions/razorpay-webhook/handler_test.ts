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
