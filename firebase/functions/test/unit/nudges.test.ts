import { expect, test } from "vitest";
import { pushData } from "../../src/notifications/contract.js";
import * as n from "../../src/notifications/nudges.js";

// Growth (docs/GROWTH.md §2d, e): when a marketing push may go, and what it says.
const DAY = 86_400_000;
const ist = (iso: string) => new Date(`${iso}+05:30`);

test("quiet from 9 pm to 9 am IST", () => {
  expect(n.quietHours(ist("2026-11-19T20:59:00"))).toBe(false);
  expect(n.quietHours(ist("2026-11-19T21:00:00"))).toBe(true);
  expect(n.quietHours(ist("2026-11-20T03:00:00"))).toBe(true);
  expect(n.quietHours(ist("2026-11-20T08:59:00"))).toBe(true);
  expect(n.quietHours(ist("2026-11-20T09:00:00"))).toBe(false);
});

test("1 marketing push per 3 days; the switch is on unless turned off", () => {
  const now = Date.UTC(2026, 10, 19);
  expect(n.capped(undefined, now)).toBe(false);
  expect(n.capped(now - 3 * DAY + 1, now)).toBe(true);
  expect(n.capped(now - 3 * DAY, now)).toBe(false);
  expect(n.optedIn(undefined) && n.optedIn({}) && n.optedIn({ offers: true, backInStock: false })).toBe(true);
  expect(n.optedIn({ offers: false })).toBe(false);
});

test("cart: only with something in stock, one per cart state", () => {
  expect(n.cartNudge(5, [])).toBeNull();
  expect(n.cartNudge(5, ["Galaxy S25"])).toMatchObject({ id: "nudge_cart_5", body: "Galaxy S25 is still in stock.", link: "/cart" });
  expect(n.cartNudge(5, ["Galaxy S25", "Case", "Guard"])?.body).toBe("Galaxy S25 and 2 more are still in stock.");
});

test("price drop: a real drop on an active, in-stock variant", () => {
  const live = { isActive: true, productActive: true, stock: 2 };
  expect(n.priceDropped({ pricePaise: 100 }, { ...live, pricePaise: 90 })).toBe(true);
  expect(n.priceDropped({ pricePaise: 100 }, { ...live, pricePaise: 100 })).toBe(false);
  expect(n.priceDropped({ pricePaise: 100 }, { ...live, pricePaise: 120 })).toBe(false);
  expect(n.priceDropped({ pricePaise: 100 }, { ...live, stock: 0, pricePaise: 90 })).toBe(false);
  expect(n.priceDropped({ pricePaise: 100 }, { ...live, isActive: false, pricePaise: 90 })).toBe(false);
  expect(n.priceDropped({}, { ...live, pricePaise: 90 })).toBe(false);
  const d = n.priceDropNudge({ variantId: "v1", productId: "galaxy-s25", productName: "Samsung Galaxy S25", fromPaise: 7999900, toPaise: 7499900 });
  expect(d).toMatchObject({ id: "nudge_drop_v1_7499900", title: "Price dropped: Samsung Galaxy S25", link: "/product/galaxy-s25?variant=v1" });
  expect(d.body).toBe("Now ₹74,999, was ₹79,999. It’s on your wishlist.");
});

test("protect: 2 to 3 days after delivery, when something in stock fits", () => {
  const at = Date.UTC(2026, 10, 10);
  const events = [{ status: "confirmed", at: new Date(at - DAY) }, { status: "delivered", at: { toMillis: () => at } }];
  expect(n.deliveredAtMs(events)).toBe(at);
  expect(n.deliveredAtMs([{ status: "shipped", at: new Date() }, null])).toBeNull();
  expect(n.protectDue(at, at + 2 * DAY - 1)).toBe(false);
  expect(n.protectDue(at, at + 2 * DAY)).toBe(true);
  expect(n.protectDue(at, at + 3 * DAY)).toBe(false);
  expect(n.protectDue(null, at)).toBe(false);
  const phone = { name: "Samsung Galaxy S25", brandName: "Samsung" };
  expect(n.hasFittingAccessory({ c1: { ft: ["Galaxy S25"], i: true } }, phone)).toBe(true);
  expect(n.hasFittingAccessory({ c1: { ft: ["Galaxy S25"], i: false } }, phone)).toBe(false);
  expect(n.hasFittingAccessory({ c1: { ft: ["Galaxy S24"], i: true }, c2: { i: true } }, phone)).toBe(false);
  expect(n.hasFittingAccessory({ c1: { ft: ["OnePlus 13"], i: true } }, { name: "OnePlus 13", brandName: "OnePlus" })).toBe(true);
  expect(n.protectNudge("o1", "Samsung Galaxy S25")).toMatchObject({ id: "nudge_protect_o1", link: "/orders/o1" });
});

test("every nudge passes the push contract", () => {
  for (const x of [
    n.cartNudge(1, ["A".repeat(400)]),
    n.priceDropNudge({ variantId: "v", productId: "p", productName: "N".repeat(200), fromPaise: 2, toPaise: 1 }),
    n.protectNudge("o1", "P".repeat(400)),
  ]) expect(pushData.safeParse({ id: x?.id, kind: x?.kind, title: x?.title, body: x?.body, link: x?.link }).success).toBe(true);
});
