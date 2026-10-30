import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/http.ts";
import { fakeFetch, ok, refused } from "../_shared/fake_fetch.ts";
import type { Rpc, RpcError } from "../_shared/supabase.ts";
import { refund } from "./handler.ts";

const ORDER = "0b8f5a3e-1111-4222-8333-944445555666";
const ITEM = "0b8f5a3e-1111-4222-8333-944445555777";
const REFUND = "0b8f5a3e-1111-4222-8333-944445555888";
const STAFF = "0b8f5a3e-1111-4222-8333-944445555999";

function fakeDb(startError: RpcError | null = null) {
  const calls: [string, Record<string, unknown>][] = [];
  const rpc: Rpc = async (fn, args) => {
    calls.push([fn, args]);
    if (fn === "admin_start_refund") {
      return startError ? { data: null, error: startError } : {
        data: { refund_id: REFUND, amount_paise: 55000, payment_id: "pay_1", instant: args.p_instant, order_number: "SM100001", retry: false },
        error: null,
      };
    }
    return { data: args.p_status, error: null };
  };
  return { rpc, calls };
}

async function status(p: Promise<unknown>) {
  const e = await assertRejects(() => p, HttpError);
  return [e.status, e.code, e.message];
}

Deno.test("bad bodies -> 400 before anything else", async () => {
  const { rpc, calls } = fakeDb();
  for (const body of [{}, { order_id: "x" }, { order_id: ORDER, item_ids: [] }, { order_id: ORDER, item_ids: ["x"] },
    { order_id: ORDER, item_ids: ITEM }, { order_id: ORDER, restock: "yes" }, { order_id: ORDER, instant: 1 }]) {
    assertEquals((await status(refund(body, STAFF, rpc)))[0], 400, JSON.stringify(body));
  }
  assertEquals(calls, []);
});

Deno.test("partial refund: database amount, idempotency key, settled from Razorpay's reply", async () => {
  const { rpc, calls } = fakeDb();
  const fake = fakeFetch(() => ok({ id: "rfnd_1", status: "processed", speed_processed: "normal" }));
  try {
    const res = await refund({ order_id: ORDER, item_ids: [ITEM], restock: true }, STAFF, rpc);
    assertEquals(await res.json(), { refund_id: REFUND, amount_paise: 55000, status: "processed", retry: false });
    assertEquals(calls[0], ["admin_start_refund", { p_staff: STAFF, p_order_id: ORDER, p_items: [ITEM], p_restock: true, p_instant: false }]);
    const [call] = fake.calls;
    assertEquals(call.url, "https://api.razorpay.com/v1/payments/pay_1/refund");
    assertEquals(call.headers.get("x-refund-idempotency"), REFUND);
    assertEquals(call.body, { amount: 55000, speed: "normal", receipt: REFUND, notes: { order_id: ORDER, order_number: "SM100001", refund_id: REFUND } });
    assertEquals(calls[1], ["settle_refund", { p_refund_id: REFUND, p_razorpay_refund_id: "rfnd_1", p_status: "processed", p_speed: "normal" }]);
  } finally {
    fake.restore();
  }
});

Deno.test("instant asks for speed optimum; a pending reply stays pending", async () => {
  const { rpc, calls } = fakeDb();
  const fake = fakeFetch(() => ok({ id: "rfnd_2", status: "pending" }));
  try {
    const res = await refund({ order_id: ORDER, instant: true }, STAFF, rpc);
    assertEquals((await res.json()).status, "pending");
    assertEquals((fake.calls[0].body as Record<string, unknown>).speed, "optimum");
    assertEquals(calls[0][1].p_items, null, "no item_ids: a full refund");
    assertEquals(calls[1][1].p_status, "pending");
  } finally {
    fake.restore();
  }
});

Deno.test("Razorpay says no -> refund failed (lines freed), staff see the reason", async () => {
  const { rpc, calls } = fakeDb();
  const fake = fakeFetch(() => refused(400, "Your account does not have enough balance to carry out the refund operation."));
  try {
    assertEquals(await status(refund({ order_id: ORDER }, STAFF, rpc)),
      [409, "REFUND_REFUSED", "Razorpay refused the refund: Your account does not have enough balance to carry out the refund operation."]);
    assertEquals(calls[1], ["settle_refund", { p_refund_id: REFUND, p_razorpay_refund_id: null, p_status: "failed",
      p_failure: "Your account does not have enough balance to carry out the refund operation." }]);
  } finally {
    fake.restore();
  }
});

Deno.test("a payment id Razorpay can't route (404) is a definite no too", async () => {
  const { rpc, calls } = fakeDb();
  const fake = fakeFetch(() => Response.json({ message: "no Route matched with those values" }, { status: 404 }));
  try {
    assertEquals(await status(refund({ order_id: ORDER }, STAFF, rpc)),
      [409, "REFUND_REFUSED", "Razorpay refused the refund: no Route matched with those values"]);
    assertEquals(calls[1][1].p_status, "failed");
  } finally {
    fake.restore();
  }
});

Deno.test("timeout, 5xx or 'in progress' -> left pending for a safe retry", async () => {
  for (const reply of [() => Promise.reject(new TypeError("timed out")), () => refused(500, "oops"),
    () => refused(400, "Request failed because another payment operation is in progress."), () => refused(409, "same key in flight")]) {
    const { rpc, calls } = fakeDb();
    const fake = fakeFetch(reply);
    try {
      assertEquals((await status(refund({ order_id: ORDER }, STAFF, rpc)))[0], 502);
      assertEquals(calls.map(([fn]) => fn), ["admin_start_refund"], "not settled");
    } finally {
      fake.restore();
    }
  }
});

Deno.test("business refusals from the database keep their staff copy", async () => {
  const { rpc } = fakeDb({ message: "REFUND_NOT_ALLOWED", details: "Cancel the order first, or refund single items." });
  const fake = fakeFetch(() => ok({}));
  try {
    assertEquals(await status(refund({ order_id: ORDER }, STAFF, rpc)), [409, "REFUND_NOT_ALLOWED", "Cancel the order first, or refund single items."]);
    assertEquals(fake.calls, []);
    const forbidden = fakeDb({ message: "FORBIDDEN" });
    assertEquals((await status(refund({ order_id: ORDER }, STAFF, forbidden.rpc)))[0], 403);
  } finally {
    fake.restore();
  }
});
