import { assertEquals } from "jsr:@std/assert@1";
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { handleSendSms } from "./handler.ts";
import { msg91Sender } from "./msg91.ts";

const raw = btoa("0123456789abcdef0123456789abcdef");
const secret = `v1,whsec_${raw}`;

function signed(body: unknown, key = raw): Request {
  const payload = JSON.stringify(body);
  const id = "msg_1";
  const ts = new Date();
  const signature = new Webhook(key).sign(id, ts, payload);
  return new Request("http://x/send-sms", {
    method: "POST",
    body: payload,
    headers: {
      "webhook-id": id,
      "webhook-timestamp": `${Math.floor(ts.getTime() / 1000)}`,
      "webhook-signature": signature,
    },
  });
}

const hook = (phone: string, otp = "123456") => ({ user: { phone }, sms: { otp } });

Deno.test("a signed hook for an Indian mobile sends the code", async () => {
  const sent: [string, string][] = [];
  const res = await handleSendSms(signed(hook("+91 98765 43210")), secret, async (m, o) => void sent.push([m, o]));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {});
  assertEquals(sent, [["919876543210", "123456"]]);
});

Deno.test("a wrong signature sends nothing", async () => {
  const other = btoa("ffffffffffffffffffffffffffffffff");
  let called = false;
  const res = await handleSendSms(signed(hook("919876543210"), other), secret, async () => void (called = true));
  assertEquals(res.status, 401);
  assertEquals(called, false);
});

Deno.test("numbers outside India and malformed codes are refused before any SMS", async () => {
  let calls = 0;
  const send = async () => void calls++;
  for (const phone of ["+447700900123", "+911234567890", "9876543210", ""]) {
    assertEquals((await handleSendSms(signed(hook(phone)), secret, send)).status, 400, phone);
  }
  assertEquals((await handleSendSms(signed(hook("919876543210", "12ab56")), secret, send)).status, 400);
  assertEquals(calls, 0);
});

Deno.test("a provider failure comes back as an error Auth can show", async () => {
  const res = await handleSendSms(signed(hook("919876543210")), secret, () => Promise.reject(new Error("down")));
  assertEquals(res.status, 502);
  assertEquals((await res.json()).error.http_code, 502);
});

Deno.test("msg91Sender puts the authkey in a header and fails on a non-success reply", async () => {
  const seen: { url: string; key: string | null }[] = [];
  const reply = (body: unknown, status = 200) =>
    (async (input: string | URL | Request, init?: RequestInit) => {
      seen.push({ url: String(input), key: new Headers(init?.headers).get("authkey") });
      return Response.json(body, { status });
    }) as typeof fetch;

  await msg91Sender("KEY", "TPL", reply({ type: "success" }))("919876543210", "123456");
  const url = new URL(seen[0].url);
  assertEquals(url.searchParams.get("template_id"), "TPL");
  assertEquals(url.searchParams.get("mobile"), "919876543210");
  assertEquals(url.searchParams.get("otp"), "123456");
  assertEquals(url.searchParams.has("authkey"), false);
  assertEquals(seen[0].key, "KEY");

  let failed = false;
  await msg91Sender("KEY", "TPL", reply({ type: "error", message: "Invalid template" }))("919876543210", "1")
    .catch(() => (failed = true));
  assertEquals(failed, true);
});
