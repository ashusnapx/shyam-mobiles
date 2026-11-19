import { expect, test } from "vitest";
import { addSold, addWith, counts, gone, units } from "../../src/feedback/stats.js";

// Growth (docs/GROWTH.md §2b): which orders count, and the rolling 7-day and co-purchase counts.

test("an order counts once paid or delivered, and not after a cancel or refund", () => {
  expect(counts({ status: "confirmed", paymentStatus: "paid" })).toBe(true); // online, paid
  expect(counts({ status: "delivered", paymentStatus: "pending" })).toBe(true); // COD at the door
  expect(counts({ status: "confirmed", paymentStatus: "pending" })).toBe(false); // COD not yet delivered
  expect(counts({ status: "pending_payment", paymentStatus: "pending" })).toBe(false);
  expect(counts({ status: "cancelled", paymentStatus: "paid" })).toBe(false);
  expect(counts({ status: "delivered", paymentStatus: "refunded" })).toBe(false);
  expect(counts(undefined)).toBe(false);
  expect(gone({ status: "refunded" }) && gone({ status: "cancelled" }) && gone({ paymentStatus: "refunded" })).toBe(true);
  expect(gone({ status: "shipped", paymentStatus: "paid" })).toBe(false);
});

test("units add up per product; junk lines are skipped", () => {
  expect(units([{ productId: "a", qty: 2 }, { productId: "b", qty: 1 }, { productId: "a", qty: 1 }])).toEqual({ a: 3, b: 1 });
  expect(units([{ productId: "a", qty: 0 }, { productId: 5, qty: 1 }, { productId: "c", qty: 1.5 }, null])).toEqual({});
  expect(units("junk")).toEqual({});
});

test("sold keeps the 7 IST days ending today and drops empty days", () => {
  const sold = { "2026-11-10": 4, "2026-11-12": 1, "2026-11-18": 2 };
  expect(addSold(sold, "2026-11-19", 3, "2026-11-19")).toEqual({ "2026-11-18": 2, "2026-11-19": 3 }); // 13th is the oldest kept
  expect(addSold({ "2026-11-13": 1 }, "2026-11-13", 2, "2026-11-19")).toEqual({ "2026-11-13": 3 });
  expect(addSold({ "2026-11-18": 2 }, "2026-11-18", -2, "2026-11-19")).toEqual({});
  expect(addSold(undefined, "2026-11-01", -1, "2026-11-19")).toEqual({}); // taking back a day already gone
});

test("co-purchase counts: every other product in the order, never itself, never below 1", () => {
  expect(addWith(undefined, "a", ["a", "b", "c"], 1)).toEqual({ b: 1, c: 1 });
  expect(addWith({ b: 1, c: 2 }, "a", ["a", "b", "c"], -1)).toEqual({ c: 1 });
  expect(addWith({ b: 3 }, "a", ["a"], 1)).toEqual({ b: 3 });
});
