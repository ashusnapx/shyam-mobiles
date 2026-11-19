import { z } from "zod";
import { contract } from "../shared/callable.js";
import { cleanMultiline, v } from "../shared/validation.js";

// Owner: engineer D. A rating, a comment or both (docs/FIREBASE.md §6). Rating an order or a repair again replaces
// the earlier rating (doc id order_{id} / repair_{id}); FEEDBACK_LIMIT past 10 a day.
export const sendFeedback = contract(
  "sendFeedback",
  z.strictObject({
    kind: z.enum(["general", "order", "repair", "product", "bug"]),
    rating: z.number().int().min(1).max(5).nullish(),
    message: cleanMultiline(1000).default(""),
    orderId: v.docId.nullish(),
    repairId: v.docId.nullish(),
    productId: v.slug.nullish(),
    screen: v.feedbackScreen.nullish(),
    appVersion: v.appVersion.nullish(),
  }).refine((f) => (f.rating ?? null) !== null || f.message !== "", { message: "empty", path: ["message"] }),
  z.object({ id: z.string() }),
);

// Growth (docs/GROWTH.md §2a). A verified-purchase review: only after a delivered order of the product, one per
// customer per product (saving again replaces it); photos are the caller's own uploads under review-photos/{uid}/.
export const saveReview = contract(
  "saveReview",
  z.strictObject({
    productId: v.slug,
    rating: z.number().int().min(1).max(5),
    text: cleanMultiline(1000).default(""),
    photos: z.array(z.string().regex(/^review-photos\/[A-Za-z0-9]{1,128}\/[0-9]{1,15}\.webp$/)).max(3).default([]),
  }),
  z.object({ id: z.string() }),
);
