import { randomBytes } from "node:crypto";
import type { Transaction } from "firebase-admin/firestore";
import { requireUser } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { db } from "../shared/db.js";
import { fail, reasonOf } from "../shared/errors.js";
import { takeRateLimit } from "../shared/rateLimit.js";
import { offerJson } from "../offers/promotion.js";
import { doc, hasOrder, settings, writeReferralCoupon } from "../orders/repository.js";
import * as c from "./contract.js";

// Owner: engineer C. Refer & earn (docs/FIREBASE.md §3, §6), ported from my_referral and apply_referral_code
// (supabase/migrations/20261030000000_offers.sql). The reward is paid in adminUpdateOrder (orders/handlers.ts).

/** The caller's code, made on first ask: 8 characters, retried on the (rare) clash. */
async function codeOf(uid: string): Promise<string> {
  for (;;) {
    const code = await db().runTransaction(async (tx: Transaction) => {
      const user = doc(`users/${uid}`);
      const mine = (await tx.get(user)).get("referralCode") as string | undefined;
      if (mine) return mine;
      const code = randomBytes(4).toString("hex").toUpperCase();
      if ((await tx.get(doc(`referralCodes/${code}`))).exists) return null;
      tx.create(doc(`referralCodes/${code}`), { uid });
      tx.set(user, { referralCode: code }, { merge: true });
      return code;
    });
    if (code) return code;
  }
}

export const myReferral = callable(c.myReferral, async (_, req) => {
  const { uid } = requireUser(req);
  const code = await codeOf(uid);
  const mine = db().collection("referrals").where("referrerUid", "==", uid);
  const [s, joined, rewarded, referred, ordered] = await Promise.all([
    db().runTransaction((tx) => settings(tx)),
    mine.count().get(),
    mine.where("status", "==", "rewarded").count().get(),
    doc(`referrals/${uid}`).get(),
    db().runTransaction((tx) => hasOrder(tx, uid)),
  ]);
  const r = s.referral;
  return {
    enabled: r.enabled, code, friendPaise: r.friendPaise, rewardPaise: r.rewardPaise, minOrderPaise: r.minOrderPaise,
    joined: joined.data().count, rewarded: rewarded.data().count, canEnterCode: r.enabled && !referred.exists && !ordered,
  };
});

/** Links the caller to a friend's code before their first order and gives them the welcome coupon. Checks run in
 * apply_referral_code's order. rateLimits/{uid}, written here and by placeOrder, serialises the two. */
export const applyReferralCode = callable(c.applyReferralCode, async ({ code }, req) => {
  const { uid } = requireUser(req);
  try {
    return await db().runTransaction(async (tx) => {
      const s = (await settings(tx)).referral;
      if (!s.enabled) fail("REFERRAL_OFF");
      const referral = doc(`referrals/${uid}`);
      if ((await tx.get(referral)).exists) fail("REFERRAL_USED");
      if (await hasOrder(tx, uid)) fail("REFERRAL_TOO_LATE");
      const referrer = /^[A-Z0-9]{6,10}$/.test(code) ? ((await tx.get(doc(`referralCodes/${code}`))).get("uid") as string | undefined) : undefined;
      await takeRateLimit(tx, uid, "applyReferralCode"); // before the answer, so guessing stops at the limit
      if (!referrer) fail("REFERRAL_INVALID");
      if (referrer === uid) fail("REFERRAL_SELF");
      const now = new Date();
      tx.create(referral, { referrerUid: referrer, status: "pending", createdAt: now });
      const { id, p } = writeReferralCoupon(tx, "friend", uid, s, now);
      return offerJson(id, p);
    });
  } catch (e) {
    // a wrong guess still counts toward the limit, which the refused transaction rolled back
    if (reasonOf(e) === "REFERRAL_INVALID") await db().runTransaction((tx) => takeRateLimit(tx, uid, "applyReferralCode")).catch(() => undefined);
    throw e;
  }
});
