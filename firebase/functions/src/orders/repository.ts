import { randomBytes, randomUUID } from "node:crypto";
import { Timestamp, type DocumentReference, type Transaction } from "firebase-admin/firestore";
import { applyStockChange } from "../catalog/stock.js";
import type { ProductDoc, VariantDoc } from "../model/catalog.js";
import type { OrderDoc } from "../model/orders.js";
import type { StoreSettingsDoc } from "../model/settings.js";
import { mirrorOf, mirrorPath, referralCoupon, type Promotion } from "../offers/promotion.js";
import { db } from "../shared/db.js";
import { LIMITS, nextHits } from "../shared/rateLimit.js";
import type { Line, Promo } from "./pricing.js";

// Owner: engineer C. Firestore reads and writes for orders, offers and referrals, each taking the caller's transaction
// (reads first, then writes: Firestore's rule). The decisions are in pricing.ts, state.ts and offers/promotion.ts.

export const doc = (path: string) => db().doc(path);
export const DAY = 86_400_000;
export const purgeAt = (now: Date) => new Date(now.getTime() + 8 * 366 * DAY); // GST records (model/orders.ts)

/** A Timestamp (or Date, in tests) as a Date; anything else null. */
export const date = (v: unknown): Date | null => (v instanceof Timestamp ? v.toDate() : v instanceof Date ? v : null);

export function promotionOf(d: Record<string, unknown>): Promotion {
  return { ...(d as unknown as Promotion), startsAt: date(d.startsAt) ?? new Date(0), endsAt: date(d.endsAt), createdAt: date(d.createdAt) ?? new Date(0),
    updatedAt: date(d.updatedAt) ?? new Date(0), targets: (d.targets as Promotion["targets"] | undefined) ?? [], usesActive: (d.usesActive as number | undefined) ?? 0 };
}
export const promoOf = (id: string, p: Promotion): Promo & { isPublic: boolean; uid: string | null } => ({ ...p, id, uid: p.uid ?? null });

export async function settings(tx: Transaction): Promise<StoreSettingsDoc> {
  const s = (await tx.get(doc("settings/store"))).data() as StoreSettingsDoc | undefined;
  if (!s) throw new Error("settings/store missing");
  return s;
}

/** A non-cancelled order of [uid] exists (first-order offers, referrals). */
export async function hasOrder(tx: Transaction, uid: string): Promise<boolean> {
  return !(await tx.get(db().collection("orders").where("uid", "==", uid).where("status", "!=", "cancelled").limit(1))).empty;
}

/** [uid]'s redemptions of [promotionId] on orders not cancelled, counted up to [max]. */
export async function usesBy(tx: Transaction, promotionId: string, uid: string, max: number): Promise<number> {
  return (await tx.get(db().collection("redemptions").where("promotionId", "==", promotionId).where("uid", "==", uid)
    .where("active", "==", true).limit(max))).size;
}

/** The running automatic sales (code null, active). */
export async function sales(tx: Transaction): Promise<Promo[]> {
  const snap = await tx.get(db().collection("promotions").where("code", "==", null).where("isActive", "==", true).limit(50));
  return snap.docs.map((d) => promoOf(d.id, promotionOf(d.data())));
}

/** promoCodes/{code} → the promotion, if it is active and the caller may use it (paused or someone else's personal
 * codes look unknown). A code that can't be a doc id is unknown without a read. */
export async function promoByCode(tx: Transaction, code: string, uid: string): Promise<Promo | null> {
  if (!/^[A-Z0-9]{1,40}$/.test(code)) return null;
  const id = (await tx.get(doc(`promoCodes/${code}`))).get("promotionId") as string | undefined;
  if (!id) return null;
  const snap = await tx.get(doc(`promotions/${id}`));
  if (!snap.exists) return null;
  const p = promoOf(id, promotionOf(snap.data() ?? {}));
  return p.isActive && (p.uid === null || p.uid === uid) ? p : null;
}

export type Variant = VariantDoc & { restockSeq?: number };
const on = (flag: unknown) => flag !== false; // a flag the doc leaves out counts as on

/** The cart lines priced from the variant, product and (for collection targets) collection docs. */
export async function cartLines(tx: Transaction, lines: [string, number][], collectionIds: string[]) {
  if (lines.length === 0) return { priced: [], variants: new Map<string, Variant>(), products: new Map<string, ProductDoc>(), missing: [] };
  const vs = await tx.getAll(...lines.map(([id]) => doc(`variants/${id}`)));
  const variants = new Map(vs.filter((s) => s.exists).map((s) => [s.id, s.data() as Variant]));
  const productIds = [...new Set([...variants.values()].map((v) => v.productId))];
  const ps = productIds.length ? await tx.getAll(...productIds.map((id) => doc(`products/${id}`))) : [];
  const products = new Map(ps.filter((s) => s.exists).map((s) => [s.id, s.data() as ProductDoc]));
  const cs = collectionIds.length ? await tx.getAll(...collectionIds.map((id) => doc(`collections/${id}`))) : [];
  const groups = cs.map((s) => [s.id, (s.get("productIds") as string[] | undefined) ?? []] as const);
  const priced = lines.flatMap(([variantId, qty]) => {
    const v = variants.get(variantId);
    if (!v) return [];
    const p = products.get(v.productId);
    const line: Line & { stock: number; available: boolean; variant: Variant; product: ProductDoc | null } = {
      variantId, productId: v.productId, categoryId: p?.categoryId ?? "", brandId: p?.brandId ?? "",
      collectionIds: groups.filter(([, ids]) => ids.includes(v.productId)).map(([id]) => id),
      unitPricePaise: v.pricePaise, qty, stock: v.stock, variant: v, product: p ?? null,
      available: p !== undefined && on(v.isActive) && on(v.productActive) && on(p.isActive),
    };
    return [line];
  });
  return { priced, variants, products, missing: lines.map(([id]) => id).filter((id) => !variants.has(id)) };
}

