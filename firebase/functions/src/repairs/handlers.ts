import { Timestamp } from "firebase-admin/firestore";
import type { CallableRequest } from "firebase-functions/v2/https";
import type { RepairDoc } from "../model/repairs.js";
import { DAY_MS } from "../model/retention.js";
import { requireStaff, requireUser } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { db } from "../shared/db.js";
import { fail } from "../shared/errors.js";
import { audit } from "../shared/log.js";
import { istDate } from "../shared/time.js";
import * as c from "./contract.js";
import { approveQuote, cancelByCustomer, type Change, declineQuote, newBooking, OPEN, OPEN_LIMIT, type Repair, setQuote, staffUpdate } from "./state.js";

// Owner: engineer D. parse → guard → transaction: load the booking, decide (state.ts), write it with its new event.

const PURGE_MS = 3 * 366 * DAY_MS; // model/repairs.ts retention

export const bookRepair = callable(c.bookRepair, async (input, req) => {
  const { uid } = requireUser(req);
  const ref = db().collection("repairs").doc();
  await db().runTransaction(async (tx) => {
    const open = await tx.get(db().collection("repairs").where("uid", "==", uid).where("status", "in", OPEN).limit(OPEN_LIMIT));
    const counter = await tx.get(db().doc("counters/repairs"));
    const number = (counter.get("next") as number | undefined) ?? 100001;
    const at = Timestamp.now();
    const doc = newBooking(input, uid, open.size, number, istDate(at.toDate()), at);
    tx.set(counter.ref, { next: number + 1 });
    tx.create(ref, { ...doc, createdAt: at, updatedAt: at, purgeAt: Timestamp.fromMillis(at.toMillis() + PURGE_MS) });
  });
  return { repairId: ref.id };
});

async function change(repairId: string, decide: (r: Repair, at: Timestamp) => Change | null): Promise<Record<string, never>> {
  const ref = db().doc(`repairs/${repairId}`);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) fail("NOT_FOUND");
    const r = snap.data() as RepairDoc;
    const at = Timestamp.now();
    const next = decide(r, at);
    if (next) tx.update(ref, { status: next.status, quote: next.quote, events: [...r.events, next.event], updatedAt: at });
  });
  return {};
}

async function staff(req: CallableRequest, action: string, repairId: string): Promise<string> {
  const { uid } = await requireStaff(req);
  audit(action, uid, repairId);
  return uid;
}

export const cancelRepair = callable(c.cancelRepair, ({ repairId }, req) => {
  const { uid } = requireUser(req);
  return change(repairId, (r, at) => cancelByCustomer(r, uid, at));
});

export const approveRepairQuote = callable(c.approveRepairQuote, ({ repairId, quotePaise }, req) => {
  const { uid } = requireUser(req);
  return change(repairId, (r, at) => approveQuote(r, uid, quotePaise, at));
});

export const declineRepairQuote = callable(c.declineRepairQuote, ({ repairId, reason }, req) => {
  const { uid } = requireUser(req);
  return change(repairId, (r, at) => declineQuote(r, uid, reason ?? null, at));
});

export const adminUpdateRepair = callable(c.adminUpdateRepair, async ({ repairId, status, note }, req) => {
  const uid = await staff(req, "adminUpdateRepair", repairId);
  return change(repairId, (r, at) => staffUpdate(r, uid, status, note ?? null, at));
});

export const adminSetRepairQuote = callable(c.adminSetRepairQuote, async ({ repairId, quotePaise, note, approved }, req) => {
  const uid = await staff(req, "adminSetRepairQuote", repairId);
  return change(repairId, (r, at) => setQuote(r, uid, quotePaise, note ?? null, approved, at));
});
