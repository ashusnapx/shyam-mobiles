import type { Transaction } from "firebase-admin/firestore";
import type { GatewayState } from "../payments/gateway.js";
import { notImplemented } from "../shared/callable.js";

// Owner: engineer C. The gateway-neutral settlement state machine that payments (engineer D) calls inside its own
// transaction; the call shape is payments/flows.ts `Settlement`. Vectors: test-vectors/settlement.json.

/** Marks the order paid only on `completed` with exactly its totalPaise; idempotent; revives an expired order only
 * if stock allows, else records that a refund is due. */
export async function settleOnlinePayment(
  _tx: Transaction,
  _orderId: string,
  _p: { merchantOrderId: string; transactionId: string | null; amountPaise: number | null; state: GatewayState },
): Promise<unknown> {
  return Promise.resolve(notImplemented());
}

/** Settles orders/{id}/refunds/{refundId}: processed → items[].refundId kept, paymentStatus refunded once fully
 * refunded; failed → pendingRefundId cleared and the items freed. Idempotent. */
export async function settleRefund(
  _tx: Transaction,
  _orderId: string,
  _refundId: string,
  _r: { state: GatewayState; gatewayRefundId: string | null; failure: string | null },
): Promise<unknown> {
  return Promise.resolve(notImplemented());
}
