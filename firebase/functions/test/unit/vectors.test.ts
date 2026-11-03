import { describe, expect, test } from "vitest";
import type { z } from "zod";
import { REASONS } from "../../src/shared/errors.js";
import * as account from "../../src/account/contract.js";
import * as catalog from "../../src/catalog/contract.js";
import * as feedback from "../../src/feedback/contract.js";
import * as offers from "../../src/offers/contract.js";
import * as orders from "../../src/orders/contract.js";
import * as payments from "../../src/payments/contract.js";
import * as referrals from "../../src/referrals/contract.js";
import * as repairs from "../../src/repairs/contract.js";
import { callFiles, loadVectors, resolveTime } from "../vectors.js";

// Every vector file is well formed, names a real callable (or a known internal function), and its inputs pass that
// callable's contract: the vectors, the contracts and errors.dart can't drift apart silently.

const contracts = new Map<string, { input: z.ZodType; invalid: string }>(
  [account, catalog, feedback, offers, orders, payments, referrals, repairs]
    .flatMap((m): unknown[] => Object.values(m))
    .filter((x): x is { name: string; input: z.ZodType; invalid: string } => typeof x === "object" && x !== null && "name" in x && "input" in x)
    .map((c) => [c.name, c]),
);
/** Not callables: the scheduled job, settlement (called by payments), the app's pure offerOpenFor, and
 * notifications/notices.ts (called by the triggers). */
const INTERNAL = new Set(["expireUnpaidOrders", "settleOnlinePayment", "settleRefund", "offerOpenFor",
  "orderNotices", "refundNotices", "repairNotices", "couponNotice", "feedbackNotices", "stockNotices", "backInStock"]);

describe.each(callFiles())("test-vectors/%s.json", (name) => {
  const file = loadVectors(name);

  test("case ids are unique", () => {
    const ids = file.cases.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  test.each(file.cases.map((c) => [c.id, c] as const))("%s", (_id, c) => {
    if (c.error !== undefined) expect(Object.keys(REASONS)).toContain(c.error);
    if (INTERNAL.has(c.call)) return;
    const contract = contracts.get(c.call);
    expect(contract, `no contract for ${c.call}`).toBeDefined();
    // A case expecting the contract's own invalid-input reason may fail parsing: that is what it tests.
    if (c.error !== contract?.invalid) expect(contract?.input.safeParse(c.input).error).toBeUndefined();
  });
});

test("relative times", () => {
  const now = new Date("2026-11-03T12:00:00+05:30");
  expect(resolveTime("@now", now)).toEqual(now);
  expect(resolveTime("@now+15m", now)).toEqual(new Date(now.getTime() + 900_000));
  expect(resolveTime("@now-2d", now)).toEqual(new Date(now.getTime() - 172_800_000));
  expect(resolveTime("2026-01-01", now)).toBe("2026-01-01");
});
