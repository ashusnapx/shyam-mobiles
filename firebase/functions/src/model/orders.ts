import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";
import type { AddressDoc } from "./users.js";

// Owner: engineer C. docs/FIREBASE.md §3. Orders are server-written only; clients read their own.

export type OrderStatus = "pending_payment" | "confirmed" | "packed" | "shipped" | "delivered" | "cancelled" | "refunded";
export type PaymentMethod = "online" | "cod";
export type PaymentStatus = "pending" | "paid" | "failed" | "refunded";
export type Actor = "customer" | "staff" | "system";

/** carts/{uid} (C): ≤ 20 lines (Rules), qty 1..5 (checked by quoteOrder/placeOrder). */
export interface CartDoc {
  lines: Record<string, { qty: number; addedAt: Timestamp }>; // key: variantId
  updatedAt: Timestamp;
}

export interface OrderItem {
  id: string; // the variantId
  productId: string;
  productName: string;
  variantName: string;
  imagePath?: string;
  unitPricePaise: number;
  qty: number;
  gstRateBp: number;
  hsnCode?: string;
  discountPaise: number; // this line's share of the order discount
  imeis: string[];
  refundId?: string | null; // the refund in flight or processed for this line; null again when it failed
}

export interface OrderEvent {
  status: OrderStatus;
  note?: string;
  by: Actor;
  byUid?: string;
  at: Timestamp;
}

/** orders/{autoId} (S). total = subtotal + fee − discount, discount = Σ items[].discountPaise ≤ subtotal − 100. */
export interface OrderDoc {
  number: string; // SM100001
  uid: string | null; // null after the customer deleted their account
  status: OrderStatus;
  paymentMethod: PaymentMethod;
  paymentStatus: PaymentStatus;
  subtotalPaise: number;
  deliveryFeePaise: number;
  discountPaise: number;
  totalPaise: number;
  promotion?: { id: string; title: string; code: string | null; kind: "percent" | "flat" | "free_delivery" };
  couponCode?: string;
  address: Omit<AddressDoc, "createdAt" | "updatedAt" | "label">;
  buyer?: { gstin: string; legalName: string }; // Phase 2
  items: OrderItem[]; // ≤ 10
  events: OrderEvent[];
  reservedUntil?: Timestamp | null; // online orders: the stock hold
  cancelledBy?: "customer" | "staff" | "expiry";
  courier?: string;
  trackingNumber?: string;
  payment?: { gateway: "phonepe"; merchantOrderId: string; transactionId?: string; paidAt?: Timestamp };
  pendingRefundId?: string | null;
  invoice?: { number: string; issuedAt: Timestamp; pdfPath: string; taxablePaise: number; cgstPaise: number; sgstPaise: number; igstPaise: number };
  createdAt: Timestamp;
  updatedAt: Timestamp;
  purgeAt: Timestamp; // 8 years: GST records (SECURITY §4.1)
}

/** orders/{id}/payments/{merchantOrderId} (S): one PhonePe attempt. */
export interface PaymentAttemptDoc {
  state: "pending" | "completed" | "failed";
  amountPaise: number;
  token: string;
  expireAt: Timestamp; // when the attempt stops being usable (not a TTL field)
  transactionId?: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  purgeAt: Timestamp;
}

/** orders/{id}/refunds/{refundId} (S). The doc id is the gateway's merchantRefundId (idempotency key). */
export interface RefundDoc {
  amountPaise: number;
  fullRefund: boolean;
  itemIds: string[];
  restock: boolean;
  status: "pending" | "processed" | "failed";
  gatewayRefundId?: string;
  failure?: string;
  createdBy: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  purgeAt: Timestamp;
}

/** counters/{orders|repairs|invoice-26-27} (S): incremented in the same transaction that uses the number. */
export interface CounterDoc {
  next: number;
}

export const ORDER_RETENTION_DAYS = 8 * 366;

export const retention: Record<string, Retention> = {
  carts: { kind: "account" },
  orders: { kind: "ttl", field: "purgeAt", days: ORDER_RETENTION_DAYS },
  "orders/*/payments": { kind: "ttl", field: "purgeAt", days: ORDER_RETENTION_DAYS },
  "orders/*/refunds": { kind: "ttl", field: "purgeAt", days: ORDER_RETENTION_DAYS },
  counters: { kind: "shop" },
};
