import type { PromotionKind, TargetType } from "../model/offers.js";
import type { PaymentMethod } from "../model/orders.js";
import { MAX_ORDER_PAISE } from "../shared/money.js";

// Owner: engineer C. The one pricing path (docs/FIREBASE.md §5), a pure port of private.price_lines +
// evaluate_promotion + the discount split (supabase/migrations/20261030000260_best_offer.sql). quoteOrder and
// placeOrder both call price(); the handlers only load the documents. Vectors: test-vectors/{pricing,offers}.json.

export interface Line {
  variantId: string;
  productId: string;
  categoryId: string;
  brandId: string;
  collectionIds: readonly string[];
  unitPricePaise: number;
  qty: number;
  // What a pack offer reads (absent: not a phone, no accessory type, fits nothing)
  productName?: string;
  brandName?: string;
  categoryKind?: string;
  fits?: readonly string[]; // the product's "Fits" spec values
  forModel?: string | null; // made-to-order lines: the customer's phone model
}

export interface Promo {
  id: string;
  title: string;
  code: string | null;
  kind: PromotionKind;
  value: number;
  maxDiscountPaise?: number | null;
  minSubtotalPaise: number;
  appliesTo: "order" | "items";
  targets: readonly { type: TargetType; id: string }[];
  packTypes?: readonly string[]; // pack: the accessory types the phone needs alongside
  packWhole?: boolean; // pack: the phone is discounted too
  startsAt: Date;
  endsAt?: Date | null;
  usageLimit?: number | null;
  perUserLimit?: number | null;
  firstOrderOnly: boolean;
  onlineOnly: boolean;
  isActive: boolean;
  usesActive: number;
}

/** The caller as the offer rules see them. */
export interface Shopper {
  method: PaymentMethod | null;
  now: Date;
  hasOrder: boolean; // an order that isn't cancelled
  usesByUser: (promotionId: string) => number; // their redemptions on orders not cancelled
}

export interface Fees {
  deliveryFeePaise: number;
  freeDeliveryMinPaise: number;
}

export type CouponReason =
  | "COUPON_RATE_LIMIT" | "COUPON_NOT_FOUND" | "COUPON_NOT_STARTED" | "COUPON_EXPIRED" | "COUPON_USED_UP"
  | "COUPON_LIMIT_REACHED" | "COUPON_FIRST_ORDER" | "COUPON_ONLINE_ONLY" | "COUPON_NOT_APPLICABLE" | "COUPON_MIN_ORDER"
  | "COUPON_BETTER_OFFER";

type Evaluated = { error: CouponReason; detail?: number } | { error: null; discount: number; fee: number; saving: number };

/** The typed code as looked up: null = none typed; promo null = unknown, paused or someone else's. */
export type CodeLookup = null | { rateLimited: true } | { rateLimited: false; promo: Promo | null };

export interface Priced {
  subtotalPaise: number;
  deliveryFeePaise: number;
  discountPaise: number;
  totalPaise: number;
  promotion: Promo | null;
  couponError: CouponReason | null;
  couponErrorDetail: number | null;
  /** variantId → its share of discountPaise (covered lines only). */
  lineDiscounts: Record<string, number>;
}

export const lineTotal = (l: Line) => l.unitPricePaise * l.qty;

export function covers(p: Pick<Promo, "appliesTo" | "targets">, l: Line): boolean {
  return p.appliesTo === "order" || p.targets.some((t) =>
    t.type === "product" ? t.id === l.productId
      : t.type === "category" ? t.id === l.categoryId
        : t.type === "brand" ? t.id === l.brandId
          : l.collectionIds.includes(t.id));
}

export const PACK_TYPES = ["glass", "case", "lens", "charger", "earphones"] as const;
type PackType = (typeof PACK_TYPES)[number];

/** A line's accessory type from its product name and category slug, first match wins (the SQL's accessory_type). */
export function accessoryType(l: Pick<Line, "productName" | "categoryId">): PackType | null {
  const n = (l.productName ?? "").toLowerCase();
  const has = (...words: string[]) => words.some((w) => n.includes(w));
  if (has("lens")) return "lens";
  if (l.categoryId === "screen-guards" || has("glass", "screen guard", "screen protector")) return "glass";
  if (l.categoryId === "cases-covers" || has("case", "cover")) return "case";
  if (has("charger", "adapter")) return "charger";
  if (l.categoryId === "earbuds-headphones" || has("earphone", "earbud", "buds", "headphone", "airpods")) return "earphones";
  return null;
}

