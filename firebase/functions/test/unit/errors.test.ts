import { readFileSync } from "node:fs";
import { HttpsError } from "firebase-functions/v2/https";
import { expect, test } from "vitest";
import { fail, REASONS, reasonOf } from "../../src/shared/errors.js";

// The app shows copy by reason (app/lib/core/errors.dart `_codes`), so both lists must hold the same keys.
const dart = readFileSync(new URL("../../../../app/lib/core/errors.dart", import.meta.url), "utf8");
const block = /const _codes = \{([\s\S]*?)\n\};/.exec(dart)?.[1] ?? "";
const appCodes = new Set([...block.matchAll(/^\s+'([A-Z_]+)':/gm)].map((m) => m[1] ?? ""));
/** Razorpay payment links, gone with decision D4; their copy leaves the app in Phase 2. */
const APP_ONLY = new Set(["LINK_IN_PROGRESS", "LINK_NOT_OPEN"]);
/** Staff refund refusals that carry the server's own staff copy (see the comment above them in errors.dart). */
const SERVER_COPY = new Set(["REFUND_NOT_ALLOWED", "REFUND_REFUSED"]);

test("every app error code is a server reason", () => {
  expect(appCodes.size).toBeGreaterThan(40);
  for (const code of appCodes) if (!APP_ONLY.has(code)) expect(REASONS).toHaveProperty(code);
});

test("every server reason has app copy", () => {
  for (const reason of Object.keys(REASONS)) if (!SERVER_COPY.has(reason)) expect(appCodes, reason).toContain(reason);
});

test("fail() throws one HttpsError shape", () => {
  try {
    fail("COUPON_MIN_ORDER", 99900);
  } catch (e) {
    expect(e).toBeInstanceOf(HttpsError);
    expect((e as HttpsError).code).toBe("failed-precondition");
    expect((e as HttpsError).details).toEqual({ reason: "COUPON_MIN_ORDER", detail: 99900 });
    expect(reasonOf(e)).toBe("COUPON_MIN_ORDER");
    return;
  }
  expect.unreachable();
});
