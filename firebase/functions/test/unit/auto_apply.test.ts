import { expect, test } from "vitest";
import { savePromotion } from "../../src/offers/contract.js";
import { brokenRule, mirrorOf, newPromotion, type Promotion } from "../../src/offers/promotion.js";

// Campaign calendar: autoApply rides on a coded promotion; pricing never reads it (the app sends the code).
const now = new Date("2026-11-19T00:00:00+05:30");
const p = (over: Partial<Promotion>): Promotion => ({ ...newPromotion(now), title: "Men's Day sale", kind: "percent", value: 5, code: "MEN5", ...over });

test("off by default; only a coded offer may auto-apply", () => {
  expect(newPromotion(now).autoApply).toBe(false);
  expect(brokenRule(p({ autoApply: true }))).toBeNull();
  expect(brokenRule(p({ autoApply: true, code: null }))).toBe("promotions_auto_apply_check");
  expect(brokenRule(p({ autoApply: false, code: null }))).toBeNull();
});

test("customers see the flag on the public mirror; staff send it like any field", () => {
  expect(mirrorOf(p({ autoApply: true }))).toMatchObject({ code: "MEN5", autoApply: true, usedUp: false });
  expect(savePromotion.input.safeParse({ id: "x", autoApply: true }).success).toBe(true);
  expect(savePromotion.input.safeParse({ id: "x", autoApply: "yes" }).success).toBe(false);
});
