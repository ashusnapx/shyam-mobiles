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

// requireUser, then the caller must be in `admins` (the same table public.is_admin() reads).
export async function requireAdmin(req: Request): Promise<{ userId: string; db: Db }> {
  const { userId, db } = await requireUser(req);
  const { data, error } = await db.from("admins").select("user_id").eq("user_id", userId).maybeSingle();
  if (error) throw error;
  if (!data) throw new HttpError(403, "FORBIDDEN", "This is for Shyam Mobiles staff.");
  return { userId, db };
}

export type RpcError = { message: string; details?: string | null; code?: string };
/** An RPC as the handlers see it, so tests can fake the database. */
export type Rpc = (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: RpcError | null }>;

export const rpcOf = (db: Db): Rpc => async (fn, args) => {
  const { data, error } = await db.rpc(fn, args);
  return { data, error };
};

// A bare code raised in SQL -> HttpError with that code, its `details` (written as staff copy) or `fallback` as the
// message; a refused check constraint (23514) -> 400; anything else is a server problem (500).
export async function callRpc<T>(rpc: Rpc, fn: string, args: Record<string, unknown>,
  codes: Record<string, [status: number, fallback: string]>): Promise<T> {
  const { data, error } = await rpc(fn, args);
  if (!error) return data as T;
  const known = codes[error.message];
  if (known) throw new HttpError(known[0], error.message, error.details || known[1]);
  if (error.code === "23514") throw new HttpError(400, "BAD_REQUEST", "Something in that request isn't valid.");
  throw new Error(`${fn}: ${error.message}`);
}
