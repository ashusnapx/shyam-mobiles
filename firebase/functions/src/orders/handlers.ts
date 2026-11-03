import { FieldValue, type Timestamp, type Transaction } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import type { OrderDoc, OrderItem, PaymentMethod } from "../model/orders.js";
import type { AddressDoc } from "../model/users.js";
import { rejectConsumedAppCheck, requireStaff, requireUser } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { db } from "../shared/db.js";
import { fail, reasonOf } from "../shared/errors.js";
import { audit, log } from "../shared/log.js";
import { BACKGROUND, REPLAY_PROTECTED } from "../shared/options.js";
import { takeRateLimit } from "../shared/rateLimit.js";
import { istMonth } from "../shared/time.js";
import { v } from "../shared/validation.js";
import type { Promotion } from "../offers/promotion.js";
import * as c from "./contract.js";
import { assertOrderTotals, placeRefusal, price, pricedRefusal, type Priced } from "./pricing.js";
import {
  addHit, cartLines, changeUses, couponsBlocked, date, doc, hasOrder, moveStock, promoByCode, purgeAt, readUndo, sales,
  settings, targetedCollections, usesBy, writeReferralCoupon,
} from "./repository.js";
import { customerCancelNote, EXPIRED_NOTE, staffStep } from "./state.js";

// Owner: engineer C. Checkout and the order lifecycle (docs/FIREBASE.md §5): guard → one transaction (load → decide in
// pricing.ts / state.ts → write). Vectors: test-vectors/{pricing,offers,orders-state,referrals}.json.

const HOLD_MS = 15 * 60_000;
const defined = (o: object) => Object.fromEntries(Object.entries(o).filter(([, x]) => x !== undefined));

/** Everything quote and place read, priced. */
async function checkout(tx: Transaction, uid: string, couponCode: string | null, method: PaymentMethod | null, forPlace: boolean) {
  const now = new Date();
  const rateRef = doc(`rateLimits/${uid}`);
  const fails = (await tx.get(rateRef)).get("couponFails") as Timestamp[] | undefined;
  const cartRef = doc(`carts/${uid}`);
  const entries = Object.entries(((await tx.get(cartRef)).get("lines") ?? {}) as Record<string, { qty?: unknown }>)
    .map(([id, l]) => [id, l.qty] as [string, unknown]).sort(([a], [b]) => (a < b ? -1 : 1));
  if (entries.some(([, q]) => !v.cartQty.safeParse(q).success)) fail("BAD_REQUEST", ["qty"]); // Rules can't check map values
  const lines = entries as [string, number][];
  const shop = await settings(tx);
  const code = couponCode || null;
  const blocked = code !== null && couponsBlocked(fails, now);
  const codePromo = code !== null && !blocked ? await promoByCode(tx, code, uid) : null;
  const running = await sales(tx);
  const cart = await cartLines(tx, lines, targetedCollections([codePromo, ...running]));
  const uses = new Map<string, number>();
  for (const p of [codePromo, ...running]) if (p?.perUserLimit != null) uses.set(p.id, await usesBy(tx, p.id, uid, p.perUserLimit));
  const ordered = await hasOrder(tx, uid);
  const priced = price({
    lines: cart.priced, fees: shop, sales: running, forPlace,
    code: code === null ? null : blocked ? { rateLimited: true } : { rateLimited: false, promo: codePromo },
    who: { method, now, hasOrder: ordered, usesByUser: (id) => uses.get(id) ?? 0 },
  });
  return { now, rateRef, fails, cartRef, lines, shop, cart, priced, notFound: code !== null && !blocked && codePromo === null };
}

const quoteOut = (p: Priced) => ({
  subtotalPaise: p.subtotalPaise, deliveryFeePaise: p.deliveryFeePaise, discountPaise: p.discountPaise, totalPaise: p.totalPaise,
  promotion: p.promotion && { id: p.promotion.id, title: p.promotion.title, code: p.promotion.code, kind: p.promotion.kind },
  couponError: p.couponError, couponErrorDetail: p.couponErrorDetail,
});

export const quoteOrder = callable(c.quoteOrder, async ({ couponCode, paymentMethod }, req) => {
  const { uid } = requireUser(req);
  return db().runTransaction(async (tx) => {
    const k = await checkout(tx, uid, couponCode ?? null, paymentMethod ?? null, false);
    if (k.lines.length === 0) fail("CART_EMPTY");
    await takeRateLimit(tx, uid, "quoteOrder", k.now.getTime());
    if (k.notFound) addHit(tx, k.rateRef, k.fails, "couponFails", k.now);
    return quoteOut(k.priced);
  });
});

