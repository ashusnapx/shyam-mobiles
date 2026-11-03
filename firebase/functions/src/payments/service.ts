// Pure payment rules (no Firestore, no network), unit-tested on their own.

/** A refusal for the app: `reason` is the errors.dart code, `message` short human text, `status` the HTTP shape. */
export class PaymentError extends Error {
  status: number;
  reason: string;
  constructor(status: number, reason: string, message: string) {
    super(message);
    this.status = status;
    this.reason = reason;
  }
}

/** PhonePe's order window (5–60 minutes), set to what is left of the stock hold. */
export function expireAfterSeconds(reservedUntilMs: number, nowMs: number): number {
  return Math.min(3600, Math.max(300, Math.floor((reservedUntilMs - nowMs) / 1000)));
}

/** "SM100001-3fa2b9c1" (a PhonePe order) and "SM100001-R3fa2b9c" (a refund): readable in PhonePe's dashboard, and the
 * webhook finds the order by its number. `random` is hex. */
export const merchantOrderId = (orderNumber: string, random: string) => `${orderNumber}-${random.slice(0, 8)}`;
export const merchantRefundId = (orderNumber: string, random: string) => `${orderNumber}-R${random.slice(0, 7)}`;
export const orderNumberOf = (id: unknown): string | null =>
  typeof id === "string" ? (/^(SM[0-9]{6,12})-R?[0-9a-f]{7,8}$/.exec(id)?.[1] ?? null) : null;

export type RefundableOrder = {
  status: string;
  paymentStatus: string;
  totalPaise: number;
  payment?: { gateway: string; merchantOrderId: string } | null;
  items: { id: string; unitPricePaise: number; qty: number; discountPaise: number; refundId?: string | null }[];
};

// What a refund may pay back, from the order (admin_start_refund's rules). itemIds null: everything not yet refunded,
// delivery included, only on a cancelled or delivered order. Otherwise those lines at what was paid for them
// (price × qty − their discount), on an order that isn't cancelled.
export function planRefund(o: RefundableOrder, refundedPaise: number, itemIds: string[] | null):
  { amountPaise: number; lineIds: string[]; fullRefund: boolean; merchantOrderId: string } {
  if (o.paymentStatus !== "paid" || o.payment?.gateway !== "phonepe") {
    throw new PaymentError(409, "REFUND_NOT_ALLOWED", "Only an order paid online, and not yet refunded, can be refunded here.");
  }
  const left = o.totalPaise - refundedPaise;
  let lines: RefundableOrder["items"];
  let amount: number;
  if (itemIds === null) {
    if (o.status !== "cancelled" && o.status !== "delivered") {
      throw new PaymentError(409, "REFUND_NOT_ALLOWED", "Cancel the order first, or refund single items.");
    }
    lines = o.items.filter((i) => !i.refundId);
    amount = left;
  } else {
    if (o.status === "cancelled") throw new PaymentError(409, "REFUND_NOT_ALLOWED", "A cancelled order is refunded in full.");
    lines = o.items.filter((i) => itemIds.includes(i.id) && !i.refundId);
    if (lines.length !== new Set(itemIds).size) {
      throw new PaymentError(400, "BAD_REQUEST", "Pick items of this order that aren’t refunded yet.");
    }
    amount = lines.reduce((sum, i) => sum + i.unitPricePaise * i.qty - i.discountPaise, 0);
  }
  if (amount < 100 || amount > left) throw new PaymentError(409, "REFUND_NOT_ALLOWED", "There’s nothing left to refund on this order.");
  return { amountPaise: amount, lineIds: lines.map((i) => i.id), fullRefund: itemIds === null, merchantOrderId: o.payment.merchantOrderId };
}
