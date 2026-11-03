import type { DecodedIdToken } from "firebase-admin/auth";
import { describe, expect, test } from "vitest";
import { requireOwner, requireRecentLogin, requireStaff, requireUser, rejectConsumedAppCheck } from "../../src/shared/auth.js";
import { reasonOf } from "../../src/shared/errors.js";
import { redact } from "../../src/shared/log.js";
import { add, inr, paise, percentOf, sub, sum, times } from "../../src/shared/money.js";
import { nextHits } from "../../src/shared/rateLimit.js";
import { addDays, financialYear, istDate, istMidnight, istMonth } from "../../src/shared/time.js";

const reason = async (f: () => unknown) => {
  try {
    await f();
  } catch (e) {
    return reasonOf(e);
  }
  return null;
};

describe("money", () => {
  test("only safe non-negative integers", () => {
    expect(() => paise(1.5)).toThrow();
    expect(() => paise(-1)).toThrow();
    expect(() => paise(2 ** 53)).toThrow();
    expect(() => sub(paise(100), paise(101))).toThrow();
    expect(sum([paise(4900), paise(50000), paise(1)])).toBe(54901);
    expect(add(paise(1), times(paise(30000), 3))).toBe(90001);
  });
  test("percent rounds down", () => {
    expect(percentOf(paise(99999), 20)).toBe(19999);
    expect(() => percentOf(paise(100), 101)).toThrow();
  });
  test("₹ in Indian grouping", () => {
    expect(inr(paise(12999900))).toBe("₹1,29,999");
    expect(inr(paise(4950))).toBe("₹49.50");
    expect(inr(paise(0))).toBe("₹0");
  });
});

describe("IST calendar", () => {
  const lateUtc = new Date("2026-03-31T19:00:00Z"); // 00:30 on 1 April in India
  test("day, month and financial year follow IST", () => {
    expect(istDate(lateUtc)).toBe("2026-04-01");
    expect(istMonth(lateUtc)).toBe("202604");
    expect(financialYear(lateUtc)).toBe("26-27");
    expect(financialYear(new Date("2026-03-31T18:00:00Z"))).toBe("25-26");
    expect(istMidnight(lateUtc).toISOString()).toBe("2026-03-31T18:30:00.000Z");
    expect(addDays("2026-02-27", 2)).toBe("2026-03-01");
  });
});

test("rate limit windows roll", () => {
  const rule = { max: 2, windowMs: 1000 };
  expect(nextHits([], 5000, rule)).toEqual([5000]);
  expect(nextHits([4500, 4800], 5000, rule)).toBeNull();
  expect(nextHits([3000, 4800], 5000, rule)).toEqual([4800, 5000]);
});

describe("log redaction", () => {
  test("drops personal fields and scrubs strings", () => {
    expect(redact({ uid: "u1", fullName: "Ravi", address: { line1: "x" }, totalPaise: 4900 }))
      .toEqual({ uid: "u1", fullName: "[redacted]", address: "[redacted]", totalPaise: 4900 });
    expect(redact("call +91 98765 43210 or 9876543210, mail a@b.in")).toBe("call [phone] or [phone], mail [email]");
    expect(redact("Bearer eyJhbGciOi.eyJzdWIiOi.c2ln")).toBe("Bearer [jwt]");
    expect(redact("order SM100001 total 1299900 imei 356938035643809")).toBe("order SM100001 total 1299900 imei 356938035643809");
  });
});

describe("auth guards", () => {
  const nowMs = 1_800_000_000_000;
  const token = (claims: Record<string, unknown>, secondFactor?: string) =>
    ({ uid: "u1", auth_time: nowMs / 1000 - 60, firebase: { sign_in_provider: "google.com", sign_in_second_factor: secondFactor }, ...claims }) as unknown as DecodedIdToken;
  const req = (t?: DecodedIdToken) => ({ auth: t ? { uid: "u1", token: t, rawToken: "" } : undefined });
  const role = (r: unknown) => () => Promise.resolve(r);

  test("signed in", async () => {
    expect(await reason(() => requireUser(req()))).toBe("UNAUTHORIZED");
    expect(requireUser(req(token({}))).uid).toBe("u1");
  });
  test("staff needs the claim, TOTP and the role doc", async () => {
    expect((await requireStaff(req(token({ role: "staff" }, "totp")), role("staff"))).role).toBe("staff");
    expect(await reason(() => requireStaff(req(token({ role: "staff" })), role("staff")))).toBe("FORBIDDEN"); // phone sign-in, no TOTP
    expect(await reason(() => requireStaff(req(token({}, "totp")), role("staff")))).toBe("FORBIDDEN"); // no claim
    expect(await reason(() => requireStaff(req(token({ role: "staff" }, "totp")), role(undefined)))).toBe("FORBIDDEN"); // removed
    expect(await reason(() => requireStaff(req(token({ role: "admin" }, "totp")), role("admin")))).toBe("FORBIDDEN");
    expect(await reason(() => requireOwner(req(token({ role: "staff" }, "totp")), role("staff")))).toBe("FORBIDDEN");
    expect((await requireOwner(req(token({ role: "owner" }, "totp")), role("owner"))).role).toBe("owner");
  });
  test("recent login and replay", async () => {
    const caller = requireUser(req(token({})));
    expect(() => { requireRecentLogin(caller, nowMs); }).not.toThrow();
    expect(await reason(() => { requireRecentLogin(caller, nowMs + 300_000); })).toBe("REAUTH_REQUIRED");
    expect(await reason(() => { rejectConsumedAppCheck({ app: { appId: "a", token: {} as never, alreadyConsumed: true } }); })).toBe("UNAUTHORIZED");
    expect(() => { rejectConsumedAppCheck({ app: undefined }); }).not.toThrow();
  });
});