async function place(tx: Transaction, uid: string, input: { addressId: string; paymentMethod: PaymentMethod; couponCode?: string | null }) {
  const method = input.paymentMethod;
  const k = await checkout(tx, uid, input.couponCode ?? null, method, true);
  const address = (await tx.get(doc(`users/${uid}/addresses/${input.addressId}`))).data() as AddressDoc | undefined;
  const pendingOnline = method !== "online" ? 0 : (await tx.get(db().collection("orders").where("uid", "==", uid)
    .where("status", "==", "pending_payment").limit(20))).docs
    .filter((d) => d.get("paymentMethod") === "online" && (date(d.get("reservedUntil"))?.getTime() ?? 0) > k.now.getTime()).length;
  const counterRef = doc("counters/orders");
  const next = ((await tx.get(counterRef)).get("next") as number | undefined) ?? 100001;
  await takeRateLimit(tx, uid, "placeOrder", k.now.getTime());

  const refused = placeRefusal({ lineCount: k.lines.length, addressFound: address !== undefined, method, pendingOnline, lines: k.cart.priced, missing: k.cart.missing })
    ?? pricedRefusal(k.priced, method, k.shop);
  if (refused) fail(refused.reason, refused.detail);

  const { now, priced } = k;
  const promo = priced.promotion;
  const items: OrderItem[] = k.cart.priced.map((l) => {
    const product = l.product ?? fail("OUT_OF_STOCK", [l.variantId]);
    const cover = [...product.images].sort((a, b) => a.sort - b.sort)[0]?.path;
    return defined({
      id: l.variantId, productId: l.productId, productName: product.name, variantName: l.variant.name, imagePath: cover,
      unitPricePaise: l.unitPricePaise, qty: l.qty, gstRateBp: (product.gstRateBp as number | undefined) ?? 1800, hsnCode: product.hsnCode,
      discountPaise: priced.lineDiscounts[l.variantId] ?? 0, imeis: [],
    }) as unknown as OrderItem;
  });
  const a = address ?? fail("ADDRESS_NOT_FOUND");
  const status = method === "cod" ? "confirmed" : "pending_payment";
  const order = {
    number: `SM${next}`, uid, status, paymentMethod: method, paymentStatus: "pending",
    subtotalPaise: priced.subtotalPaise, deliveryFeePaise: priced.deliveryFeePaise, discountPaise: priced.discountPaise, totalPaise: priced.totalPaise,
    ...(promo ? { promotion: { id: promo.id, title: promo.title, code: promo.code, kind: promo.kind } } : {}),
    ...(promo?.code ? { couponCode: promo.code } : {}),
    address: defined({ name: a.name, phone: a.phone, line1: a.line1, line2: a.line2, landmark: a.landmark, city: a.city, district: a.district,
      state: a.state, stateCode: a.stateCode, pincode: a.pincode }),
    items, events: [{ status, by: "customer", byUid: uid, at: now }],
    reservedUntil: method === "online" ? new Date(now.getTime() + HOLD_MS) : null,
    createdAt: now, updatedAt: now, purgeAt: purgeAt(now),
  };
  assertOrderTotals(order);
  const ref = db().collection("orders").doc();
  tx.create(ref, order);
  for (const l of k.cart.priced) moveStock(tx, l.variantId, l.variant, -l.qty, "order", now);
  if (promo) {
    tx.create(doc(`redemptions/${ref.id}`), { promotionId: promo.id, uid, discountPaise: priced.discountPaise, active: true, createdAt: now, purgeAt: purgeAt(now) });
    changeUses(tx, promo.id, promo as unknown as Promotion, 1, priced.discountPaise, now);
  }
  tx.update(k.cartRef, { lines: {}, updatedAt: now });
  tx.set(counterRef, { next: next + 1 });
  return { orderId: ref.id };
}

/** A failed coupon guess at checkout counts toward COUPON_RATE_LIMIT, recorded after the checkout rolled back. */
async function recordCouponFail(uid: string) {
  await db().runTransaction(async (tx) => {
    const ref = doc(`rateLimits/${uid}`);
    addHit(tx, ref, (await tx.get(ref)).get("couponFails") as Timestamp[] | undefined, "couponFails", new Date());
  });
}

export const placeOrder = callable(c.placeOrder, async (input, req) => {
  rejectConsumedAppCheck(req);
  const { uid } = requireUser(req);
  try {
    return await db().runTransaction((tx) => place(tx, uid, input));
  } catch (e) {
    if (reasonOf(e) === "COUPON_NOT_FOUND") await recordCouponFail(uid);
    throw e;
  }
}, REPLAY_PROTECTED);

const event = (e: { status: string; note: string | null }, by: "customer" | "staff" | "system", byUid: string | null, at: Date) =>
  FieldValue.arrayUnion({ status: e.status, ...(e.note === null ? {} : { note: e.note }), by, ...(byUid === null ? {} : { byUid }), at });

async function readOrder(tx: Transaction, id: string) {
  const ref = doc(`orders/${id}`);
  return { ref, o: (await tx.get(ref)).data() as OrderDoc | undefined };
}

export const cancelOrder = callable(c.cancelOrder, async ({ orderId }, req) => {
  const { uid } = requireUser(req);
  await db().runTransaction(async (tx) => {
    const { ref, o } = await readOrder(tx, orderId);
    if (!o || o.uid !== uid) fail("NOT_FOUND");
    const note = customerCancelNote(o);
    if (note === null) fail("INVALID_TRANSITION");
    const undo = await readUndo(tx, orderId, o);
    const now = new Date();
    undo.write(-1, now);
    tx.update(ref, { status: "cancelled", cancelledBy: "customer", reservedUntil: null, events: event({ status: "cancelled", note }, "customer", uid, now), updatedAt: now });
  });
  return {};
});

