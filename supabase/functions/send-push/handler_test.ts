import { assert, assertEquals } from "jsr:@std/assert@1";
import { sendPushHandler, signJwt } from "./handler.ts";

const keys = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true,
  ["sign", "verify"],
);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey));
const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8)).replace(/.{64}/g, "$&\n")}\n-----END PRIVATE KEY-----\n`;
const serviceAccount = JSON.stringify({ project_id: "shyam-test", client_email: "push@shyam-test.iam.gserviceaccount.com", private_key: pem });

const PHONE_A = "fA1b2C3d4E5f6G7h8I9j0:APA91bAAAA";
const PHONE_B = "zZ9y8X7w6V5u4T3s2R1q0:APA91bBBBB";
const push = {
  id: "n1",
  kind: "order_packed",
  title: "SM1042 is packed",
  body: "It ships soon.",
  link: "/orders/o1",
  image_path: "p1/1730000000000.webp",
  tokens: [PHONE_A, PHONE_B],
};

/** Google and FCM stand-ins: every call recorded; [fcm] decides each phone's reply. */
function fakeGoogle(fcm: (token: string) => Response = () => Response.json({ name: "projects/shyam-test/messages/1" })) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fetchFn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });
    if (url === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "ya29.test", expires_in: 3600 });
    return fcm(JSON.parse(String(init?.body)).message.token);
  }) as typeof fetch;
  return { calls, fetchFn };
}

const request = (body: unknown, secret = "s3cret") =>
  new Request("http://x/send-push", { method: "POST", headers: { "x-push-secret": secret }, body: JSON.stringify(body) });

Deno.test("a wrong or missing secret sends nothing", async () => {
  const { calls, fetchFn } = fakeGoogle();
  const send = sendPushHandler({ secret: "s3cret", serviceAccount, fetch: fetchFn, forget: async () => {} });
  assertEquals((await send(request(push, "nope"))).status, 401);
  assertEquals((await send(new Request("http://x", { method: "POST", body: JSON.stringify(push) }))).status, 401);
  const unset = sendPushHandler({ secret: undefined, serviceAccount, fetch: fetchFn, forget: async () => {} });
  assertEquals((await unset(request(push, ""))).status, 401);
  assertEquals(calls.length, 0);
});

Deno.test("without FCM_SERVICE_ACCOUNT it's a logged no-op", async () => {
  const { calls, fetchFn } = fakeGoogle();
  const logs: unknown[] = [];
  const log = console.log;
  console.log = (...a: unknown[]) => void logs.push(a.join(" "));
  try {
    const res = await sendPushHandler({ secret: "s3cret", fetch: fetchFn, forget: async () => {} })(request(push));
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { sent: 0, off: true });
  } finally {
    console.log = log;
  }
  assertEquals(calls.length, 0);
  assert(String(logs[0]).includes("FCM_SERVICE_ACCOUNT is not set"));
});

Deno.test("one FCM v1 message per phone, with one access token for many pushes", async () => {
  const { calls, fetchFn } = fakeGoogle();
  const send = sendPushHandler({ secret: "s3cret", serviceAccount, fetch: fetchFn, forget: async () => {} });
  const res = await send(request(push));
  assertEquals(await res.json(), { sent: 2, failed: 0, removed: 0 });
  await send(request({ ...push, tokens: [PHONE_A] }));

  const token = calls.filter((c) => c.url === "https://oauth2.googleapis.com/token");
  assertEquals(token.length, 1);
  const form = new URLSearchParams(String(token[0].init?.body));
  assertEquals(form.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
  const [head, claims, sig] = form.get("assertion")!.split(".");
  const unb64 = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const verified = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", keys.publicKey, unb64(sig), new TextEncoder().encode(`${head}.${claims}`));
  assert(verified, "signed with the service account key");
  const c = JSON.parse(new TextDecoder().decode(unb64(claims)));
  assertEquals([c.iss, c.scope, c.aud, c.exp - c.iat], [
    "push@shyam-test.iam.gserviceaccount.com",
    "https://www.googleapis.com/auth/firebase.messaging",
    "https://oauth2.googleapis.com/token",
    3600,
  ]);

  const fcm = calls.filter((c) => c.url.startsWith("https://fcm.googleapis.com/"));
  assertEquals(fcm.length, 3);
  assertEquals(fcm[0].url, "https://fcm.googleapis.com/v1/projects/shyam-test/messages:send");
  assertEquals(new Headers(fcm[0].init?.headers).get("authorization"), "Bearer ya29.test");
  // data-only: the app draws the notification (photo, illustration, colour) in the foreground and the background
  assertEquals(JSON.parse(String(fcm[0].init?.body)).message, {
    token: PHONE_A,
    data: {
      id: "n1",
      kind: "order_packed",
      title: "SM1042 is packed",
      body: "It ships soon.",
      link: "/orders/o1",
      image_path: "p1/1730000000000.webp",
    },
    android: { priority: "high" },
  });
});

Deno.test("no photo, no link: those keys are left out, never sent as null or empty", async () => {
  const { calls, fetchFn } = fakeGoogle();
  const send = sendPushHandler({ secret: "s3cret", serviceAccount, fetch: fetchFn, forget: async () => {} });
  await send(request({ ...push, image_path: null, link: null, tokens: [PHONE_A] }));
  const message = JSON.parse(String(calls.find((c) => c.url.includes("fcm.googleapis.com"))!.init?.body)).message;
  assertEquals(message.data, { id: "n1", kind: "order_packed", title: "SM1042 is packed", body: "It ships soon." });
  assertEquals(message.notification, undefined);
});

Deno.test("a phone FCM no longer knows is forgotten; other failures are only logged", async () => {
  const { fetchFn } = fakeGoogle((t) =>
    t === PHONE_A
      ? Response.json({ error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } }, { status: 404 })
      : new Response("busy", { status: 503 })
  );
  const forgotten: string[][] = [];
  const error = console.error;
  console.error = () => {};
  try {
    const res = await sendPushHandler({ secret: "s3cret", serviceAccount, fetch: fetchFn, forget: async (t) => void forgotten.push(t) })(
      request(push),
    );
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { sent: 0, failed: 1, removed: 1 });
  } finally {
    console.error = error;
  }
  assertEquals(forgotten, [[PHONE_A]]);
});

Deno.test("a malformed push is refused before any call", async () => {
  const { calls, fetchFn } = fakeGoogle();
  const send = sendPushHandler({ secret: "s3cret", serviceAccount, fetch: fetchFn, forget: async () => {} });
  for (const bad of [{ ...push, tokens: ["short"] }, { ...push, title: 5 }, { ...push, tokens: "x" }, [1]]) {
    assertEquals((await send(request(bad))).status, 400, JSON.stringify(bad));
  }
  assertEquals(calls.length, 0);
});

Deno.test("signJwt makes a three-part RS256 token", async () => {
  const jwt = await signJwt({ a: 1 }, pem);
  assertEquals(jwt.split(".").length, 3);
  assertEquals(JSON.parse(atob(jwt.split(".")[0])), { alg: "RS256", typ: "JWT" });
});
