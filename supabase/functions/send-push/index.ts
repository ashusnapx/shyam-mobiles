import { adminClient } from "../_shared/supabase.ts";
import { sendPushHandler } from "./handler.ts";

const db = adminClient();

// verify_jwt = false (config.toml): the database calls it (pg_net) with the shared PUSH_SECRET instead of a JWT.
Deno.serve(sendPushHandler({
  secret: Deno.env.get("PUSH_SECRET"),
  serviceAccount: Deno.env.get("FCM_SERVICE_ACCOUNT"),
  fetch,
  async forget(tokens) {
    const { error } = await db.from("device_tokens").delete().in("token", tokens);
    if (error) throw error;
  },
}));
