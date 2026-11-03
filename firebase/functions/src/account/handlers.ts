import { isStaffSession, rejectConsumedAppCheck, requireOwner, requireRecentLogin, requireStaff, requireUser } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { adminAuth, db } from "../shared/db.js";
import { fail } from "../shared/errors.js";
import { audit } from "../shared/log.js";
import { REPLAY_PROTECTED } from "../shared/options.js";
import { takeRateLimit } from "../shared/rateLimit.js";
import * as c from "./contract.js";
import { mayClaimOwner } from "./policy.js";
import { eraseAccount, exportData, signOutAll, takeOwnerRole, userByPhone, writeRole } from "./repository.js";

// Owner: engineer A. Identity and the account (docs/FIREBASE.md §4, docs/SECURITY.md §2.2, §4.6, §4.7).

/** Once ever: the shop's own verified phone, in a staff (TOTP) session, while nobody else is the owner. */
export const claimOwner = callable(c.claimOwner, async (_, req) => {
  const { uid, token } = requireUser(req);
  if (!isStaffSession(token)) fail("FORBIDDEN");
  const user = await adminAuth().getUser(uid);
  await takeOwnerRole(uid, (shopPhone, owners) => mayClaimOwner({ uid, phone: user.phoneNumber }, shopPhone, owners));
  await adminAuth().setCustomUserClaims(uid, { ...user.customClaims, role: "owner" });
  audit("claimOwner", uid, uid);
  return { role: "owner" as const };
});

/** The owner adds or removes staff by phone. The owner's own role can't be changed here. */
export const setRole = callable(c.setRole, async ({ phone, role }, req) => {
  rejectConsumedAppCheck(req);
  const owner = await requireOwner(req);
  requireRecentLogin(owner);
  const target = await userByPhone(phone);
  if (target.uid === owner.uid || target.customClaims?.role === "owner") fail("FORBIDDEN");
  await writeRole(target.uid, role, target.customClaims);
  audit("setRole", owner.uid, target.uid, { role });
  return { uid: target.uid };
}, REPLAY_PROTECTED);

export const deleteAccount = callable(c.deleteAccount, async (_, req) => {
  rejectConsumedAppCheck(req);
  const caller = requireUser(req);
  requireRecentLogin(caller);
  await eraseAccount(caller.uid);
  return {};
}, REPLAY_PROTECTED);

/** The web deletion route: a customer asked from their registered number, and staff checked it was them. */
export const adminDeleteAccount = callable(c.adminDeleteAccount, async ({ phone }, req) => {
  rejectConsumedAppCheck(req);
  const staff = await requireStaff(req);
  requireRecentLogin(staff);
  const target = await userByPhone(phone);
  if (target.customClaims?.role !== undefined) fail("FORBIDDEN"); // staff leave through setRole first, never this route
  await eraseAccount(target.uid);
  audit("adminDeleteAccount", staff.uid, target.uid);
  return {};
}, REPLAY_PROTECTED);

export const exportMyData = callable(c.exportMyData, async (_, req) => {
  const { uid } = requireUser(req);
  await db().runTransaction((tx) => takeRateLimit(tx, uid, "exportMyData"));
  return { data: await exportData(uid) };
});

export const signOutEverywhere = callable(c.signOutEverywhere, async (_, req) => {
  await signOutAll(requireUser(req).uid);
  return {};
});
