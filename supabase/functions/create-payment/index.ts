import { env, handler, HttpError, json, readJson, UUID } from "../_shared/http.ts";
import { type Db, requireUser } from "../_shared/supabase.ts";
import { razorpay } from "../_shared/razorpay.ts";
import { customerFor, type CustomerStore } from "../_shared/customers.ts";

const customers = (db: Db): CustomerStore => ({
  async find(userId) {
    const { data, error } = await db.from("razorpay_customers").select("customer_id").eq("user_id", userId).maybeSingle();
    if (error) throw error;
    return data?.customer_id ?? null;
  },
  async who(userId) {
    const [{ data: auth, error }, { data: profile }] = await Promise.all([
      db.auth.admin.getUserById(userId),
      db.from("profiles").select("full_name").eq("id", userId).maybeSingle(),
    ]);
    if (error) throw error;
    return { phone: auth.user.phone || null, email: auth.user.email || null, name: profile?.full_name ?? null };
  },
  async save(userId, customerId) {
    const { error } = await db.from("razorpay_customers").insert({ user_id: userId, customer_id: customerId });
    if (error && error.code !== "23505") throw error; // 23505: made meanwhile, or another account's customer
    return await this.find(userId);
  },
});

// {order_id} -> {key_id, razorpay_order_id, amount, currency, order_number, reserved_until, customer_id}
Deno.serve(handler(async (req) => {
  const { userId, db } = await requireUser(req);
  const { order_id } = await readJson(req);
  if (typeof order_id !== "string" || !UUID.test(order_id)) throw new HttpError(400, "BAD_REQUEST", "order_id is required.");

  const { data: order, error } = await db.from("orders")
    .select("id, number, user_id, status, payment_method, total_paise, razorpay_order_id, reserved_until")
    .eq("id", order_id).maybeSingle();
  if (error) throw error;
  if (!order || order.user_id !== userId) throw new HttpError(404, "NOT_FOUND", "Order not found.");
  if (order.status !== "pending_payment" || order.payment_method !== "razorpay") {
    throw new HttpError(409, "ORDER_NOT_PAYABLE", "This order can't be paid online.");
  }
  if (!order.reserved_until || new Date(order.reserved_until) <= new Date()) {
    throw new HttpError(409, "ORDER_EXPIRED", "Payment time ran out. Place the order again.");
  }

  let razorpayOrderId: string | null = order.razorpay_order_id;
  if (!razorpayOrderId) {
    const created = await razorpay<{ id: string }>("/orders", {
      amount: order.total_paise,
      currency: "INR",
      receipt: order.number,
      notes: { order_id: order.id },
    });
    // a concurrent call may have stored its own id first; keep whichever won
    const { error: updateError } = await db.from("orders").update({ razorpay_order_id: created.id })
      .eq("id", order.id).is("razorpay_order_id", null);
    if (updateError) throw updateError;
    const { data: saved, error: readError } = await db.from("orders").select("razorpay_order_id").eq("id", order.id).single();
    if (readError) throw readError;
    razorpayOrderId = saved.razorpay_order_id;
  }

  return json({
    key_id: env("RAZORPAY_KEY_ID"),
    razorpay_order_id: razorpayOrderId,
    amount: order.total_paise,
    currency: "INR",
    order_number: order.number,
    reserved_until: new Date(order.reserved_until).toISOString(), // app sets Razorpay's checkout timeout from this
    customer_id: await customerFor(customers(db), userId), // saved cards in Checkout; null without one
  });
}));
