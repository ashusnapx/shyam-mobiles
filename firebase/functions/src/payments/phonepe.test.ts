import assert from "node:assert/strict";
import { test } from "node:test";
import { PaymentError, phonePe, PhonePeError, webhookAuthorized } from "./phonepe.js";
import { CONFIG, fakeFetch, ok, refused, SANDBOX, token, TOKEN_URL } from "./testing.js";

const STATUS = "/checkout/v2/order/SM1-a/status";

test("client-credentials token, sent as O-Bearer, reused until half its life", async () => {
  const f = fakeFetch((c) => (c.url === TOKEN_URL ? token() : ok({ state: "PENDING" })));
  const pp = phonePe(CONFIG, f.fetcher);
  assert.deepEqual(await pp.call(STATUS), { state: "PENDING" });
  await pp.call(STATUS);
  assert.deepEqual(f.calls.map((c) => `${c.method} ${c.url}`), [`POST ${TOKEN_URL}`, `GET ${SANDBOX}${STATUS}`, `GET ${SANDBOX}${STATUS}`]);
  assert.equal(f.calls[0].headers.get("content-type"), "application/x-www-form-urlencoded");
  assert.deepEqual(f.calls[0].body, { client_id: "pp_client_fake", client_version: "1", client_secret: "pp_secret_fake", grant_type: "client_credentials" });
  assert.equal(f.calls[1].headers.get("authorization"), "O-Bearer pp_access_fake");
  assert.equal(pp.environment, "SANDBOX");
});

test("a token past half its life is renewed", async () => {
  const now = Math.floor(Date.now() / 1000);
  const f = fakeFetch((c) => (c.url === TOKEN_URL ? ok({ access_token: "old", issued_at: now - 3000, expires_at: now + 600 }) : ok({})));
  const pp = phonePe(CONFIG, f.fetcher);
  await pp.call(STATUS);
  await pp.call(STATUS);
  assert.equal(f.calls.filter((c) => c.url === TOKEN_URL).length, 2);
});

test("production hosts only for env production; anything else is refused at start", async () => {
  const f = fakeFetch((c) => (c.url.endsWith("/oauth/token") ? token() : ok({})));
  const pp = phonePe({ ...CONFIG, env: "production" }, f.fetcher);
  await pp.call("/payments/v2/refund", { amount: 100 });
  assert.deepEqual(f.calls.map((c) => c.url), [
    "https://api.phonepe.com/apis/identity-manager/v1/oauth/token", "https://api.phonepe.com/apis/pg/payments/v2/refund",
  ]);
  assert.equal(pp.environment, "PRODUCTION");
  assert.throws(() => phonePe({ ...CONFIG, env: "live" }), /PHONEPE_ENV must be sandbox or production/);
  assert.throws(() => phonePe({ ...CONFIG, clientSecret: "" }), /Missing PhonePe setting clientSecret/);
});

test("a 401 renews the token once, then gives up", async () => {
  let n = 0;
  const f = fakeFetch((c) => (c.url === TOKEN_URL ? token(`t${++n}`) : refused(401, "UNAUTHORIZED", "no")));
  const err = await phonePe(CONFIG, f.fetcher).call(STATUS).catch((x) => x);
  assert.ok(err instanceof PhonePeError);
  assert.deepEqual([err.status, err.code, err.gatewayStatus, err.gatewayCode], [502, "GATEWAY_ERROR", 401, "UNAUTHORIZED"]);
  assert.deepEqual(f.calls.map((c) => c.headers.get("authorization") ?? "token"), ["token", "O-Bearer t1", "token", "O-Bearer t2"]);
});

test("error replies keep PhonePe's code and message; unreachable is a plain 502", async () => {
  const f = fakeFetch((c) => (c.url === TOKEN_URL ? token() : refused(400, "BAD_REQUEST", "Invalid amount")));
  const err = await phonePe(CONFIG, f.fetcher).call("/payments/v2/refund", {}).catch((x) => x);
  assert.deepEqual([err.gatewayStatus, err.gatewayCode, err.description], [400, "BAD_REQUEST", "Invalid amount"]);

  const down = fakeFetch(() => Promise.reject(new TypeError("timed out")));
  const gone = await phonePe(CONFIG, down.fetcher).call(STATUS).catch((x) => x);
  assert.ok(gone instanceof PaymentError && !(gone instanceof PhonePeError));
  assert.equal(gone.status, 502);

  const badClient = fakeFetch(() => refused(400, "INVALID_CLIENT", "bad client"));
  assert.equal((await phonePe(CONFIG, badClient.fetcher).call(STATUS).catch((x) => x)).gatewayCode, "INVALID_CLIENT");
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
