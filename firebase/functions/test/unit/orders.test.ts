import { describe, expect, test } from "vitest";
import type { OrderStatus } from "../../src/model/orders.js";
import { offerOpenFor, price, splitDiscount, type Line, type Promo } from "../../src/orders/pricing.js";
import { customerCancelNote, staffStep } from "../../src/orders/state.js";
import { loadVectors, resolveTimes, startingDocs } from "../vectors.js";

// pricing.ts and state.ts against the vectors with no Firestore: the docs a case starts from are handed to the pure
// functions as the handlers would load them. The emulator suite (test/integration/vectors.test.ts) runs every case end
// to end, writes included.

type D = Record<string, unknown>;
const promo = (id: string, d: D): Promo & { isPublic: boolean; uid: string | null } =>
  ({ ...(d as unknown as Promo & { isPublic: boolean }), id, uid: (d.uid as string | null | undefined) ?? null, usesActive: (d.usesActive as number | undefined) ?? 0, targets: (d.targets as Promo["targets"] | undefined) ?? [] });

describe.each(["pricing", "offers", "referrals"])("quoteOrder vectors in %s.json, pure", (name) => {
  const file = loadVectors(name);
  const now = new Date(file.now);
  test.each(file.cases.filter((c) => c.call === "quoteOrder" && !c.error).map((c) => [c.id, c] as const))("%s", (_id, c) => {
    const docs = startingDocs(file, c) as Record<string, D>;
    const uid = c.as;
    const at = (p: string) => Object.entries(docs).filter(([k]) => k.startsWith(`${p}/`) && k.split("/").length === p.split("/").length + 1);
    const cart = Object.entries((docs[`carts/${uid}`]?.lines ?? {}) as Record<string, { qty: number }>).sort(([a], [b]) => (a < b ? -1 : 1));
    const lines: Line[] = cart.flatMap(([id, { qty }]) => {
      const v = docs[`variants/${id}`];
      if (!v) return [];
      const p = docs[`products/${v.productId as string}`] ?? {};
      const groups = at("collections").filter(([, g]) => (g.productIds as string[]).includes(v.productId as string)).map(([k]) => k.split("/")[1]!);
      return [{ variantId: id, productId: v.productId as string, categoryId: p.categoryId as string, brandId: p.brandId as string, collectionIds: groups, unitPricePaise: v.pricePaise as number, qty }];
    });
    const input = c.input as { couponCode?: string; paymentMethod?: "online" | "cod" | null };
    const code = input.couponCode?.replace(/\s+/g, "").toUpperCase() || null;
    const fails = ((docs[`rateLimits/${uid}`]?.couponFails ?? []) as Date[]).filter((t) => t.getTime() > now.getTime() - 600_000);
    const pid = code ? (docs[`promoCodes/${code}`]?.promotionId as string | undefined) : undefined;
    const found = pid && docs[`promotions/${pid}`] ? promo(pid, docs[`promotions/${pid}`]!) : null;
    const usable = found?.isActive && (found.uid === null || found.uid === uid) ? found : null;
    const got = price({
      lines, fees: docs["settings/store"] as never, forPlace: false,
      code: code === null ? null : fails.length >= 10 ? { rateLimited: true } : { rateLimited: false, promo: usable },
      sales: at("promotions").map(([k, d]) => promo(k.split("/")[1]!, d)).filter((p) => p.code === null && p.isActive),
      who: {
        method: input.paymentMethod ?? null, now,
        hasOrder: at("orders").some(([, o]) => o.uid === uid && o.status !== "cancelled"),
        usesByUser: (id) => at("redemptions").filter(([, r]) => r.promotionId === id && r.uid === uid && r.active).length,
      },
    });
    const p = got.promotion;
    expect({ ...got, promotion: p && { id: p.id, title: p.title, code: p.code, kind: p.kind }, lineDiscounts: undefined }).toMatchObject(c.expect!);
    expect(Object.values(got.lineDiscounts).reduce((s, x) => s + x, 0)).toBe(got.discountPaise);
  });
});

describe.each(["offers", "referrals"])("offerOpenFor vectors in %s.json", (name) => {
  const file = loadVectors(name);
  test.each(file.cases.filter((c) => c.call === "offerOpenFor").map((c) => [c.id, c] as const))("%s", (_id, c) => {
    const i = resolveTimes(c.input, new Date(file.now)) as { promotion: D; uid: string | null; usesTotal: number; usesByUser: number; hasPlacedOrder: boolean };
    expect({ open: offerOpenFor(promo("p", i.promotion), i.uid, i.usesTotal, i.usesByUser, i.hasPlacedOrder, new Date(file.now)) }).toEqual(c.expect);
  });
});

describe("orders-state.json transitions, pure", () => {
  const file = loadVectors("orders-state");
  const cases = file.cases.filter((c) => (c.call === "adminUpdateOrder" || c.call === "cancelOrder") && c.as !== "bob" && c.error !== "FORBIDDEN" && c.error !== "NOT_FOUND" && c.error !== "BAD_REQUEST");
  test.each(cases.map((c) => [c.id, c] as const))("%s", (_id, c) => {
    const o = startingDocs(file, c)[`orders/${c.input.orderId as string}`] as Parameters<typeof staffStep>[0];
    if (c.call === "cancelOrder") {
      const note = customerCancelNote(o);
      if (c.error) expect(note).toBeNull();
      else expect(note).toBe((c.then?.[`orders/${c.input.orderId as string}`] as { events: { note?: string }[] }).events.at(-1)?.note);
      return;
    }
    const step = staffStep(o, c.input.status as OrderStatus, c.input);
    if (c.error) expect(step).toEqual({ reason: c.error, detail: c.errorDetail });
    else expect(step).toMatchObject({ status: (c.then?.[`orders/${c.input.orderId as string}`] as { status?: string } | undefined)?.status ?? c.input.status });
  });
});

test("the split sums to the discount and never passes a line", () => {
  const l = (id: string, unitPricePaise: number, qty = 1): Line => ({ variantId: id, productId: "p", categoryId: "", brandId: "", collectionIds: [], unitPricePaise, qty });
  expect(splitDiscount(1001, [l("v2", 50000), l("v3", 30000)])).toEqual({ v2: 626, v3: 375 });
  expect(splitDiscount(2, [l("a", 1), l("b", 1), l("c", 1)])).toEqual({ a: 1, b: 1, c: 0 });
  const big = splitDiscount(2_147_483_547, [l("x", 2_147_483_647), l("y", 100)]);
  expect(big.x! + big.y!).toBe(2_147_483_547);
});
