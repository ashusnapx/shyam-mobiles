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

export function evaluate(p: Promo, lines: readonly Line[], subtotal: number, baseFee: number, fees: Fees, who: Shopper): Evaluated {
  const now = who.now.getTime();
  if (p.startsAt.getTime() > now) return { error: "COUPON_NOT_STARTED" };
  if (p.endsAt && p.endsAt.getTime() <= now) return { error: "COUPON_EXPIRED" };
  if (p.usageLimit != null && p.usesActive >= p.usageLimit) return { error: "COUPON_USED_UP" };
  if (p.perUserLimit != null && who.usesByUser(p.id) >= p.perUserLimit) return { error: "COUPON_LIMIT_REACHED" };
  if (p.firstOrderOnly && who.hasOrder) return { error: "COUPON_FIRST_ORDER" };
  if (p.onlineOnly && who.method === "cod") return { error: "COUPON_ONLINE_ONLY" };
  const covered = lines.filter((l) => covers(p, l));
  if (covered.length === 0) return { error: "COUPON_NOT_APPLICABLE" };
  const eligible = covered.reduce((s, l) => s + lineTotal(l), 0);
  if (eligible < p.minSubtotalPaise) return { error: "COUPON_MIN_ORDER", detail: p.minSubtotalPaise };
  let discount = p.kind === "percent" ? Math.min(Math.floor((eligible * p.value) / 100), p.maxDiscountPaise ?? eligible)
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
    lineDiscounts: promo && discount > 0 ? splitDiscount(discount, lines.filter((l) => covers(promo, l))) : {},
  };
}

/** One cart line as placeOrder sees it: null variant = deleted. */
export interface PlaceLine extends Line {
  stock: number;
  available: boolean; // variant and product active
}

/** placeOrder's refusals in the SQL's order, before pricing (CART_EMPTY … OUT_OF_STOCK). */
export function placeRefusal(a: { lineCount: number; addressFound: boolean; method: PaymentMethod; pendingOnline: number; lines: readonly PlaceLine[]; missing: readonly string[] }):
  { reason: "CART_EMPTY" | "CART_LIMIT" | "ADDRESS_NOT_FOUND" | "PENDING_LIMIT" | "OUT_OF_STOCK"; detail?: string | string[] } | null {
  if (a.lineCount === 0) return { reason: "CART_EMPTY" };
  if (a.lineCount > 10) return { reason: "CART_LIMIT", detail: "at most 10 lines per order" };
  if (!a.addressFound) return { reason: "ADDRESS_NOT_FOUND" };
  if (a.method === "online" && a.pendingOnline >= 2) return { reason: "PENDING_LIMIT" };
  const out = [...a.missing, ...a.lines.filter((l) => !l.available || l.stock < l.qty).map((l) => l.variantId)].sort();
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
