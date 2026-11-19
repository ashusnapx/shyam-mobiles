import { expect, test } from "vitest";
import { saveReview } from "../../src/feedback/contract.js";
import { ratingStats, reviewerName, verifiedOrder } from "../../src/feedback/ratings.js";

// Growth (docs/GROWTH.md §2a): who may review, the name shown, the numbers shown.

test("only a delivered order holding the product verifies the purchase", () => {
  const orders = [
    { id: "o1", status: "shipped", items: [{ productId: "p1" }] },
    { id: "o2", status: "delivered", items: [{ productId: "p2" }] },
    { id: "o3", status: "delivered", items: "junk" },
    { id: "o4", status: "delivered", items: [{ productId: "p2" }, { productId: "p1" }] },
  ];
  expect(verifiedOrder(orders, "p1")).toBe("o4");
  expect(verifiedOrder(orders.slice(0, 3), "p1")).toBeNull();
  expect(verifiedOrder([], "p1")).toBeNull();
});

test("the published name is a first name and an initial, never the full name", () => {
  expect(reviewerName("Ravi Kumar Sharma")).toBe("Ravi S.");
  expect(reviewerName("  ravi   kumar ")).toBe("ravi K.");
  expect(reviewerName("Ravi")).toBe("Ravi");
  expect(reviewerName("राम शर्मा")).toBe("राम श.");
  expect(reviewerName(null)).toBe("Customer");
  expect(reviewerName("   ")).toBe("Customer");
});

test("stats count only whole 1..5 ratings; the average rounds half up to one decimal", () => {
  expect(ratingStats([5, 4, 4])).toEqual({ count: 3, sum: 13, stars: [0, 0, 0, 2, 1], avg10: 43 });
  expect(ratingStats([5, 4]).avg10).toBe(45);
  expect(ratingStats([1, 2, 2]).avg10).toBe(17); // 1.666…
  expect(ratingStats([4, 4, 5, 5, 5, 5]).avg10).toBe(47); // 4.666…
  expect(ratingStats([0, 6, 4.5, "5", null]).count).toBe(0);
  expect(ratingStats([])).toEqual({ count: 0, sum: 0, stars: [0, 0, 0, 0, 0], avg10: 0 });
});

test("saveReview takes up to 3 of the caller's photo keys and 1000 characters", () => {
  const ok = { productId: "galaxy-s25", rating: 5, text: "Good", photos: ["review-photos/u1/1730000000000.webp"] };
  expect(saveReview.input.safeParse(ok).success).toBe(true);
  expect(saveReview.input.parse({ productId: "galaxy-s25", rating: 3 })).toEqual({ productId: "galaxy-s25", rating: 3, text: "", photos: [] });
  for (const bad of [
    { ...ok, rating: 0 }, { ...ok, rating: 4.5 }, { ...ok, text: "x".repeat(1001) },
    { ...ok, photos: Array(4).fill(ok.photos[0]) }, { ...ok, photos: ["product-images/p/1.webp"] },
    { ...ok, photos: ["review-photos/u1/../x.webp"] }, { ...ok, extra: 1 },
  ]) expect(saveReview.input.safeParse(bad).success, JSON.stringify(bad).slice(0, 80)).toBe(false);
});
