import { expect, test } from "vitest";
import { pushData } from "../../src/notifications/contract.js";
import { estimateExchange, requestExchange } from "../../src/repairs/contract.js";
import { estimateRange, exchangeNotice } from "../../src/repairs/exchange.js";

// Growth (docs/GROWTH.md §2c): what a request may hold, and the estimate's notice (a range, never a promise).

test("a request: brand, model, age and condition chips, up to 3 of the caller's photos", () => {
  const ok = { brand: "Samsung", model: "Galaxy A12", age: "2_3", condition: "good", photos: ["exchange-photos/u1/1730000000000.webp"] };
  expect(requestExchange.input.parse(ok)).toEqual({ ...ok });
  expect(requestExchange.input.parse({ ...ok, photos: undefined, forProductId: "galaxy-s25" }).photos).toEqual([]);
  for (const bad of [
    { ...ok, brand: "" }, { ...ok, model: "x".repeat(61) }, { ...ok, age: "new" }, { ...ok, condition: "broken" },
    { ...ok, photos: Array(4).fill(ok.photos[0]) }, { ...ok, photos: ["review-photos/u1/1.webp"] }, { ...ok, priceRupees: 5000 },
  ]) expect(requestExchange.input.safeParse(bad).success, JSON.stringify(bad).slice(0, 80)).toBe(false);
});

test("an estimate is a range: low ≤ high, ₹0 to ₹10,00,000", () => {
  expect(estimateExchange.input.safeParse({ exchangeId: "e1", lowPaise: 400000, highPaise: 500000 }).success).toBe(true);
  expect(estimateExchange.input.safeParse({ exchangeId: "e1", lowPaise: 500000, highPaise: 400000 }).success).toBe(false);
  expect(estimateExchange.input.safeParse({ exchangeId: "e1", lowPaise: 0, highPaise: 100_000_001 }).success).toBe(false);
  expect(estimateExchange.input.safeParse({ exchangeId: "e1", lowPaise: 1.5, highPaise: 2 }).success).toBe(false);
});

test("the customer's notice names the range and says the final value comes after the check", () => {
  expect(estimateRange(400000, 500000)).toBe("₹4,000–₹5,000");
  expect(estimateRange(400000, 400000)).toBe("₹4,000");
  const n = exchangeNotice("u1", { brand: "Samsung", model: "Galaxy A12" }, 400000, 550000, 1_763_000_000_000);
  expect(n).toMatchObject({ recipient: "u1", key: "1763000000000", kind: "exchange_estimate", link: "/repairs/exchanges" });
  expect(n.body).toBe("About ₹4,000–₹5,500 for your old phone. The final value is set when the shop checks it.");
  expect(pushData.safeParse({ id: "x", kind: n.kind, title: n.title, body: n.body, link: n.link }).success).toBe(true);
  expect(exchangeNotice("u1", { brand: "B".repeat(50), model: "M".repeat(60) }, 0, 0, 1).title.length).toBe(80);
});
