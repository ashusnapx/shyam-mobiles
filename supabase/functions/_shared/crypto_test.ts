import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { hmacSha256Hex, safeEqual, verifySignature } from "./crypto.ts";

Deno.test("hmacSha256Hex matches RFC 4231 test case 2", async () => {
  assertEquals(
    await hmacSha256Hex("Jefe", "what do ya want for nothing?"),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("hmacSha256Hex hashes raw bytes and strings alike", async () => {
  const text = "order_1|pay_1 ₹";
  assertEquals(await hmacSha256Hex("k", await new Response(text).arrayBuffer()), await hmacSha256Hex("k", text));
});

Deno.test("safeEqual", () => {
  assert(safeEqual("abc", "abc"));
  assertFalse(safeEqual("abc", "abd"));
  assertFalse(safeEqual("abc", "ab"));
  assert(safeEqual("", ""));
});

Deno.test("verifySignature: Razorpay checkout format order_id|payment_id", async () => {
  const sig = await hmacSha256Hex("secret", "order_A|pay_B");
  assert(await verifySignature("secret", "order_A|pay_B", sig));
  assertFalse(await verifySignature("secret", "order_A|pay_C", sig));
  assertFalse(await verifySignature("other", "order_A|pay_B", sig));
  assertFalse(await verifySignature("secret", "order_A|pay_B", sig.toUpperCase()));
  assertFalse(await verifySignature("secret", "order_A|pay_B", ""));
});
