import { z } from "zod";
import { contract } from "../shared/callable.js";
import { v } from "../shared/validation.js";

// Owner: engineer A. Identity and the account (docs/FIREBASE.md §4, docs/SECURITY.md §2.2, §4.6, §4.7).
const none = z.strictObject({});
const ok = z.object({});

/** Once ever: a Google + TOTP session whose verified phone equals settings/business.phone, and no owner yet. */
export const claimOwner = contract("claimOwner", none, z.object({ role: z.literal("owner") }));

/** Owner only, recent login, replay-protected. role null removes staff rights and revokes their sessions. */
export const setRole = contract("setRole", z.strictObject({ phone: v.phone, role: z.enum(["staff"]).nullable() }), z.object({ uid: z.string() }));

/** Recent login, replay-protected. ACTIVE_ORDERS while orders or repairs are open or a refund is due. */
export const deleteAccount = contract("deleteAccount", none, ok);

/** Staff (TOTP, recent login): the web deletion route, for a customer who asked from their registered number. */
export const adminDeleteAccount = contract("adminDeleteAccount", z.strictObject({ phone: v.phone }), ok);

/** The caller's data as JSON (DPDP s.11), at most once a day. */
export const exportMyData = contract("exportMyData", none, z.object({ data: z.record(z.string(), z.unknown()) }));

/** Revokes every session and deletes the caller's devices/*. */
export const signOutEverywhere = contract("signOutEverywhere", none, ok);
