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
