import type { CatalogCard, ProductDoc, StaffCatalogCard, StaffVariantRow, VariantDoc } from "../model/catalog.js";

// One product's entries in catalogIndex/public and catalogIndex/staff (docs/FIREBASE.md D3), computed from its source
// docs only, so recomputing is idempotent. Mirrors the product_cards view: a public card needs an active product with
// at least one active variant; the price is the cheapest active variant's, with that variant's MRP; in stock when the
// active variants hold any stock; the cover is the first photo.

export type WithId<T> = T & { id: string };

/** Firestore warns at 1 MiB; the trigger logs past this, and the unit test keeps the seed ×2 under it. */
export const INDEX_WARN_BYTES = 700_000;

const bySort = (a: WithId<VariantDoc>, b: WithId<VariantDoc>) => a.sort - b.sort || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

export function cardsFor(
  id: string,
  product: ProductDoc | null,
  variants: WithId<VariantDoc>[],
  collectionIds: string[],
): { public: CatalogCard | null; staff: StaffCatalogCard | null } {
  if (product === null) return { public: null, staff: null };
  // Docs written by hand or by an older shape (tests, the import) may lack lists or stamps: treat them as empty.
  const { images = [], specs = [] } = product as Partial<ProductDoc>;
  const ms = (t: { toMillis(): number } | undefined) => t?.toMillis() ?? 0;
  const all = [...variants].sort(bySort);
  const active = all.filter((v) => v.isActive);
  const cheapest = active.reduce<WithId<VariantDoc> | null>((best, v) => (best === null || v.pricePaise < best.pricePaise ? v : best), null);
  const cover = [...images].sort((a, b) => a.sort - b.sort)[0]?.path ?? null;
  const fits = specs.filter((s) => s.label === "Fits").map((s) => s.value);
  const card: CatalogCard = {
    n: product.name,
    s: id,
    b: product.brandId,
    bn: product.brandName,
    c: product.categoryId,
    k: product.categoryKind,
    v: active.map((v) => v.name).join(" "),
    p: cheapest?.pricePaise ?? 0,
    m: cheapest?.mrpPaise ?? 0,
    i: active.some((v) => v.stock > 0),
    f: product.isFeatured,
    cv: cover,
    col: [...collectionIds].sort(),
    t: ms(product.createdAt),
    ...(fits.length > 0 ? { ft: fits } : {}),
  };
  const rows: StaffVariantRow[] = all.map((v) => ({ id: v.id, sku: v.sku, n: v.name, p: v.pricePaise, m: v.mrpPaise, st: v.stock, a: v.isActive, u: ms(v.updatedAt) }));
  return {
    public: product.isActive && cheapest !== null ? card : null,
    staff: { ...card, active: product.isActive, u: ms(product.updatedAt), variants: rows },
  };
}

/** Deep equality for the JSON-shaped cards, whatever the key order (Firestore hands maps back sorted), so an unchanged
 * entry is never rewritten. */
export function sameCard(a: unknown, b: unknown): boolean {
  const canon = (x: unknown): unknown =>
    Array.isArray(x) ? x.map(canon)
    : x !== null && typeof x === "object" ? Object.fromEntries(Object.entries(x).sort(([k], [l]) => (k < l ? -1 : 1)).map(([k, v]) => [k, canon(v)]))
    : x;
  return JSON.stringify(canon(a)) === JSON.stringify(canon(b));
}
