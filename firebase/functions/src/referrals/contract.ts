import { z } from "zod";
import { contract } from "../shared/callable.js";
import { v } from "../shared/validation.js";

// Owner: engineer C. Refer & earn (docs/FIREBASE.md §3, §6). Vectors: test-vectors/referrals.json.

/** An offer as the app shows it (app/lib/core/models/offers.dart Offer). Times are ISO-8601. */
export const offerOut = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string(),
  code: z.string().nullable(),
  kind: z.enum(["percent", "flat", "free_delivery"]),
  value: z.number().int(),
  maxDiscountPaise: z.number().int().nullable(),
  minSubtotalPaise: z.number().int(),
  appliesTo: z.enum(["order", "items"]),
  startsAt: z.string(),
  endsAt: z.string().nullable(),
  onlineOnly: z.boolean(),
  firstOrderOnly: z.boolean(),
});

/** The caller's own code (made on first ask) and how far it has got. */
export const myReferral = contract(
  "myReferral",
  z.strictObject({}),
  z.object({
    enabled: z.boolean(),
    code: z.string(),
    friendPaise: z.number().int(),
    rewardPaise: z.number().int(),
    minOrderPaise: z.number().int(),
    joined: z.number().int(),
    rewarded: z.number().int(),
    canEnterCode: z.boolean(),
  }),
);

/** Links the caller to a friend's code before their first order; returns the welcome coupon. */
export const applyReferralCode = contract("applyReferralCode", z.strictObject({ code: v.typedCode }), offerOut);