/** The name without a leading "<brand> " (app product_tile.dart shortName). */
export const shortName = (name: string, brand: string) =>
  name.length > brand.length + 1 && name.toLowerCase().startsWith(`${brand.toLowerCase()} `) ? name.slice(brand.length + 1) : name;

const modelKey = (s: string) => s.toLowerCase().replace(/ /g, "");

/** Does accessory [a] fit phone [p]: chargers and earphones fit all; else a "Fits" value names it, or the made-to-order model does. */
function fits(a: Line, type: PackType, p: Line): boolean {
  if (type === "charger" || type === "earphones") return true;
  const names = [p.productName ?? "", shortName(p.productName ?? "", p.brandName ?? "")];
  return (a.fits ?? []).some((f) => names.includes(f)) || (!!a.forModel && names.some((n) => modelKey(n) === modelKey(a.forModel ?? "")));
}

/** The lines [p] discounts: the ones its targets cover; for a pack, the first phone (priciest, then lowest id) in its
 * categories with a fitting line of every pack type, its fitting accessories of those types and, if packWhole, itself. */
export function eligibleLines(p: Pick<Promo, "kind" | "appliesTo" | "targets" | "packTypes" | "packWhole">, lines: readonly Line[]): Line[] {
  if (p.kind !== "pack") return lines.filter((l) => covers(p, l));
  const types = p.packTypes ?? [];
  const typed = lines.map((l) => ({ l, type: accessoryType(l) }));
  const phones = lines.filter((l) => l.categoryKind === "phone" && p.targets.some((t) => t.type === "category" && t.id === l.categoryId))
    .sort((a, b) => b.unitPricePaise - a.unitPricePaise || (a.variantId < b.variantId ? -1 : a.variantId > b.variantId ? 1 : 0));
  for (const phone of phones) {
    const extras = typed.filter(({ l, type }) => l !== phone && type !== null && types.includes(type) && fits(l, type, phone));
    if (types.length > 0 && types.every((t) => extras.some((e) => e.type === t))) return [...(p.packWhole ? [phone] : []), ...extras.map((e) => e.l)];
  }
  return [];
}

export function evaluate(p: Promo, lines: readonly Line[], subtotal: number, baseFee: number, fees: Fees, who: Shopper): Evaluated {
  const now = who.now.getTime();
  if (p.startsAt.getTime() > now) return { error: "COUPON_NOT_STARTED" };
  if (p.endsAt && p.endsAt.getTime() <= now) return { error: "COUPON_EXPIRED" };
  if (p.usageLimit != null && p.usesActive >= p.usageLimit) return { error: "COUPON_USED_UP" };
  if (p.perUserLimit != null && who.usesByUser(p.id) >= p.perUserLimit) return { error: "COUPON_LIMIT_REACHED" };
  if (p.firstOrderOnly && who.hasOrder) return { error: "COUPON_FIRST_ORDER" };
  if (p.onlineOnly && who.method === "cod") return { error: "COUPON_ONLINE_ONLY" };
  const covered = eligibleLines(p, lines);
  if (covered.length === 0) return { error: "COUPON_NOT_APPLICABLE" };
  const eligible = covered.reduce((s, l) => s + lineTotal(l), 0);
  if (eligible < p.minSubtotalPaise) return { error: "COUPON_MIN_ORDER", detail: p.minSubtotalPaise };
  let discount = p.kind === "percent" || p.kind === "pack" ? Math.min(Math.floor((eligible * p.value) / 100), p.maxDiscountPaise ?? eligible)
    : p.kind === "flat" ? Math.min(p.value, eligible) : 0;
  discount = Math.max(0, Math.min(discount, subtotal - 100)); // the ₹1 floor
  const fee = p.kind === "free_delivery" || subtotal - discount >= fees.freeDeliveryMinPaise ? 0 : fees.deliveryFeePaise;
  const saving = baseFee + discount - fee;
  return saving <= 0 ? { error: "COUPON_NOT_APPLICABLE" } : { error: null, discount, fee, saving };
}

/** Splits [discount] over [lines] by line total, rounding down; the rest goes to the largest line (ties: lowest id),
 * spilling to the next only past that line's total. BigInt: discount × line total can pass 2^53. */
