// The payment gateway as the payment flows see it (docs/FIREBASE.md §5): PhonePe in production (phonepe.ts), a fake in
// tests (fake_gateway.ts). States are PhonePe's, lowercased.

export type GatewayState = "pending" | "completed" | "failed";

export type GatewayOrder = { phonepeOrderId: string; token: string; expireAt: Date | null };
export type GatewayOrderStatus = { state: GatewayState; amountPaise: number | null; transactionId: string | null };
export type GatewayRefund = { state: GatewayState; gatewayRefundId: string | null };

export interface PaymentGateway {
  readonly merchantId: string; // public: the app's SDK init takes it
  readonly env: "SANDBOX" | "PRODUCTION"; // the SDK's environment matching the API host
  createOrder(o: { merchantOrderId: string; amountPaise: number; expireAfterSeconds: number; orderId: string; orderNumber: string }): Promise<GatewayOrder>;
  orderStatus(merchantOrderId: string): Promise<GatewayOrderStatus>;
  refund(r: { merchantRefundId: string; merchantOrderId: string; amountPaise: number }): Promise<GatewayRefund>;
  /** null: the gateway has never heard of this refund */
  refundStatus(merchantRefundId: string): Promise<GatewayRefund | null>;
}

/** The gateway said no, or couldn't be reached (`status` 0). `definite`: retrying the same request can't succeed. */
export class GatewayError extends Error {
  status: number;
  code: string;
  description: string;
  constructor(status: number, code: string, description: string) {
    super(`gateway ${status} ${code}: ${description}`);
    this.status = status;
    this.code = code;
    this.description = description;
  }
  get definite(): boolean {
    return (this.status === 400 || this.status === 404) && !/duplicate|already|in progress/i.test(`${this.code} ${this.description}`);
  }
}
