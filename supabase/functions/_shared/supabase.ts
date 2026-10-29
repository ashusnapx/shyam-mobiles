// @supabase/server is the documented way to authorize Edge Function callers
// (https://supabase.com/docs/guides/functions/auth). It reads SUPABASE_URL, SUPABASE_SECRET_KEYS and
// SUPABASE_JWKS, which the platform and the CLI provision, so no legacy anon/service_role key is used.
import { createSupabaseContext, type SupabaseContext } from "npm:@supabase/server@1.9.2";
import { createAdminClient } from "npm:@supabase/server@1.9.2/core";
import { HttpError } from "./http.ts";

export type Db = SupabaseContext["supabaseAdmin"];

// Secret-key client: bypasses RLS. Only ever used server-side.
export const adminClient = (): Db => createAdminClient();

// Verifies the caller's Supabase Auth JWT against the project's JWKS (no Auth round trip) and returns
// their user id plus an admin client. The admin client bypasses RLS, so every query must filter by userId.
export async function requireUser(req: Request): Promise<{ userId: string; db: Db }> {
  const { data: ctx, error } = await createSupabaseContext(req, { auth: "user", audience: "authenticated" });
  if (error) {
    if (error.status === 401) throw new HttpError(401, "UNAUTHORIZED", "Sign in again.");
    throw error; // missing env/JWKS: a server problem, so 500
  }
  const userId = ctx.userClaims?.id;
  if (!userId) throw new HttpError(401, "UNAUTHORIZED", "Sign in again.");
  return { userId, db: ctx.supabaseAdmin };
}

// RPC errors come back with message = the bare code raised in SQL.
export async function rpc(db: Db, fn: string, args: Record<string, unknown>): Promise<void> {
  const { error } = await db.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
}
