import { handler, HttpError } from "../_shared/http.ts";
import { requireUser } from "../_shared/supabase.ts";
import { forgetCustomer } from "../_shared/customers.ts";

// {} -> 204. Orders survive with user_id = null (FK on delete set null). Saved cards at Razorpay are deleted.
Deno.serve(handler(async (req) => {
  const { userId, db } = await requireUser(req);

  const [orders, repairs, refunds] = await Promise.all([
    db.from("orders").select("id", { count: "exact", head: true })
      .eq("user_id", userId).not("status", "in", "(delivered,cancelled,refunded)"),
    db.from("repair_bookings").select("id", { count: "exact", head: true })
      .eq("user_id", userId).not("status", "in", "(completed,cancelled)"),
    // a cancelled order still owed a refund: the customer would lose sight of it
    db.from("orders").select("id", { count: "exact", head: true })
      .eq("user_id", userId).eq("status", "cancelled").eq("payment_status", "paid"),
  ]);
  if (orders.error) throw orders.error;
  if (repairs.error) throw repairs.error;
  if (refunds.error) throw refunds.error;
  if (orders.count || repairs.count || refunds.count) {
    throw new HttpError(409, "ACTIVE_ORDERS", "Finish or cancel your open orders and repairs first, and wait for any refund.");
  }

  // saved cards go first; the razorpay_customers row goes with the user (on delete cascade)
  const { data: customer } = await db.from("razorpay_customers").select("customer_id").eq("user_id", userId).maybeSingle();
  if (customer) await forgetCustomer(customer.customer_id);

  const { error } = await db.auth.admin.deleteUser(userId);
  if (error) throw error;
  return new Response(null, { status: 204 });
}));
