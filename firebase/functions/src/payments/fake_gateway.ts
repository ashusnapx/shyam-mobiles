import { GatewayError, type GatewayRefund, type GatewayState, type PaymentGateway } from "./gateway.js";

// An in-memory PhonePe for tests. Set `orders`/`refunds` entries to play the customer or the bank; set `fail` to make a
// call refuse or time out. `calls` records every call as "method id".
export function fakeGateway() {
  const g = {
    orders: new Map<string, { state: GatewayState; amountPaise: number; transactionId: string | null }>(),
    refunds: new Map<string, GatewayRefund & { amountPaise: number }>(),
    calls: [] as string[],
    made: 0,
    fail: null as null | ((method: string, id: string) => GatewayError | null),
  };
  const check = (method: string, id: string) => {
    g.calls.push(`${method} ${id}`);
    const e = g.fail?.(method, id);
    if (e) throw e;
  };
  const gateway: PaymentGateway = {
    merchantId: "PPFAKEMERCHANT",
    env: "SANDBOX",
    async createOrder(o) {
      check("createOrder", o.merchantOrderId);
      g.orders.set(o.merchantOrderId, { state: "pending", amountPaise: o.amountPaise, transactionId: null });
      g.made++;
      return { phonepeOrderId: `OMO${g.made}`, token: `tok${g.made}`, expireAt: null };
    },
    async orderStatus(id) {
      check("orderStatus", id);
      const o = g.orders.get(id);
      if (!o) throw new GatewayError(404, "ORDER_NOT_FOUND", "no such order");
      return { state: o.state, amountPaise: o.amountPaise, transactionId: o.transactionId };
    },
    async refund(r) {
      check("refund", r.merchantRefundId);
      if (g.refunds.has(r.merchantRefundId)) throw new GatewayError(400, "DUPLICATE_REQUEST", "duplicate merchantRefundId");
      const made = { state: "pending" as const, gatewayRefundId: `OMR${g.refunds.size + 1}`, amountPaise: r.amountPaise };
      g.refunds.set(r.merchantRefundId, made);
      return { state: made.state, gatewayRefundId: made.gatewayRefundId };
    },
    async refundStatus(id) {
      check("refundStatus", id);
      const r = g.refunds.get(id);
      return r ? { state: r.state, gatewayRefundId: r.gatewayRefundId } : null;
    },
  };
  return Object.assign(g, { gateway });
}
