import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Owner: engineer C. docs/FIREBASE.md §3. Customers never read `promotions` (hidden and personal codes must not be
// listable): they read publicOffers and their own users/{uid}/coupons mirrors.

export type PromotionKind = "percent" | "flat" | "free_delivery";
export type TargetType = "product" | "category" | "brand" | "collection";

/** promotions/{id} (S, savePromotion) */
export interface PromotionDoc {
  title: string;
  description: string;
  code: string | null; // null: an automatic sale
  kind: PromotionKind;
  value: number; // percent 1..90, flat paise, 0 for free delivery
  maxDiscountPaise?: number | null;
  minSubtotalPaise: number;
  appliesTo: "order" | "items";
  targets: { type: TargetType; id: string }[];
  startsAt: Timestamp;
  endsAt?: Timestamp | null;
  usageLimit?: number | null;
  perUserLimit?: number | null; // savePromotion defaults it to 1 (the SQL default); null = no limit
  firstOrderOnly: boolean;
  onlineOnly: boolean;
  isPublic: boolean;
  uid?: string | null; // a personal coupon's owner
  isActive: boolean;
  showBanner: boolean;
  usesActive: number; // S: redemptions of orders not cancelled
  discountTotalPaise: number; // S
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** The fields of a promotion a customer may see (publicOffers/*, users/{uid}/coupons/*). */
export type PublicPromotion = Omit<PromotionDoc, "usesActive" | "discountTotalPaise" | "uid" | "isPublic" | "showBanner">;

/** promoCodes/{CODE} (S, never client-readable) */
export interface PromoCodeDoc {
  promotionId: string;
}

/** publicOffers/{promotionId} (S) */
export interface PublicOfferDoc extends PublicPromotion {
  usedUp: boolean;
}

/** users/{uid}/coupons/{promotionId} (S): a personal promotion's mirror. */
export type CouponDoc = PublicOfferDoc;

/** redemptions/{orderId} (S). active flips false only on cancel or expiry, never on refund. */
export interface RedemptionDoc {
  promotionId: string;
  uid: string | null;
  discountPaise: number;
  active: boolean;
  createdAt: Timestamp;
}

/** referralCodes/{CODE} (S) */
export interface ReferralCodeDoc {
  uid: string;
}

/** referrals/{refereeUid} (S): one per referee, created by applyReferralCode. */
export interface ReferralDoc {
  referrerUid: string;
  status: "pending" | "rewarded" | "void";
  rewardedAt?: Timestamp;
  createdAt: Timestamp;
}

export const retention: Record<string, Retention> = {
  promotions: { kind: "shop" },
  promoCodes: { kind: "shop" },
  publicOffers: { kind: "shop" },
  "users/*/coupons": { kind: "account" },
  redemptions: { kind: "ttl", field: "purgeAt", days: 8 * 366 }, // with the order it belongs to
  referralCodes: { kind: "account" },
  referrals: { kind: "account" },
};
