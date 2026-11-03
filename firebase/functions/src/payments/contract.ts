import { z } from "zod";
import { contract } from "../shared/callable.js";
import { v } from "../shared/validation.js";

// The payment callables' wire contract, as handlers.ts/flows.ts answer today (docs/FIREBASE.md §5). Owner: engineer D.
// TODO(D): handlers.ts still uses bare onCall with its own parsing and error mapping; move each callable onto
// shared/callable.ts with these contracts (App Check, REPLAY_PROTECTED for createPayment/startRefund, BAD_REQUEST,
// logged INTERNAL), and adjust the schemas here if a shape changes.
const order = z.strictObject({ orderId: v.docId });
const orderState = z.object({ status: z.string(), paymentStatus: z.enum(["pending", "paid", "failed", "refunded"]) });

/** {merchantId, token, orderId: PhonePe's order id, env} for the SDK, or {paid: true} when PhonePe already has it. */
export const createPayment = contract(
  "createPayment",
  order,
  z.union([
    z.object({ merchantId: z.string(), token: z.string(), orderId: z.string(), env: z.string() }),
    z.object({ paid: z.literal(true) }),
  ]),
);

/** Always called after the SDK returns, whatever it said: asks PhonePe's status API, then settles. */
export const verifyPayment = contract("verifyPayment", order, orderState);

/** Staff, recent login, replay-protected. Amounts come from the order; a retry asks the refund's status first. */
export const startRefund = contract(
  "startRefund",
  z.strictObject({ orderId: v.docId, itemIds: z.array(v.docId).min(1).max(10).nullish(), restock: z.boolean().default(false) }),
  z.object({ refundId: z.string(), amountPaise: z.number().int(), status: z.string(), retry: z.boolean() }),
);
