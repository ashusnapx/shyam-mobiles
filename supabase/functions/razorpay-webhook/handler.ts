import { verifySignature } from "../_shared/crypto.ts";
import { fail, json, UUID } from "../_shared/http.ts";

export interface Store {
  /** false if this event id was already recorded */
  recordEvent(id: string, type: string, payload: unknown): Promise<boolean>;
  forgetEvent(id: string): Promise<void>;
  findOrder(razorpayOrderId?: string, orderId?: string): Promise<{ id: string; total_paise: number } | null>;
  /** null on success, else the Postgres error message (a bare code for business errors) */
  rpc(fn: string, args: Record<string, unknown>): Promise<string | null>;
}

// deno-lint-ignore no-explicit-any
type Entity = Record<string, any> | undefined;

export async function handleWebhook(req: Request, secret: string, store: Store): Promise<Response> {
  const raw = await req.arrayBuffer();
  if (!(await verifySignature(secret, raw, req.headers.get("x-razorpay-signature") ?? ""))) {
    return fail(401, "BAD_SIGNATURE", "Invalid webhook signature.");
  }
  const eventId = req.headers.get("x-razorpay-event-id");
  let event;
  try {
    event = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    event = null;
  }
  if (!eventId || typeof event?.event !== "string") return fail(400, "BAD_REQUEST", "Not a Razorpay event.");

  if (!(await store.recordEvent(eventId, event.event, event))) return json({ result: "duplicate" });
  try {
    return json({ result: await apply(event.event, event.payload ?? {}, store) });
  } catch (e) {
    await store.forgetEvent(eventId); // so Razorpay's retry is processed, not deduped
    throw e;
  }
}

async function apply(type: string, payload: Record<string, { entity?: Entity }>, store: Store): Promise<string> {
  const payment = payload.payment?.entity;
  const rzpOrder = payload.order?.entity;

  switch (type) {
    case "payment.captured":
    case "order.paid": {
      if (!payment?.id) return "ignored";
      const order = await store.findOrder(payment.order_id ?? rzpOrder?.id, rzpOrder?.notes?.order_id ?? payment.notes?.order_id);
      if (!order) return "unknown_order";
      if (payment.amount !== order.total_paise) {
        console.error("amount mismatch", { order: order.id, payment: payment.id, amount: payment.amount });
        return "amount_mismatch";
      }
      return await call(store, "mark_order_paid", { p_order_id: order.id, p_razorpay_payment_id: payment.id }, "paid");
    }
    case "payment.failed": {
      const order = await store.findOrder(payment?.order_id, payment?.notes?.order_id);
      if (!order) return "unknown_order";
      return await call(store, "mark_payment_failed", { p_order_id: order.id }, "failed");
    }
    case "refund.processed":
    case "refund.failed": {
      const refund = payload.refund?.entity;
      if (!refund?.payment_id) return "ignored";
      // one of ours (refund-payment puts our id in its notes): settle_refund does the rest
      const ours = typeof refund.notes?.refund_id === "string" && UUID.test(refund.notes.refund_id) ? refund.notes.refund_id : null;
      const status = type === "refund.processed" ? "processed" : "failed";
      const args = { p_refund_id: ours, p_razorpay_refund_id: refund.id ?? null, p_status: status, p_speed: refund.speed_processed ?? null };
      const error = await store.rpc("settle_refund", args);
      if (error !== "NOT_FOUND") return outcome(error, "settle_refund", args, `refund_${status}`);
      if (type === "refund.failed") return "unknown_refund";
      // made in the Razorpay dashboard:
      // shortcut: partial refunds are left for staff to reconcile; only a full refund flips payment_status.
      // Fail safe: without the payment's totals it is not provably full, so it isn't marked refunded.
      if (!(payment && payment.amount > 0 && payment.amount_refunded >= payment.amount)) return "partial_refund";
      return await call(store, "mark_order_refunded", { p_razorpay_payment_id: refund.payment_id }, "refunded");
    }
    case "payment_link.paid": {
      const link = payload.payment_link?.entity;
      if (!link?.id || !payment?.id) return "ignored";
      if (!Number.isInteger(payment.amount)) return "amount_mismatch";
      return await call(store, "mark_link_paid",
        { p_razorpay_link_id: link.id, p_razorpay_payment_id: payment.id, p_amount_paise: payment.amount }, "link_paid");
    }
    case "payment_link.cancelled":
    case "payment_link.expired": {
      const link = payload.payment_link?.entity;
      if (!link?.id) return "ignored";
      const status = type === "payment_link.cancelled" ? "cancelled" : "expired";
      return await call(store, "close_payment_link", { p_razorpay_link_id: link.id, p_status: status }, `link_${status}`);
    }
    default: {
      // payment.dispute.created / won / lost / closed / under_review / action_required
      const dispute = payload.dispute?.entity;
      if (!type.startsWith("payment.dispute.") || !dispute?.id || !dispute.payment_id) return "ignored";
      return await call(store, "record_dispute", {
        p_id: dispute.id,
        p_payment_id: dispute.payment_id,
        p_amount_paise: Number.isInteger(dispute.amount) ? dispute.amount : 0,
        p_status: dispute.status ?? "open",
        p_phase: dispute.phase ?? null,
        p_reason_code: dispute.reason_code ?? null,
        p_reason: dispute.reason_description ?? null,
        p_respond_by: Number.isInteger(dispute.respond_by) ? new Date(dispute.respond_by * 1000).toISOString() : null,
      }, "dispute");
    }
  }
}

// Business errors (bare codes like NOT_FOUND) won't fix themselves on retry: log and ack.
// Anything else (network, DB down) is thrown -> 500 -> Razorpay retries.
async function call(store: Store, fn: string, args: Record<string, unknown>, ok: string): Promise<string> {
  return outcome(await store.rpc(fn, args), fn, args, ok);
}

function outcome(error: string | null, fn: string, args: Record<string, unknown>, ok: string): string {
  if (error === null) return ok;
  if (/^[A-Z_]+$/.test(error)) {
    console.error(`${fn} refused`, error, args);
    return error.toLowerCase();
  }
  throw new Error(`${fn}: ${error}`);
}
