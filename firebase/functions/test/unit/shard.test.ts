import { describe, expect, test } from "vitest";
import type { CatalogCard, StaffCatalogCard } from "../../src/model/catalog.js";
import { BUCKETS, bucketOf, categoryOf, chunkId, planChunks, type Entries } from "../../src/catalog/shard.js";
import { INDEX_WARN_BYTES } from "../../src/catalog/cards.js";

// 5,000 products x 4 variants = 20,000 variants, spread over 12 categories (a skewed one holds 40%), and the worst case
// of all of them in one category.
const CATS = ["phones", "cases", "chargers", "cables", "earphones", "speakers", "glass", "powerbanks", "watches", "storage", "holders", "other"];
function synth(n: number, cat: (i: number) => string): Map<string, { public: CatalogCard; staff: StaffCatalogCard }> {
  const m = new Map<string, { public: CatalogCard; staff: StaffCatalogCard }>();
  for (let i = 0; i < n; i++) {
    const id = `brand-${i % 40}-model-name-${i}`;
    const c = cat(i);
    const card: CatalogCard = { n: `Brand ${i % 40} Model Name ${i}`, s: id, b: `brand-${i % 40}`, bn: `Brand ${i % 40}`, c, k: "accessory",
      v: "4 GB Black 4 GB Blue 8 GB Black 8 GB Blue", p: 99900 + i, m: 129900 + i, i: true, f: false, cv: `${id}/1.webp`, col: ["new", "deals"], t: 1_700_000_000_000 + i };
    const variants = [0, 1, 2, 3].map((j) => ({ id: `${id}-v${j}ABCDEFGHIJKLMNOP`, sku: `SKU-${i}-${j}`, n: ["4 GB Black", "4 GB Blue", "8 GB Black", "8 GB Blue"][j]!, p: 99900, m: 129900, st: 5, a: true, u: 1_700_000_000_000 }));
    m.set(id, { public: card, staff: { ...card, active: true, u: 1_700_000_000_000, variants } });
  }
  return m;
}
const spread = (i: number) => (i % 10 < 4 ? "phones" : CATS[i % CATS.length]!);
/** Applies a plan to an in-memory store, like the transaction does. */
function apply(store: Map<string, Record<string, unknown>>, plan: ReturnType<typeof planChunks>) {
  for (const [cid, { set, del }] of plan) {
    const cards = Object.fromEntries(Object.entries({ ...store.get(cid), ...set }).filter(([id]) => !del.includes(id)));
    if (Object.keys(cards).length === 0) store.delete(cid);
    else store.set(cid, cards);
  }
}
const sizes = (store: Map<string, Record<string, unknown>>) => [...store].map(([cid, cards]) => [cid, JSON.stringify(cards).length] as const);

describe("catalog index sharding, 20,000 variants", () => {
  test("every chunk stays under the warn size, spread and worst case", () => {
    for (const cat of [spread, () => "phones"]) {
      const store = new Map<string, Record<string, unknown>>();
      apply(store, planChunks(store, synth(5000, cat)));
      const all = sizes(store);
      const staffTotal = all.filter(([c]) => c.startsWith("staff_")).reduce((s, [, b]) => s + b, 0);
      expect(staffTotal).toBeGreaterThan(INDEX_WARN_BYTES); // would not have fit one doc
      expect(Math.max(...all.map(([, b]) => b))).toBeLessThan(INDEX_WARN_BYTES);
      expect(all.filter(([c]) => c.startsWith("public_")).reduce((s, [, b]) => s + b, 0)).toBeGreaterThan(0);
    }
  });

  test("a product's chunk depends only on its id and category", () => {
    expect(chunkId("public", "phones", "x")).toBe(chunkId("public", "phones", "x"));
    expect(bucketOf("samsung-galaxy-s25")).toBe(bucketOf("samsung-galaxy-s25"));
    expect(bucketOf("samsung-galaxy-s25")).toBeLessThan(BUCKETS);
    expect(categoryOf("public_phones_3")).toBe("phones");
    const store = new Map<string, Record<string, unknown>>();
    const e = synth(2000, spread);
    apply(store, planChunks(store, e));
    for (const [cid, cards] of store) for (const id of Object.keys(cards)) expect(cid).toBe(chunkId(cid.startsWith("public_") ? "public" : "staff", e.get(id)!.public.c, id));
  });

  test("an unchanged product rewrites nothing; one edit rewrites one public and one staff chunk", () => {
    const e = synth(5000, spread);
    const store = new Map<string, Record<string, unknown>>();
    apply(store, planChunks(store, e));
    expect(planChunks(store, e).size).toBe(0);
    const id = "brand-3-model-name-1003";
    const cur = e.get(id)!;
    const edited: Entries = new Map([[id, { public: { ...cur.public, p: 1 }, staff: { ...cur.staff, p: 1 } }]]);
    const plan = planChunks(store, edited);
    expect([...plan.keys()].sort()).toEqual([chunkId("public", cur.public.c, id), chunkId("staff", cur.public.c, id)].sort());
  });

  test("a category move deletes from the old chunk and writes the new; hiding and deleting drop out", () => {
    const e = synth(100, () => "cases");
    const store = new Map<string, Record<string, unknown>>();
    apply(store, planChunks(store, e));
    const id = "brand-5-model-name-5";
    const cur = e.get(id)!;
    const moved = { public: { ...cur.public, c: "chargers" }, staff: { ...cur.staff, c: "chargers" } };
    const plan = planChunks(store, new Map([[id, moved]]));
    expect(plan.get(chunkId("public", "cases", id))?.del).toEqual([id]);
    expect(plan.get(chunkId("public", "chargers", id))?.set[id]).toEqual(moved.public);
    apply(store, plan);
    const hidden = planChunks(store, new Map([[id, { public: null, staff: { ...moved.staff, active: false } }]]));
    expect(hidden.get(chunkId("public", "chargers", id))?.del).toEqual([id]);
    expect(hidden.get(chunkId("staff", "chargers", id))?.set[id]).toBeDefined();
    apply(store, hidden);
    apply(store, planChunks(store, new Map([[id, { public: null, staff: null }]])));
    expect([...store.values()].some((c) => id in c)).toBe(false);
  });
});
