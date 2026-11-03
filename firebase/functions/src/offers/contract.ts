import { z } from "zod";
import { contract } from "../shared/callable.js";
import { cleanMultiline, cleanText, v } from "../shared/validation.js";

// Owner: engineer C. Staff promotions (docs/FIREBASE.md §1, §3). Customers read publicOffers and
// users/{uid}/coupons; there is no customer callable for listings.

const iso = z.iso.datetime({ offset: true });

const promotionFields = z.strictObject({
    title: cleanText(60, { min: 2, mustHave: "letterOrDigit" }),
    description: cleanMultiline(300),
    code: v.typedCode.pipe(v.couponCode).nullable(),
    kind: z.enum(["percent", "flat", "free_delivery"]),
    value: z.number().int().min(0),
    maxDiscountPaise: z.number().int().min(1).nullable(),
    minSubtotalPaise: z.number().int().min(0),
    appliesTo: z.enum(["order", "items"]),
    targets: z.array(z.strictObject({ type: z.enum(["product", "category", "brand", "collection"]), id: v.slug })).max(500),
    startsAt: iso,
    endsAt: iso.nullable(),
    usageLimit: z.number().int().min(1).nullable(),
    perUserLimit: z.number().int().min(1).nullable(),
    firstOrderOnly: z.boolean(),
    onlineOnly: z.boolean(),
    isPublic: z.boolean(),
    uid: v.docId.nullable(),
    isActive: z.boolean(),
    showBanner: z.boolean(),
});

/**
 * Writes the promotion, its promoCodes entry, the public or personal mirror and its banner in one transaction. Like
 * admin_save_promotion: without an id it creates (missing fields take the defaults, perUserLimit 1); with one it
 * changes only the fields sent. INVALID_PROMOTION carries the rule that failed (errors.dart _promotionRules);
 * CODE_TAKEN for a duplicate code.
 */
export const savePromotion = contract(
  "savePromotion",
  promotionFields.partial().extend({ id: v.docId.nullish() }),
  z.object({ id: z.string() }),
  "INVALID_PROMOTION",
);

/** Removes a promotion nobody has used yet; one with redemptions can only be switched off. */
export const deletePromotion = contract("deletePromotion", z.strictObject({ id: v.docId }), z.object({}));
