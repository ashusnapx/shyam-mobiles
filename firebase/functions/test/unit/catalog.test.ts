import { readFileSync } from "node:fs";
import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, test } from "vitest";
import { cardsFor, INDEX_WARN_BYTES, sameCard, type WithId } from "../../src/catalog/cards.js";
import * as c from "../../src/catalog/contract.js";
import { nextStock } from "../../src/catalog/stock.js";
import type { ProductDoc, VariantDoc } from "../../src/model/catalog.js";
import { reasonOf } from "../../src/shared/errors.js";

const t = Timestamp.fromMillis(1_730_000_000_000);
const product = (over: Partial<ProductDoc> = {}): ProductDoc => ({
  name: "Galaxy S25", brandId: "samsung", brandName: "Samsung", categoryId: "smartphones", categoryKind: "phone",
  description: "", specs: [], gstRateBp: 1800, isActive: true, isFeatured: false, images: [], createdAt: t, updatedAt: t, ...over,
});
const variant = (id: string, over: Partial<VariantDoc> = {}): WithId<VariantDoc> => ({
  id, productId: "s25", productName: "Galaxy S25", productActive: true, sku: id.toUpperCase(), name: id, attributes: {},
  pricePaise: 100, mrpPaise: 200, stock: 1, isActive: true, sort: 0, lastStockChange: "staff", restockSeq: 0,
  createdAt: t, updatedAt: t, ...over,
});
const reason = (f: () => unknown) => { try { f(); } catch (e) { return reasonOf(e); } return null; };

describe("nextStock: the one stock rule", () => {
  test("0 → > 0 bumps restockSeq; other moves keep it", () => {
    expect(nextStock("v", { stock: 0, restockSeq: 2 }, { set: 5 })).toEqual({ stock: 5, restockSeq: 3 });
    expect(nextStock("v", { stock: 0 }, { delta: 1 })).toEqual({ stock: 1, restockSeq: 1 });
    expect(nextStock("v", { stock: 3, restockSeq: 2 }, { delta: -3 })).toEqual({ stock: 0, restockSeq: 2 });
    expect(nextStock("v", { stock: 3, restockSeq: 2 }, { set: 9 })).toEqual({ stock: 9, restockSeq: 2 });
    expect(nextStock("v", { stock: 0, restockSeq: 2 }, { set: 0 })).toEqual({ stock: 0, restockSeq: 2 });
  });
  test("never negative, never past 1e6, whole numbers only", () => {
    expect(reason(() => nextStock("v1", { stock: 2 }, { delta: -3 }))).toBe("OUT_OF_STOCK");
    expect(reason(() => nextStock("v1", { stock: 0 }, { set: 1_000_001 }))).toBe("BAD_REQUEST");
    expect(reason(() => nextStock("v1", { stock: 0 }, { delta: 0.5 }))).toBe("BAD_REQUEST");
  });
});

describe("cardsFor: one product's index entries", () => {
  test("cheapest active variant's price and MRP, stock over active variants, first photo, fits", () => {
    const { public: card, staff } = cardsFor("s25", product({
      images: [{ path: "s25/2.webp", sort: 1 }, { path: "s25/1.webp", sort: 0 }],
      specs: [{ label: "Fits", value: "iPhone 16" }],
    }), [
      variant("b", { pricePaise: 300, mrpPaise: 400, stock: 0, sort: 1 }),
      variant("a", { pricePaise: 200, mrpPaise: 250, stock: 0, sort: 0 }),
      variant("h", { pricePaise: 50, stock: 9, isActive: false, sort: 2 }),
    ], ["deals"]);
    expect(card).toMatchObject({ s: "s25", p: 200, m: 250, i: false, cv: "s25/1.webp", v: "a b", col: ["deals"], ft: ["iPhone 16"], t: t.toMillis() });
    expect(staff?.variants.map((r) => r.id)).toEqual(["a", "b", "h"]);
    expect(staff).toMatchObject({ active: true, u: t.toMillis() });
  });
  test("hidden or variant-less products are staff-only; deleted ones leave both", () => {
    expect(cardsFor("s25", product({ isActive: false }), [variant("a")], []).public).toBeNull();
    expect(cardsFor("s25", product(), [variant("a", { isActive: false })], []).public).toBeNull();
    expect(cardsFor("s25", product(), [], []).staff).not.toBeNull();
    expect(cardsFor("s25", null, [variant("a")], [])).toEqual({ public: null, staff: null });
  });
  test("a partial product doc (no specs, images or stamps) still gets entries", () => {
    const partial = { name: "X", brandId: "b", brandName: "B", categoryId: "c", categoryKind: "phone", isActive: true, isFeatured: false } as unknown as ProductDoc;
    expect(cardsFor("x", partial, [variant("a", { updatedAt: undefined as never })], []).public).toMatchObject({ cv: null, t: 0 });
  });
  test("sameCard ignores key order", () => {
    expect(sameCard({ a: 1, b: [{ x: 1, y: 2 }] }, { b: [{ y: 2, x: 1 }], a: 1 })).toBe(true);
    expect(sameCard({ a: 1 }, { a: 2 })).toBe(false);
    expect(sameCard(undefined, undefined)).toBe(true);
  });
});

describe("seed/dev.json", () => {
  const { docs } = JSON.parse(readFileSync(new URL("../../../seed/dev.json", import.meta.url), "utf8")) as { docs: Record<string, Record<string, unknown>> };
  const of = (prefix: string) => Object.entries(docs).filter(([p]) => p.startsWith(prefix)).map(([p, d]) => ({ ...d, id: p.slice(prefix.length) }));

  test("every product and variant passes its callable's contract", () => {
    for (const p of of("products/")) {
      const { name, brandId, categoryId, description, specs, gstRateBp, isActive, isFeatured } = p as unknown as ProductDoc;
      expect(c.saveProduct.input.safeParse({ id: null, slug: p.id, name, brandId, categoryId, description, specs, gstRateBp, isActive, isFeatured }).success, p.id).toBe(true);
      expect(docs[`brands/${brandId}`], p.id).toBeDefined();
      expect(docs[`categories/${categoryId}`], p.id).toBeDefined();
    }
    for (const v of of("variants/")) {
      const { productId, sku, name, attributes, pricePaise, mrpPaise, stock, isActive, sort } = v as unknown as VariantDoc;
      expect(c.saveVariant.input.safeParse({ productId, id: null, sku, name, attributes, pricePaise, mrpPaise, stock, isActive, sort }).success, v.id).toBe(true);
      expect(docs[`products/${productId}`], v.id).toBeDefined();
    }
  });

  test(`the staff index of twice the seed stays under ${INDEX_WARN_BYTES} bytes`, () => {
    const variants = of("variants/") as unknown as WithId<VariantDoc>[];
    const cards: Record<string, unknown> = {};
    for (const copy of ["", "-copy"]) {
      for (const p of of("products/")) {
        const doc = { ...p, createdAt: t, updatedAt: t, images: [{ path: `${p.id}/1730000000000.webp`, sort: 0 }] } as unknown as ProductDoc;
        const vs = variants.filter((v) => v.productId === p.id).map((v) => ({ ...v, updatedAt: t }));
        cards[p.id + copy] = cardsFor(p.id + copy, doc, vs, ["under-1500"]).staff;
      }
    }
    expect(JSON.stringify(cards).length).toBeLessThan(INDEX_WARN_BYTES);
  });
});
