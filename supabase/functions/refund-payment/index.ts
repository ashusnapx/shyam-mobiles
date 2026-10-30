import { handler, readJson } from "../_shared/http.ts";
import { requireAdmin, rpcOf } from "../_shared/supabase.ts";
import { refund } from "./handler.ts";

Deno.serve(handler(async (req) => {
  const { userId, db } = await requireAdmin(req);
  return await refund(await readJson(req), userId, rpcOf(db));
}));
