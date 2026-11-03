import assert from "node:assert/strict";
import { test } from "node:test";
import { GatewayError } from "./gateway.js";
import { phonePeGateway, webhookAuthorized } from "./phonepe.js";
import { CONFIG, fakeFetch, ok, refused, SANDBOX, token, TOKEN_URL } from "./testing.js";

const STATUS = `${SANDBOX}/checkout/v2/order/SM100001-a1b2c3d4/status?details=false`;
const api = (reply: (url: string, body: unknown) => Response | Promise<Response>) =>
  fakeFetch((c) => (c.url === TOKEN_URL ? token() : reply(c.url, c.body)));

test("client-credentials token, sent as O-Bearer, reused until half its life", async () => {
  const f = api(() => ok({ state: "PENDING", amount: 100 }));
  const pp = phonePeGateway(CONFIG, f.fetcher);
  await pp.orderStatus("SM100001-a1b2c3d4");
  await pp.orderStatus("SM100001-a1b2c3d4");
  assert.deepEqual(f.calls.map((c) => `${c.method} ${c.url}`), [`POST ${TOKEN_URL}`, `GET ${STATUS}`, `GET ${STATUS}`]);
  assert.equal(f.calls[0]!.headers.get("content-type"), "application/x-www-form-urlencoded");
  assert.deepEqual(f.calls[0]!.body, { client_id: "pp_client_fake", client_version: "1", client_secret: "pp_secret_fake", grant_type: "client_credentials" });
  assert.equal(f.calls[1]!.headers.get("authorization"), "O-Bearer pp_access_fake");
});

test("a token past half its life is renewed", async () => {
  const now = Math.floor(Date.now() / 1000);
  const f = fakeFetch((c) => (c.url === TOKEN_URL ? ok({ access_token: "old", issued_at: now - 3000, expires_at: now + 600 }) : ok({})));
  const pp = phonePeGateway(CONFIG, f.fetcher);
  await pp.orderStatus("SM100001-a1b2c3d4");
  await pp.orderStatus("SM100001-a1b2c3d4");
  assert.equal(f.calls.filter((c) => c.url === TOKEN_URL).length, 2);
});

test("production hosts only for PRODUCTION; anything else is refused at start", async () => {
  const f = fakeFetch((c) => (c.url.endsWith("/oauth/token") ? token() : ok({ refundId: "OMR1", state: "PENDING" })));
  const pp = phonePeGateway({ ...CONFIG, env: "PRODUCTION" }, f.fetcher);
  await pp.refund({ merchantRefundId: "SM1-Rabc", merchantOrderId: "SM1-a", amountPaise: 100 });
  assert.deepEqual(f.calls.map((c) => c.url), [
    "https://api.phonepe.com/apis/identity-manager/v1/oauth/token", "https://api.phonepe.com/apis/pg/payments/v2/refund",
  ]);
  assert.equal(pp.env, "PRODUCTION");
  assert.throws(() => phonePeGateway({ ...CONFIG, env: "sandbox" }), /PHONEPE_ENV must be SANDBOX or PRODUCTION/);
  assert.throws(() => phonePeGateway({ ...CONFIG, clientSecret: "" }), /Missing PhonePe setting clientSecret/);
});

test("createOrder: PhonePe's request and reply shapes", async () => {
  const f = api(() => ok({ orderId: "OMO1", state: "PENDING", expireAt: 1_800_000_000_000, token: "tok1" }));
  const made = await phonePeGateway(CONFIG, f.fetcher).createOrder({
    merchantOrderId: "SM100001-a1b2c3d4", amountPaise: 129900, expireAfterSeconds: 600, orderId: "o1", orderNumber: "SM100001",
  });
  assert.deepEqual(made, { phonepeOrderId: "OMO1", token: "tok1", expireAt: new Date(1_800_000_000_000) });
  assert.equal(f.calls[1]!.url, `${SANDBOX}/checkout/v2/sdk/order`);
  assert.deepEqual(f.calls[1]!.body, {
    merchantOrderId: "SM100001-a1b2c3d4", amount: 129900, expireAfter: 600,
    metaInfo: { udf1: "o1", udf2: "SM100001" }, paymentFlow: { type: "PG_CHECKOUT" },
  });
  const empty = api(() => ok({ orderId: "OMO1", token: "" }));
  assert.equal((await phonePeGateway(CONFIG, empty.fetcher).createOrder({
    merchantOrderId: "x", amountPaise: 100, expireAfterSeconds: 300, orderId: "o", orderNumber: "SM1",
  }).catch((e) => e)).code, "BAD_REPLY");
});