export function splitDiscount(discount: number, lines: readonly Line[]): Record<string, number> {
  const sumLt = BigInt(lines.reduce((s, l) => s + lineTotal(l), 0));
  const rows = lines.map((l) => ({ id: l.variantId, lt: lineTotal(l), share: Number((BigInt(discount) * BigInt(lineTotal(l))) / sumLt) }))
    .sort((a, b) => b.lt - a.lt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  let rest = discount - rows.reduce((s, r) => s + r.share, 0);
  const out: Record<string, number> = {};
  for (const r of rows) {
    const extra = Math.min(r.lt - r.share, rest);
    out[r.id] = r.share + extra;
    rest -= extra;
  }
  return out;
}

const byEnd = (p: Promo) => p.endsAt?.getTime() ?? Infinity;

/** quoteOrder (forPlace false: a stronger sale reports COUPON_BETTER_OFFER) and placeOrder (forPlace true). */
export function price(a: { lines: readonly Line[]; fees: Fees; code: CodeLookup; sales: readonly Promo[]; who: Shopper; forPlace: boolean }): Priced {
  const { lines, fees, who } = a;
  const subtotal = lines.reduce((s, l) => s + lineTotal(l), 0);
  const baseFee = subtotal >= fees.freeDeliveryMinPaise ? 0 : fees.deliveryFeePaise;

  let error: CouponReason | null = null;
  let detail: number | null = null;
  let chosen: { promo: Promo; discount: number; fee: number } | null = null;
  let codeSaving = 0;
  if (a.code) {
    if (a.code.rateLimited) error = "COUPON_RATE_LIMIT";
    else if (!a.code.promo) error = "COUPON_NOT_FOUND";
    else {
      const e = evaluate(a.code.promo, lines, subtotal, baseFee, fees, who);
      if (e.error) [error, detail] = [e.error, "detail" in e ? (e.detail ?? null) : null];
      else [chosen, codeSaving] = [{ promo: a.code.promo, discount: e.discount, fee: e.fee }, e.saving];
    }
  }

  let best: { promo: Promo; discount: number; fee: number; saving: number } | null = null;
  for (const p of a.sales) {
    if (p.code !== null || !p.isActive) continue;
    const e = evaluate(p, lines, subtotal, baseFee, fees, who);
    if (e.error) continue;
    if (!best || e.saving > best.saving || (e.saving === best.saving && (byEnd(p) < byEnd(best.promo) ||
      (byEnd(p) === byEnd(best.promo) && p.id < best.promo.id)))) best = { promo: p, ...e };
  }
  if (!chosen) chosen = best;
  else if (best && best.saving > codeSaving) {
    chosen = best; // the customer gets the sale and keeps the code for later
    error = a.forPlace ? null : "COUPON_BETTER_OFFER";
  }

  const discount = chosen?.discount ?? 0;
  const fee = chosen?.fee ?? baseFee;
  const promo = chosen?.promo ?? null;
  return {
    subtotalPaise: subtotal,
    deliveryFeePaise: fee,
    discountPaise: discount,
    totalPaise: subtotal + fee - discount,
    promotion: promo,
    couponError: error,
    couponErrorDetail: detail,
    lineDiscounts: promo && discount > 0 ? splitDiscount(discount, eligibleLines(promo, lines)) : {},
  };
}

/** One cart line as placeOrder sees it: null variant = deleted. */
export interface PlaceLine extends Line {
  stock: number;
  available: boolean; // variant and product active
  madeToOrder?: boolean; // no stock kept: never OUT_OF_STOCK for its count
}

/** A made-to-order line's phone model, tidied (trimmed, spaces collapsed), or null when it isn't one (MODEL_REQUIRED). */
export function tidyModel(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const s = raw.trim().replace(/\s+/g, " ");
  return s.length >= 2 && s.length <= 60 && /^[A-Za-z0-9][A-Za-z0-9 +()./'-]*$/.test(s) ? s : null;
}

/** catalogIndex/models after a delivered order named [added]: tidied, only letters/digits/spaces/+-. (60 chars max),
 * newest first, one per lowercase-without-spaces key, at most 300. */
export function learnModels(names: readonly string[], added: readonly string[]): string[] {
  const key = (n: string) => n.toLowerCase().replace(/ /g, "");
  const out: string[] = [];
  const clean = added.flatMap((a) => { const t = tidyModel(a); return t && /^[A-Za-z0-9 +.-]+$/.test(t) ? [t] : []; });
  for (const n of [...clean, ...names]) if (!out.some((o) => key(o) === key(n))) out.push(n);
  return out.slice(0, 300);
}

/** placeOrder's refusals in the SQL's order, before pricing (CART_EMPTY … OUT_OF_STOCK). */
export function placeRefusal(a: { lineCount: number; addressFound: boolean; method: PaymentMethod; pendingOnline: number; lines: readonly PlaceLine[]; missing: readonly string[] }):
  { reason: "CART_EMPTY" | "CART_LIMIT" | "ADDRESS_NOT_FOUND" | "PENDING_LIMIT" | "OUT_OF_STOCK"; detail?: string | string[] } | null {
  if (a.lineCount === 0) return { reason: "CART_EMPTY" };
  if (a.lineCount > 10) return { reason: "CART_LIMIT", detail: "at most 10 lines per order" };
  if (!a.addressFound) return { reason: "ADDRESS_NOT_FOUND" };
  if (a.method === "online" && a.pendingOnline >= 2) return { reason: "PENDING_LIMIT" };
  const out = [...a.missing, ...a.lines.filter((l) => !l.available || (!l.madeToOrder && l.stock < l.qty)).map((l) => l.variantId)].sort();
  return out.length ? { reason: "OUT_OF_STOCK", detail: out } : null;
}

/** After pricing: the code's refusal, ORDER_TOO_LARGE, COD_UNAVAILABLE. */
export function pricedRefusal(p: Priced, method: PaymentMethod, cod: { codEnabled: boolean; codMaxPaise: number }):
  { reason: CouponReason | "ORDER_TOO_LARGE" | "COD_UNAVAILABLE"; detail?: number } | null {
  if (p.couponError) return p.couponErrorDetail === null ? { reason: p.couponError } : { reason: p.couponError, detail: p.couponErrorDetail };
  if (p.subtotalPaise + p.deliveryFeePaise > MAX_ORDER_PAISE) return { reason: "ORDER_TOO_LARGE" };
  if (method === "cod" && (!cod.codEnabled || p.totalPaise > cod.codMaxPaise)) return { reason: "COD_UNAVAILABLE" };
  return null;
}

/** The order invariants (docs/FIREBASE.md §3), checked before every order write. Throws: a bug, never user input. */
export function assertOrderTotals(o: { subtotalPaise: number; deliveryFeePaise: number; discountPaise: number; totalPaise: number;
  items: readonly { unitPricePaise: number; qty: number; discountPaise: number }[] }): void {
  const ok = o.items.length >= 1 && o.items.length <= 10 &&
    o.items.every((i) => Number.isInteger(i.qty) && i.qty >= 1 && i.qty <= 5 && i.discountPaise >= 0 && i.discountPaise <= i.unitPricePaise * i.qty) &&
    o.items.reduce((s, i) => s + i.unitPricePaise * i.qty, 0) === o.subtotalPaise &&
    o.items.reduce((s, i) => s + i.discountPaise, 0) === o.discountPaise &&
    o.discountPaise >= 0 && (o.discountPaise === 0 || o.discountPaise <= o.subtotalPaise - 100) &&
    o.totalPaise === o.subtotalPaise + o.deliveryFeePaise - o.discountPaise && o.totalPaise <= MAX_ORDER_PAISE &&
    [o.subtotalPaise, o.deliveryFeePaise, o.discountPaise, o.totalPaise].every(Number.isSafeInteger);
  if (!ok) throw new Error("order totals broken");
}

/** private.offer_open: may [uid] (null: signed out) use [p] right now? The app's offerOpenFor is the same rule. */
export function offerOpenFor(p: Promo & { isPublic: boolean; uid?: string | null }, uid: string | null, usesTotal: number, usesByUser: number,
  hasPlacedOrder: boolean, now: Date): boolean {
  const t = now.getTime();
  return p.isActive && p.startsAt.getTime() <= t && (p.endsAt == null || p.endsAt.getTime() > t) &&
    ((p.isPublic && p.uid == null) || (uid !== null && p.uid === uid)) &&
    (p.usageLimit == null || usesTotal < p.usageLimit) &&
    (uid === null || ((p.perUserLimit == null || usesByUser < p.perUserLimit) && !(p.firstOrderOnly && hasPlacedOrder)));
}