/** reward_referral, inside the → delivered transaction: once, for a pending referral, the referee's order at least the
 * minimum, void past the referrer's monthly cap (users/{referrer}.referralRewards[IST month]). */
async function readReward(tx: Transaction, o: OrderDoc, now: Date) {
  if (o.uid === null) return null;
  const refRef = doc(`referrals/${o.uid}`);
  const r = await tx.get(refRef);
  if (r.get("status") !== "pending") return null;
  const s = (await settings(tx)).referral;
  if (o.subtotalPaise < s.minOrderPaise) return null;
  const referrer = r.get("referrerUid") as string;
  const userRef = doc(`users/${referrer}`);
  const month = istMonth(now);
  const count = (((await tx.get(userRef)).get("referralRewards") as Record<string, number> | undefined)?.[month]) ?? 0;
  return () => {
    if (count >= s.monthlyCap) return tx.update(refRef, { status: "void" });
    writeReferralCoupon(tx, "reward", referrer, s, now);
    tx.update(refRef, { status: "rewarded", rewardedAt: now });
    tx.set(userRef, { referralRewards: { [month]: count + 1 } }, { merge: true });
  };
}

export const adminUpdateOrder = callable(c.adminUpdateOrder, async (input, req) => {
  const staff = await requireStaff(req);
  await db().runTransaction(async (tx) => {
    const { ref, o } = await readOrder(tx, input.orderId);
    if (!o) fail("NOT_FOUND");
    // Mark refunded is for cash and UPI refunds: never while a PhonePe refund may still pay out
    if (o.status === "cancelled" && input.status === "refunded" && o.pendingRefundId) fail("REFUND_IN_PROGRESS");
    const step = staffStep(o, input.status, input);
    if ("reason" in step) fail(step.reason, step.detail);
    const now = new Date();
    const undo = step.restock ? await readUndo(tx, input.orderId, o) : null;
    const reward = step.status === "delivered" && o.status !== "delivered" ? await readReward(tx, o, now) : null;
    undo?.write(-1, now);
    reward?.();
    tx.update(ref, defined({
      status: step.status, paymentStatus: step.paymentStatus, courier: step.courier, trackingNumber: step.trackingNumber,
      ...(step.restock ? { cancelledBy: "staff", reservedUntil: null } : {}),
      events: step.event ? event(step.event, "staff", staff.uid, now) : undefined, updatedAt: now,
    }));
  });
  audit("orders.update", staff.uid, input.orderId, { status: input.status });
  return {};
});

export const adminSetImeis = callable(c.adminSetImeis, async ({ orderId, itemId, imeis }, req) => {
  const staff = await requireStaff(req);
  await db().runTransaction(async (tx) => {
    const { ref, o } = await readOrder(tx, orderId);
    const item = o?.items.find((x) => x.id === itemId);
    if (!o || !item) fail("NOT_FOUND");
    const qty = item.qty;
    const list = Array.isArray(imeis) ? imeis : null;
    const ok = list !== null && (list.length === 0 ||
      (list.length === qty && list.every((x) => v.imei.safeParse(x).success) && new Set(list).size === qty));
    if (!ok) fail("INVALID_IMEIS", `need ${qty} distinct 15-digit IMEIs`);
    tx.update(ref, { items: o.items.map((x) => (x === item ? { ...x, imeis: list } : x)), updatedAt: new Date() });
  });
  audit("orders.setImeis", staff.uid, orderId);
  return {};
});

/** expire_unpaid_orders: each online order whose 15-minute hold ran out, in its own transaction. Keeps reservedUntil and
 * says cancelledBy "expiry", which lets a late payment revive it (settlement.ts). */
export async function expireUnpaid(): Promise<{ expired: number }> {
  const now = new Date();
  const due = await db().collection("orders").where("status", "==", "pending_payment").where("reservedUntil", "<", now).limit(100).get();
  let expired = 0;
  for (const d of due.docs) {
    const done = await db().runTransaction(async (tx) => {
      const o = (await tx.get(d.ref)).data() as OrderDoc | undefined;
      if (o?.status !== "pending_payment" || (date(o.reservedUntil)?.getTime() ?? Infinity) >= now.getTime()) return false;
      const undo = await readUndo(tx, d.id, o);
      undo.write(-1, now);
      tx.update(d.ref, { status: "cancelled", cancelledBy: "expiry", events: event({ status: "cancelled", note: EXPIRED_NOTE }, "system", null, now), updatedAt: now });
      return true;
    });
    if (done) expired++;
  }
  return { expired };
}

export const expireUnpaidOrders = onSchedule({ schedule: "every 5 minutes", timeZone: "Asia/Kolkata", ...BACKGROUND }, async () => {
  log.info("expireUnpaidOrders", await expireUnpaid());
});
