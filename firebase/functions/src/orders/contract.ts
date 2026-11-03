import { z } from "zod";
import { contract } from "../shared/callable.js";
import { cleanMultiline, cleanText, v } from "../shared/validation.js";

// Owner: engineer C. Checkout and the order lifecycle (docs/FIREBASE.md §5). The client never sends a price: the
// server prices the cart from documents. Vectors: test-vectors/{pricing,offers,orders-state,settlement}.json.
const ok = z.object({});
const orderStatus = z.enum(["pending_payment", "confirmed", "packed", "shipped", "delivered", "cancelled", "refunded"]);
const promotionRef = z.object({ id: z.string(), title: z.string(), code: z.string().nullable(), kind: z.enum(["percent", "flat", "free_delivery"]) });

/** Prices the caller's cart as it is on the server. A refused code comes back as couponError, not a throw. */
export const quoteOrder = contract(
  "quoteOrder",
  z.strictObject({ couponCode: v.typedCode.nullish(), paymentMethod: v.paymentMethod.nullish() }),
  z.object({
    subtotalPaise: z.number().int(),
    deliveryFeePaise: z.number().int(),
    discountPaise: z.number().int(),
    totalPaise: z.number().int(),
    promotion: promotionRef.nullable(),
    couponError: z.string().nullable(),
    couponErrorDetail: z.number().int().nullable(),
  }),
);

/** One transaction: prices, reserves stock (online: 15-minute hold), records the redemption, clears the cart lines. */
export const placeOrder = contract(
  "placeOrder",
  z.strictObject({
    addressId: z.enum(["a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9"]),
    paymentMethod: v.paymentMethod,
    couponCode: v.typedCode.nullish(),
    buyerGstin: z.string().regex(/^[0-9]{2}[A-Z0-9]{13}$/).nullish(), // Phase 2: format + checksum
  }),
  z.object({ orderId: z.string() }),
);

/** The customer cancels their own order while it is still pending_payment or confirmed. Restocks. */
export const cancelOrder = contract("cancelOrder", z.strictObject({ orderId: v.docId }), ok);

/** Staff: one step forward, a cancel, COD delivered → paid, cancelled+paid → refunded ("Mark refunded"). The current
 * status again only edits courier/tracking and adds [note] to the timeline. */
export const adminUpdateOrder = contract(
  "adminUpdateOrder",
  z.strictObject({
    orderId: v.docId,
    status: orderStatus,
    note: cleanMultiline(500).nullish(),
    courier: cleanText(60, { min: 1, mustHave: "letterOrDigit" }).nullish(),
    trackingNumber: cleanText(60).nullish(),
  }),
  ok,
);

/** Staff: the IMEIs of one line, exactly qty distinct values (or [] to clear). `imeis` is checked by the handler against
 * the line's qty (detail "need 2 distinct 15-digit IMEIs"), after the staff and order checks. */
export const adminSetImeis = contract(
  "adminSetImeis",
  z.strictObject({ orderId: v.docId, itemId: v.docId, imeis: z.unknown() }),
  ok,
  "INVALID_IMEIS",
);

// settleOnlinePayment / settleRefund (orders/settlement.ts) are internal: their call shape is payments/flows.ts
// `Settlement`, defined by engineer D and implemented by engineer C.
