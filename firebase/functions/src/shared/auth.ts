import type { CallableRequest } from "firebase-functions/v2/https";
import type { DecodedIdToken } from "firebase-admin/auth";
import { fail } from "./errors.js";
import { db } from "./db.js";

// Who may call what (docs/SECURITY.md §2.2). Staff power needs all three: the `role` custom claim, a TOTP second
// factor in this session, and the role still on users/{uid} (so removal is immediate, not after the 1-hour token).
// Rules' isStaff() checks the same three.

export const STAFF_ROLES = ["owner", "staff"] as const;
export type Role = (typeof STAFF_ROLES)[number];

export interface Caller {
  uid: string;
  token: DecodedIdToken;
}

const isRole = (v: unknown): v is Role => typeof v === "string" && (STAFF_ROLES as readonly string[]).includes(v);

/** The signed-in caller, or UNAUTHORIZED. */
export function requireUser(req: Pick<CallableRequest, "auth">): Caller {
  if (!req.auth) fail("UNAUTHORIZED");
  return { uid: req.auth.uid, token: req.auth.token };
}

export type RoleReader = (uid: string) => Promise<unknown>;
const roleOnUserDoc: RoleReader = async (uid) => (await db().doc(`users/${uid}`).get()).get("role") as unknown;

/** A staff member or the owner in a TOTP session whose role doc agrees with the claim, else FORBIDDEN. */
export async function requireStaff(req: Pick<CallableRequest, "auth">, readRole: RoleReader = roleOnUserDoc): Promise<Caller & { role: Role }> {
  const caller = requireUser(req);
  const claim: unknown = caller.token.role;
  if (!isRole(claim) || caller.token.firebase.sign_in_second_factor !== "totp") fail("FORBIDDEN");
  const role = await readRole(caller.uid);
  if (role !== claim) fail("FORBIDDEN");
  return { ...caller, role: claim };
}

export async function requireOwner(req: Pick<CallableRequest, "auth">, readRole: RoleReader = roleOnUserDoc): Promise<Caller & { role: "owner" }> {
  const caller = await requireStaff(req, readRole);
  if (caller.role !== "owner") fail("FORBIDDEN");
  return { ...caller, role: "owner" };
}

/** For setRole, startRefund, deleteAccount, adminDeleteAccount: signed in within [maxAgeSec], else REAUTH_REQUIRED. */
export function requireRecentLogin(caller: Caller, nowMs = Date.now(), maxAgeSec = 300): void {
  if (nowMs / 1000 - caller.token.auth_time > maxAgeSec) fail("REAUTH_REQUIRED");
}

/** Replay protection: with consumeAppCheckToken a reused token still reaches the handler, flagged (SECURITY §2.1). */
export function rejectConsumedAppCheck(req: Pick<CallableRequest, "app">): void {
  if (req.app?.alreadyConsumed === true) fail("UNAUTHORIZED");
}
