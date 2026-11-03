import type { PromotionDoc } from "../model/offers.js";

// Owner: engineer C. Pure promotion rules: savePromotion's checks (admin_save_promotion and the promotions table
// constraints in supabase/migrations/20261030000000_offers.sql, details = errors.dart _promotionRules keys), the
// customer-visible mirror, the promotion banner and the personal coupons referrals hand out.

/** A promotion as stored, with Dates where Firestore keeps Timestamps (the Admin SDK writes Dates as Timestamps). */
export type Promotion = Omit<PromotionDoc, "startsAt" | "endsAt" | "createdAt" | "updatedAt"> &
  { startsAt: Date; endsAt: Date | null; createdAt: Date; updatedAt: Date };

/** What admin_save_promotion's insert defaulted. */
export function newPromotion(now: Date): Omit<Promotion, "title" | "kind"> {
  return {
    description: "", code: null, value: 0, maxDiscountPaise: null, minSubtotalPaise: 0, appliesTo: "order", targets: [],
    startsAt: now, endsAt: null, usageLimit: null, perUserLimit: 1, firstOrderOnly: false, onlineOnly: false, isPublic: true,
    uid: null, isActive: true, showBanner: false, usesActive: 0, discountTotalPaise: 0, createdAt: now, updatedAt: now,
  };
}

/** The first broken rule (the SQL constraint name, as errors.dart knows it), or null. Targets are checked by the caller. */
export function brokenRule(p: Promotion): string | null {
  if (!(p.kind === "percent" ? p.value >= 1 && p.value <= 90 : p.kind === "flat" ? p.value >= 100 : p.value === 0)) return "promotions_value_check";
  if (p.maxDiscountPaise != null && p.kind !== "percent") return "promotions_cap_check";
  if (p.endsAt !== null && p.endsAt <= p.startsAt) return "promotions_window_check";
  if (p.uid != null && p.code === null) return "promotions_personal_check";
  if (p.showBanner && !(p.isPublic && p.uid == null)) return "promotions_banner_check";
  if (p.appliesTo === "items" && p.targets.length === 0) return "items needs a target";
  return null;
}

/** Where customers see [p]: publicOffers/{id}, the owner's users/{uid}/coupons/{id}, or nowhere (a hidden code). */
export function mirrorPath(id: string, p: Pick<Promotion, "isPublic" | "uid">): string | null {
  return p.uid != null ? `users/${p.uid}/coupons/${id}` : p.isPublic ? `publicOffers/${id}` : null;
}

export const usedUp = (p: Pick<Promotion, "usageLimit" | "usesActive">) => p.usageLimit != null && p.usesActive >= p.usageLimit;

/** The mirror doc: the public fields plus usedUp (model/offers.ts PublicOfferDoc). */
export function mirrorOf(p: Promotion): Record<string, unknown> {
  const hide = new Set(["usesActive", "discountTotalPaise", "uid", "isPublic", "showBanner"]);
  return { ...Object.fromEntries(Object.entries(p).filter(([k]) => !hide.has(k))), usedUp: usedUp(p) };
}

/** sync_promotion_banner: banners/{promotionId}, or null when the promotion shows none. */
export function bannerOf(id: string, p: Promotion): Record<string, unknown> | null {
  if (!p.showBanner) return null;
  return {
    title: p.title, subtitle: p.description.replace(/\s+/g, " ").trim().slice(0, 120),
    ctaLabel: p.code === null ? "Shop the sale" : p.code.length <= 11 ? `Use code ${p.code}` : "View offer",
    link: `/offers/${id}`, tone: 0, startsAt: p.startsAt, endsAt: p.endsAt, sort: 0, isActive: p.isActive, promotionId: id,
    createdAt: p.createdAt, updatedAt: p.updatedAt,
  };
}

/** apply_referral_code's welcome coupon and reward_referral's thank-you: personal, hidden, one use, 90 days. */
export function referralCoupon(kind: "friend" | "reward", uid: string, code: string, s: { friendPaise: number; rewardPaise: number; minOrderPaise: number }, now: Date): Promotion {
  return {
    ...newPromotion(now),
    title: kind === "friend" ? "Welcome gift from a friend" : "Thanks for referring a friend",
    kind: "flat", code, value: kind === "friend" ? s.friendPaise : s.rewardPaise, minSubtotalPaise: s.minOrderPaise,
    endsAt: new Date(now.getTime() + 90 * 86_400_000), usageLimit: 1, perUserLimit: 1, firstOrderOnly: kind === "friend",
    isPublic: false, uid,
  };
}

/** The app's Offer (referrals/contract.ts offerOut). */
export function offerJson(id: string, p: Promotion) {
  return {
    id, title: p.title, description: p.description, code: p.code, kind: p.kind, value: p.value,
    maxDiscountPaise: p.maxDiscountPaise ?? null, minSubtotalPaise: p.minSubtotalPaise, appliesTo: p.appliesTo,
    startsAt: p.startsAt.toISOString(), endsAt: p.endsAt?.toISOString() ?? null, automatic: p.code === null,
    onlineOnly: p.onlineOnly, firstOrderOnly: p.firstOrderOnly,
  };
}