/** The collection ids any of [promos] targets. */
export const targetedCollections = (promos: readonly (Promo | null)[]) =>
  [...new Set(promos.flatMap((p) => p?.targets.filter((t) => t.type === "collection").map((t) => t.id) ?? []))];

/** Moves stock through engineer B's one stock writer. */
export function moveStock(tx: Transaction, id: string, v: Variant, delta: number, by: VariantDoc["lastStockChange"], now: Date) {
  applyStockChange(tx, doc(`variants/${id}`), v, { delta }, by, Timestamp.fromDate(now));
}

/** ± one use on a promotion (place, cancel, expiry, a revived expiry), flipping its mirror's usedUp when it crosses. */
export function changeUses(tx: Transaction, id: string, p: Promotion, uses: number, discount: number, now: Date) {
  const after = { ...p, usesActive: p.usesActive + uses, discountTotalPaise: (p.discountTotalPaise || 0) + discount, updatedAt: now };
  tx.update(doc(`promotions/${id}`), { usesActive: after.usesActive, discountTotalPaise: after.discountTotalPaise, updatedAt: now });
  const mirror = mirrorPath(id, p);
  if (mirror && mirrorOf(p).usedUp !== mirrorOf(after).usedUp) tx.set(doc(mirror), mirrorOf(after));
}

/** What a cancel or expiry undoes: stock back, the coupon use given back. Read in [tx] first, then write. */
export async function readUndo(tx: Transaction, orderId: string, o: Pick<OrderDoc, "items">) {
  const vs = await tx.getAll(...o.items.map((i) => doc(`variants/${i.id}`)));
  const red = await tx.get(doc(`redemptions/${orderId}`));
  const r = red.data() as { promotionId: string; discountPaise: number; active: boolean } | undefined;
  const promo = r ? await tx.get(doc(`promotions/${r.promotionId}`)) : null;
  return {
    variants: vs,
    /** sign −1 undoes the order (cancel, expiry), +1 redoes it (a late payment revives an expired order). */
    write(sign: 1 | -1, now: Date) {
      o.items.forEach((item, k) => {
        const s = vs[k];
        if (s?.exists) moveStock(tx, s.id, s.data() as Variant, -sign * item.qty, "order", now);
      });
      if (r && r.active === (sign === -1)) {
        tx.update(red.ref, { active: sign === 1 });
        if (promo?.exists) changeUses(tx, promo.id, promotionOf(promo.data() ?? {}), sign, sign * r.discountPaise, now);
      }
    },
  };
}

const hex = (n: number) => randomBytes(n).toString("hex").toUpperCase().slice(0, n);

/** A referral coupon: the promotion (UUID id, so /offers/{id} links keep their format), its code and the owner's mirror. */
export function writeReferralCoupon(tx: Transaction, kind: "friend" | "reward", uid: string, s: StoreSettingsDoc["referral"], now: Date) {
  const id = randomUUID();
  const code = `${kind === "friend" ? "FRIEND" : "REWARD"}${hex(10)}`;
  const p = referralCoupon(kind, uid, code, s, now);
  tx.create(doc(`promotions/${id}`), p);
  tx.create(doc(`promoCodes/${code}`), { promotionId: id });
  tx.set(doc(`users/${uid}/coupons/${id}`), mirrorOf(p));
  return { id, p };
}

/** Appends a hit of [key] to rateLimits/{uid} read as [snap] (couponFails: failed lookups, not every call). */
export function addHit(tx: Transaction, ref: DocumentReference, hits: Timestamp[] | undefined, key: "couponFails", now: Date) {
  const next = nextHits((hits ?? []).map((t) => t.toMillis()), now.getTime(), LIMITS[key]);
  if (next === null) return;
  tx.set(ref, { [key]: next.map((t) => Timestamp.fromMillis(t)), expireAt: new Date(now.getTime() + DAY) }, { merge: true });
}

/** Too many failed coupon lookups in the window? */
export const couponsBlocked = (hits: Timestamp[] | undefined, now: Date) =>
  nextHits((hits ?? []).map((t) => t.toMillis()), now.getTime(), LIMITS.couponFails) === null;
