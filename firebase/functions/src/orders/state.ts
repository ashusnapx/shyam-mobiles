import type { OrderStatus, PaymentMethod, PaymentStatus } from "../model/orders.js";

// Owner: engineer C. The order state machine (docs/FIREBASE.md §3 "Order state machine"), a pure port of
// cancel_order / admin_update_order (supabase/migrations/20261028000200_rpcs.sql, 20261030000350_refund_by_staff.sql).
// Vectors: test-vectors/orders-state.json.

const NEXT: Partial<Record<OrderStatus, readonly OrderStatus[]>> = {
  pending_payment: ["cancelled"],
  confirmed: ["packed", "cancelled"],
  packed: ["shipped", "cancelled"],
  shipped: ["delivered"],
  delivered: ["refunded"],
};

export const REFUND_LINE = "A full refund to your original payment method is on its way; banks usually take 5–7 working days.";
export const MARK_REFUNDED_NOTE = "Refund issued. Banks usually take 5–7 working days to show it.";
export const EXPIRED_NOTE = "Payment not received in time";

type Order = { status: OrderStatus; paymentMethod: PaymentMethod; paymentStatus: PaymentStatus; courier?: string | null; trackingNumber?: string | null };

export type Step = {
  status: OrderStatus;
  paymentStatus: PaymentStatus;
  courier?: string;
  trackingNumber?: string;
  /** null: no timeline entry (an edit that changed nothing). */
  event: { status: OrderStatus; note: string | null } | null;
  restock: boolean;
  /** Mark refunded on a cancelled, paid order: only paymentStatus changes. */
  markRefunded: boolean;
};

/** Staff's step, or a refusal reason with its detail. */
export function staffStep(o: Order, to: OrderStatus, input: { note?: string | null; courier?: string | null; trackingNumber?: string | null }):
  Step | { reason: "INVALID_TRANSITION"; detail: string } {
  const note = input.note ?? null;
  if (o.status === "cancelled" && to === "refunded") {
    if (o.paymentStatus !== "paid") return { reason: "INVALID_TRANSITION", detail: "only a paid, cancelled order can be refunded" };
    return { status: "cancelled", paymentStatus: "refunded", event: { status: "cancelled", note: note ?? MARK_REFUNDED_NOTE }, restock: false, markRefunded: true };
  }
  if (to !== o.status && !NEXT[o.status]?.includes(to)) return { reason: "INVALID_TRANSITION", detail: `${o.status} -> ${to}` };
  const courier = input.courier ?? o.courier ?? undefined;
  const trackingNumber = input.trackingNumber ?? o.trackingNumber ?? undefined;
  let text = note;
  if (to === o.status && text === null && (courier !== (o.courier ?? undefined) || trackingNumber !== (o.trackingNumber ?? undefined))) {
    text = `Courier and tracking updated: ${[courier, trackingNumber].filter((x) => x !== undefined).join(" · ")}`;
  }
  const cancel = to === "cancelled" && o.status !== "cancelled";
  if (cancel && o.paymentStatus === "paid") text = `${text ?? "Cancelled by the store."} ${REFUND_LINE}`;
  return {
    status: to,
    paymentStatus: to === "delivered" && o.paymentMethod === "cod" ? "paid" : to === "refunded" ? "refunded" : o.paymentStatus,
    ...(courier === undefined ? {} : { courier }),
    ...(trackingNumber === undefined ? {} : { trackingNumber }),
    event: to !== o.status || text !== null ? { status: to, note: text } : null,
    restock: cancel,
    markRefunded: false,
  };
}

/** The customer's cancel: only while pending payment or confirmed. */
export function customerCancelNote(o: Order): string | null {
  if (o.status !== "pending_payment" && o.status !== "confirmed") return null;
  return o.paymentStatus === "paid" ? `Cancelled by you. ${REFUND_LINE}` : "Cancelled by you.";
}
