import { env, handler, HttpError, json, readJson } from "../_shared/http.ts";
import { requireUser, rpc } from "../_shared/supabase.ts";
import { verifySignature } from "../_shared/crypto.ts";
import { razorpay } from "../_shared/razorpay.ts";

type Payment = { order_id: string; amount: number; status: string };

// {razorpay_order_id, razorpay_payment_id, razorpay_signature} -> {order_id, status}
Deno.serve(handler(async (req) => {
  const { userId, db } = await requireUser(req);
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = await readJson(req);
  if (![razorpay_order_id, razorpay_payment_id, razorpay_signature].every((v) => typeof v === "string" && v)) {
    throw new HttpError(400, "BAD_REQUEST", "Payment details are missing.");
  }
  const rzpOrderId = razorpay_order_id as string, paymentId = razorpay_payment_id as string;

  if (!(await verifySignature(env("RAZORPAY_KEY_SECRET"), `${rzpOrderId}|${paymentId}`, razorpay_signature as string))) {
    throw new HttpError(400, "BAD_SIGNATURE", "Payment could not be verified.");
  }

  const { data: order, error } = await db.from("orders").select("id, user_id, total_paise")
    .eq("razorpay_order_id", rzpOrderId).maybeSingle();
  if (error) throw error;
  if (!order || order.user_id !== userId) throw new HttpError(404, "NOT_FOUND", "Order not found.");

  // the signature proves the pair came from Razorpay; the API confirms amount and state
  const payment = await razorpay<Payment>(`/payments/${encodeURIComponent(paymentId)}`);
  if (payment.order_id !== rzpOrderId || payment.amount !== order.total_paise || !["captured", "authorized"].includes(payment.status)) {
    console.error("payment mismatch", { order: order.id, paymentId, payment });
    throw new HttpError(409, "PAYMENT_MISMATCH", "Payment does not match this order. Contact the store.");
  }

  await rpc(db, "mark_order_paid", { p_order_id: order.id, p_razorpay_payment_id: paymentId });
  const { data: after, error: readError } = await db.from("orders").select("status").eq("id", order.id).single();
  if (readError) throw readError;
  return json({ order_id: order.id, status: after.status });
}));
