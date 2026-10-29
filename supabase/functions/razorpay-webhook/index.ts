import { env, handler, UUID } from "../_shared/http.ts";
import { adminClient } from "../_shared/supabase.ts";
import { handleWebhook, type Store } from "./handler.ts";

const db = adminClient();

const store: Store = {
  async recordEvent(id, type, payload) {
    const { error } = await db.from("payment_events").insert({ razorpay_event_id: id, type, payload });
    if (error?.code === "23505") return false;
    if (error) throw error;
    return true;
  },
  async forgetEvent(id) {
    await db.from("payment_events").delete().eq("razorpay_event_id", id);
  },
  async findOrder(razorpayOrderId, orderId) {
    for (const [column, value] of [["razorpay_order_id", razorpayOrderId], ["id", orderId]] as const) {
      if (!value || (column === "id" && !UUID.test(value))) continue;
      const { data, error } = await db.from("orders").select("id, total_paise").eq(column, value).maybeSingle();
      if (error) throw error;
      if (data) return data;
    }
    return null;
  },
  async rpc(fn, args) {
    const { error } = await db.rpc(fn, args);
    return error ? error.message : null;
  },
};

// verify_jwt = false (config.toml): Razorpay signs the body with RAZORPAY_WEBHOOK_SECRET instead.
Deno.serve(handler((req) => handleWebhook(req, env("RAZORPAY_WEBHOOK_SECRET"), store)));
