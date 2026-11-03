import { FieldValue, type Query } from "firebase-admin/firestore";
import { adminAuth, db } from "../shared/db.js";
import { fail } from "../shared/errors.js";
import type { OrderDoc } from "../model/orders.js";
import type { RepairDoc } from "../model/repairs.js";
import { blocksDeletion, plain } from "./policy.js";

// Owner: engineer A. Firestore and Auth reads and writes for the account domain; the decisions are in policy.ts.

/** shortcut: one page of a customer's orders or repairs is the whole history at shop volume; page it past that. */
const HISTORY = 500;

const docsOf = async (q: Query) => (await q.get()).docs;
const byUid = (collection: string, uid: string, field = "uid") => db().collection(collection).where(field, "==", uid).limit(HISTORY);

/**
 * Deletes [uid]'s account (docs/SECURITY.md §4.6), or fails ACTIVE_ORDERS. Orders stay for the GST records with
 * `uid: null`, as do their redemptions; everything else personal goes: the profile with its addresses, notifications,
 * coupons and wishlist, the cart, devices, rate limits, referral code and referral, repairs, feedback, and last the
 * Auth user, so a failure part-way leaves an account that can simply try again. Storage holds nothing personal but
 * invoices, which GST law keeps for 8 years (their lifecycle rule deletes them).
 */
export async function eraseAccount(uid: string): Promise<void> {
  const fs = db();
  // The guard runs in a transaction with the cart's deletion: placeOrder reads the cart in its own, so an order is
  // either already there for the guard to see, or can no longer be placed.
  const { orders, repairs } = await fs.runTransaction(async (tx) => {
    const [orders, repairs] = await Promise.all([tx.get(byUid("orders", uid)), tx.get(byUid("repairs", uid))]);
    if (blocksDeletion(orders.docs.map((d) => d.data() as OrderDoc), repairs.docs.map((d) => d.data() as RepairDoc))) fail("ACTIVE_ORDERS");
    tx.delete(fs.doc(`carts/${uid}`));
    return { orders: orders.docs, repairs: repairs.docs };
  });

  const [feedback, devices, codes, referred, redemptions] = await Promise.all([
    docsOf(byUid("feedback", uid)),
    docsOf(byUid("devices", uid)),
    docsOf(byUid("referralCodes", uid)),
    docsOf(byUid("referrals", uid, "referrerUid")),
    docsOf(byUid("redemptions", uid)),
  ]);
  const writer = fs.bulkWriter();
  const now = FieldValue.serverTimestamp();
  for (const d of orders) void writer.update(d.ref, { uid: null, updatedAt: now });
  for (const d of redemptions) void writer.update(d.ref, { uid: null });
  for (const d of referred) void writer.update(d.ref, { referrerUid: null });
  for (const d of [...repairs, ...feedback, ...devices, ...codes]) void writer.delete(d.ref);
  void writer.delete(fs.doc(`referrals/${uid}`));
  void writer.delete(fs.doc(`rateLimits/${uid}`));
  await writer.close();
  await fs.recursiveDelete(fs.doc(`users/${uid}`));

  await adminAuth().deleteUser(uid).catch((e: unknown) => {
    if ((e as { code?: unknown }).code !== "auth/user-not-found") throw e;
  });
}

/** Everything the shop holds about [uid], as plain JSON (docs/SECURITY.md §4.7). */
export async function exportData(uid: string): Promise<Record<string, unknown>> {
  const fs = db();
  const user = fs.doc(`users/${uid}`);
  const rows = async (q: Query) => (await docsOf(q.limit(HISTORY))).map((d) => ({ id: d.id, ...d.data() }));
  const [profile, cart, addresses, wishlist, notifications, coupons, orders, repairs, feedback] = await Promise.all([
    user.get(),
    fs.doc(`carts/${uid}`).get(),
    rows(user.collection("addresses")),
    rows(user.collection("wishlist")),
    rows(user.collection("notifications")),
    rows(user.collection("coupons")),
    rows(fs.collection("orders").where("uid", "==", uid)),
    rows(fs.collection("repairs").where("uid", "==", uid)),
    rows(fs.collection("feedback").where("uid", "==", uid)),
  ]);
  return plain({
    exportedAt: new Date(),
    profile: profile.data() ?? null,
    addresses, cart: cart.data() ?? null, wishlist, coupons, orders, repairs, feedback, notifications,
  }) as Record<string, unknown>;
}

/** The Auth user who signed in with [phone], or NOT_FOUND. */
export async function userByPhone(phone: string) {
  return adminAuth().getUserByPhoneNumber(phone).catch((e: unknown) => {
    if ((e as { code?: unknown }).code === "auth/user-not-found") fail("NOT_FOUND");
    throw e;
  });
}

/**
 * Sets or removes [uid]'s staff role: the role doc first (Rules and requireStaff read it, so removal bites at once),
 * then the claim, then, on removal, every session is revoked so the old token can't even refresh.
 */
export async function writeRole(uid: string, role: "owner" | "staff" | null, claims: Record<string, unknown> | undefined): Promise<void> {
  await db().doc(`users/${uid}`).set({ role: role ?? FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  const rest = { ...claims };
  delete rest.role;
  await adminAuth().setCustomUserClaims(uid, role === null ? rest : { ...rest, role });
  if (role === null) await adminAuth().revokeRefreshTokens(uid);
}

/** "Sign out of all phones": every refresh token revoked, every push token forgotten. */
export async function signOutAll(uid: string): Promise<void> {
  await adminAuth().revokeRefreshTokens(uid);
  const writer = db().bulkWriter();
  for (const d of await docsOf(byUid("devices", uid))) void writer.delete(d.ref);
  await writer.close();
}

/** claimOwner's check and the role doc, in one transaction on settings/business and the current owners. */
export async function takeOwnerRole(uid: string, decide: (shopPhone: string | undefined, ownerUids: string[]) => boolean): Promise<void> {
  const fs = db();
  await fs.runTransaction(async (tx) => {
    const [business, owners] = await Promise.all([
      tx.get(fs.doc("settings/business")),
      tx.get(fs.collection("users").where("role", "==", "owner").limit(2)),
    ]);
    if (!decide(business.get("phone") as string | undefined, owners.docs.map((d) => d.id))) fail("FORBIDDEN");
    tx.set(fs.doc(`users/${uid}`), { role: "owner", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
}
