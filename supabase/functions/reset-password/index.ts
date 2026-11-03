import { handler, readJson } from "../_shared/http.ts";
import { requireAdmin, rpcOf } from "../_shared/supabase.ts";
import { type Accounts, resetPassword } from "./handler.ts";

Deno.serve(handler(async (req) => {
  const { userId, db } = await requireAdmin(req);
  const accounts: Accounts = {
    rpc: rpcOf(db),
    async update(id, attrs) {
      const { error } = await db.auth.admin.updateUserById(id, attrs);
      if (error) throw error;
    },
  };
  return await resetPassword(await readJson(req), userId, accounts);
}));
