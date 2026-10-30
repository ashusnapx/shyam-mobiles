import { HttpError, json, UUID } from "../_shared/http.ts";
import { razorpay, RazorpayError } from "../_shared/razorpay.ts";
import { callRpc, type Rpc } from "../_shared/supabase.ts";

type Start = { refund_id: string; amount_paise: number; payment_id: string; instant: boolean; order_number: string; retry: boolean };
type Refund = { id: string; status: string; speed_processed?: string };

const CODES: Record<string, [number, string]> = {
  FORBIDDEN: [403, "This is for Shyam Mobiles staff."],
  NOT_FOUND: [404, "Order not found."],
  BAD_REQUEST: [400, "Pick items of this order that aren't refunded yet."],
  REFUND_NOT_ALLOWED: [409, "This order can't be refunded here."],
  REFUND_IN_PROGRESS: [409, "A refund for this order is already with Razorpay. Wait until it's done."],
};

// Razorpay's definite "no" is a 400 (or a 404 for a payment id it can't route); these 400s aren't one: the earlier
// call may have gone through, so the refund stays pending.
const NOT_FINAL = /duplicate receipt|another payment operation is in progress/i;

// {order_id, item_ids?, restock?, instant?} -> {refund_id, amount_paise, status, retry}. Staff only (index.ts).
// Amounts come from admin_start_refund (the order rows); the refund id is Razorpay's idempotency key, so a retry after
// a timeout returns the same refund instead of paying out twice.
export async function refund(body: Record<string, unknown>, staffId: string, rpc: Rpc): Promise<Response> {
  const { order_id, item_ids = null, restock = false, instant = false } = body;
  const items = item_ids === null || (Array.isArray(item_ids) && item_ids.length > 0 && item_ids.length <= 20 &&
    item_ids.every((i) => typeof i === "string" && UUID.test(i)));
  if (typeof order_id !== "string" || !UUID.test(order_id) || !items || typeof restock !== "boolean" || typeof instant !== "boolean") {
    throw new HttpError(400, "BAD_REQUEST", "order_id is required; item_ids is a list of order item ids.");
  }

  const start = await callRpc<Start>(rpc, "admin_start_refund",
    { p_staff: staffId, p_order_id: order_id, p_items: item_ids, p_restock: restock, p_instant: instant }, CODES);

  let made: Refund;
  try {
    made = await razorpay<Refund>(`/payments/${encodeURIComponent(start.payment_id)}/refund`, {
      amount: start.amount_paise,
      speed: start.instant ? "optimum" : "normal",
      receipt: start.refund_id,
      notes: { order_id, order_number: start.order_number, refund_id: start.refund_id },
    }, { headers: { "X-Refund-Idempotency": start.refund_id } });
  } catch (e) {
    if (e instanceof RazorpayError && [400, 404].includes(e.gatewayStatus) && !NOT_FINAL.test(e.description)) {
      await callRpc(rpc, "settle_refund", { p_refund_id: start.refund_id, p_razorpay_refund_id: null, p_status: "failed",
        p_failure: e.description || null }, CODES);
      throw new HttpError(409, "REFUND_REFUSED", `Razorpay refused the refund: ${e.description || "no reason given"}`);
    }
    throw new HttpError(502, "REFUND_UNCONFIRMED", "Razorpay didn't confirm the refund. Tap Refund again: it retries this same refund, never a second one.");
  }

  const status = await callRpc<string>(rpc, "settle_refund", {
    p_refund_id: start.refund_id,
    p_razorpay_refund_id: made.id,
    p_status: ["processed", "failed"].includes(made.status) ? made.status : "pending",
    p_speed: made.speed_processed ?? null,
  }, CODES);
  return json({ refund_id: start.refund_id, amount_paise: start.amount_paise, status, retry: start.retry });
}