test("orderStatus: lowercased state, the amount, the transaction that paid", async () => {
  const f = api(() => ok({
    state: "COMPLETED", amount: 129900,
    paymentDetails: [{ transactionId: "OMx", state: "FAILED" }, { transactionId: "OM1", state: "COMPLETED", amount: 129900 }],
  }));
  assert.deepEqual(await phonePeGateway(CONFIG, f.fetcher).orderStatus("SM100001-a1b2c3d4"),
    { state: "completed", amountPaise: 129900, transactionId: "OM1" });
  const odd = api(() => ok({ state: "SOMETHING_NEW", amount: 1.5 }));
  assert.deepEqual(await phonePeGateway(CONFIG, odd.fetcher).orderStatus("x"), { state: "pending", amountPaise: null, transactionId: null },
    "an unknown state is never treated as paid");
});

test("refund and refundStatus; a refund PhonePe never heard of is null", async () => {
  const f = api((url) => (url.endsWith("/status") ? refused(404, "REFUND_NOT_FOUND", "no") : ok({ refundId: "OMR1", amount: 100, state: "PENDING" })));
  const pp = phonePeGateway(CONFIG, f.fetcher);
  assert.equal(await pp.refundStatus("SM1-Rabc"), null);
  assert.deepEqual(await pp.refund({ merchantRefundId: "SM1-Rabc", merchantOrderId: "SM1-a", amountPaise: 100 }),
    { state: "pending", gatewayRefundId: "OMR1" });
  assert.deepEqual(f.calls[2]!.body, { merchantRefundId: "SM1-Rabc", originalMerchantOrderId: "SM1-a", amount: 100 });
  const done = api(() => ok({ refundId: "OMR1", state: "COMPLETED" }));
  assert.deepEqual(await phonePeGateway(CONFIG, done.fetcher).refundStatus("SM1-Rabc"), { state: "completed", gatewayRefundId: "OMR1" });
  const down = api(() => refused(500, "INTERNAL_SERVER_ERROR", "down"));
  assert.equal((await phonePeGateway(CONFIG, down.fetcher).refundStatus("x").catch((e) => e)).status, 500, "an outage isn't 'never heard of it'");
});

test("a 401 renews the token once, then gives up", async () => {
  let n = 0;
  const f = fakeFetch((c) => (c.url === TOKEN_URL ? token(`t${++n}`) : refused(401, "UNAUTHORIZED", "no")));
  const err = await phonePeGateway(CONFIG, f.fetcher).orderStatus("x").catch((e) => e);
  assert.ok(err instanceof GatewayError);
  assert.deepEqual([err.status, err.code], [401, "UNAUTHORIZED"]);
  assert.deepEqual(f.calls.map((c) => c.headers.get("authorization") ?? "token"), ["token", "O-Bearer t1", "token", "O-Bearer t2"]);
});

test("errors keep PhonePe's status, code and message; unreachable is status 0; definite only for 400/404", async () => {
  const f = api(() => refused(400, "BAD_REQUEST", "Invalid amount"));
  const err = await phonePeGateway(CONFIG, f.fetcher).refund({ merchantRefundId: "a", merchantOrderId: "b", amountPaise: 1 }).catch((e) => e);
  assert.deepEqual([err.status, err.code, err.description, err.definite], [400, "BAD_REQUEST", "Invalid amount", true]);
  const down = fakeFetch(() => Promise.reject(new TypeError("timed out")));
  const gone = await phonePeGateway(CONFIG, down.fetcher).orderStatus("x").catch((e) => e);
  assert.deepEqual([gone.status, gone.code, gone.definite], [0, "UNREACHABLE", false]);
  assert.equal(new GatewayError(400, "DUPLICATE_REQUEST", "Duplicate merchantRefundId").definite, false);
  assert.equal(new GatewayError(500, "X", "y").definite, false);
});

test("webhookAuthorized: exact hex SHA-256 of username:password", () => {
  // known answer: printf 'shop:pass word' | shasum -a 256
  const hex = "ecf65f2b38ae5fd07a5da70d523b45364b85eecfe88945635b4050dd21439062";
  assert.ok(webhookAuthorized(hex, "shop", "pass word"));
  assert.ok(!webhookAuthorized(hex, "shop", "pass"));
  assert.ok(!webhookAuthorized(hex.toUpperCase(), "shop", "pass word"));
  assert.ok(!webhookAuthorized(`SHA256 ${hex}`, "shop", "pass word"));
  assert.ok(!webhookAuthorized(undefined, "shop", "pass word"));
  assert.ok(!webhookAuthorized("", "", ""), "no credentials configured: nothing gets in");
});
