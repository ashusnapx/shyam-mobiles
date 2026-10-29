import { handler, HttpError } from "../_shared/http.ts";
import { requireUser } from "../_shared/supabase.ts";

// {} -> 204. Orders survive with user_id = null (FK on delete set null).
Deno.serve(handler(async (req) => {
  const { userId, db } = await requireUser(req);

  const [orders, repairs] = await Promise.all([
    db.from("orders").select("id", { count: "exact", head: true })
      .eq("user_id", userId).not("status", "in", "(delivered,cancelled,refunded)"),
    db.from("repair_bookings").select("id", { count: "exact", head: true })
      .eq("user_id", userId).not("status", "in", "(completed,cancelled)"),
  ]);
  if (orders.error) throw orders.error;
  if (repairs.error) throw repairs.error;
  if (orders.count || repairs.count) {
    throw new HttpError(409, "ACTIVE_ORDERS", "Finish or cancel your open orders and repairs first.");
  }

  const { error } = await db.auth.admin.deleteUser(userId);
  if (error) throw error;
  return new Response(null, { status: 204 });
}));
