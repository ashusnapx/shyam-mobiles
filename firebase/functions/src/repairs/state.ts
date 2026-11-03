import type { Timestamp } from "firebase-admin/firestore";
import type { QuoteStatus, RepairDoc, RepairStatus } from "../model/repairs.js";
import { fail } from "../shared/errors.js";
import { addDays } from "../shared/time.js";

// The repair state machine (docs/FIREBASE.md §3), a port of supabase/migrations/20261030000300_repair_flow.sql:
// requested → confirmed → in_progress → ready → completed, a cancel from any open step, and the quote beside it
// (none → pending → approved | declined, pending again whenever staff change it). Work starts, and a repair is
// ready, only on an approved quote. Every change appends one event; notifications/notices.ts reads them.
// Vectors: test-vectors/repairs-state.json.

export type RepairEvent = RepairDoc["events"][number];
export type Repair = Pick<RepairDoc, "uid" | "status" | "quote">;
/** What a decision writes: the new status and quote, and the event for the timeline. */
export type Change = { status: RepairStatus; quote: RepairDoc["quote"]; event: RepairEvent };

export const OPEN: readonly RepairStatus[] = ["requested", "confirmed", "in_progress", "ready"];
export const OPEN_LIMIT = 3;
const BOOKING_DAYS = 30;

/** Staff moves: one step forward, or a cancel while the booking is open. */
const STEPS: Record<RepairStatus, readonly RepairStatus[]> = {
  requested: ["confirmed", "cancelled"],
  confirmed: ["in_progress", "cancelled"],
  in_progress: ["ready", "cancelled"],
  ready: ["completed", "cancelled"],
  completed: [],
  cancelled: [],
};
/** While a quote can be sent, approved or declined. */
const QUOTABLE: readonly RepairStatus[] = ["requested", "confirmed", "in_progress"];

type Booking = Pick<RepairDoc, "deviceBrand" | "deviceModel" | "issue" | "description" | "preferredDate" | "slot" | "contactPhone">;

/**
 * A customer's new booking: REPAIR_LIMIT at [OPEN_LIMIT] open ones; the date from [today] (IST) to 30 days on.
 * [number] is the next counters/repairs value.
 */
export function newBooking(b: Booking, uid: string, openCount: number, number: number, today: string, at: Timestamp):
  Omit<RepairDoc, "createdAt" | "updatedAt" | "purgeAt"> {
  if (openCount >= OPEN_LIMIT) fail("REPAIR_LIMIT", OPEN_LIMIT);
  if (b.preferredDate < today || b.preferredDate > addDays(today, BOOKING_DAYS)) fail("BAD_REQUEST", ["preferredDate"]);
  return {
    ...b,
    number: `RP${number}`,
    uid,
    status: "requested",
    quote: { paise: null, status: "none" },
    events: [{ status: "requested", by: "customer", byUid: uid, at }],
  };
}

function own(r: Repair, uid: string): void {
  if (r.uid !== uid) fail("NOT_FOUND");
}

const event = (e: RepairEvent): RepairEvent =>
  Object.fromEntries(Object.entries(e as Record<string, unknown>).filter(([, v]) => v !== undefined)) as RepairEvent;

/** The customer, while the phone isn't opened yet (requested or confirmed). */
export function cancelByCustomer(r: Repair, uid: string, at: Timestamp): Change {
  own(r, uid);
  if (r.status !== "requested" && r.status !== "confirmed") fail("INVALID_TRANSITION", `${r.status} -> cancelled`);
  return { status: "cancelled", quote: r.quote, event: { status: "cancelled", note: "Cancelled by you.", by: "customer", byUid: uid, at } };
}

function answerable(r: Repair): void {
  if (r.quote.status !== "pending" || !QUOTABLE.includes(r.status)) fail("INVALID_TRANSITION");
}

/** [quotePaise] is the price the customer saw: QUOTE_CHANGED if staff changed it meanwhile. */
export function approveQuote(r: Repair, uid: string, quotePaise: number, at: Timestamp): Change {
  own(r, uid);
  answerable(r);
  if (quotePaise !== r.quote.paise) fail("QUOTE_CHANGED");
  return {
    status: r.status,
    quote: { paise: quotePaise, status: "approved", decidedAt: at },
    event: event({ status: r.status, quoteStatus: "approved", quotePaise, by: "customer", byUid: uid, at }),
  };
}

/** Saying no is safe whatever the amount, so no price check. Staff can quote again, or either side cancels. */
export function declineQuote(r: Repair, uid: string, reason: string | null, at: Timestamp): Change {
  own(r, uid);
  answerable(r);
  const paise = r.quote.paise;
  return {
    status: r.status,
    quote: { paise, status: "declined", decidedAt: at },
    event: event({ status: r.status, quoteStatus: "declined", quotePaise: paise ?? undefined, note: reason || undefined, by: "customer", byUid: uid, at }),
  };
}

/** Staff: one step forward or a cancel; the current status again only adds [note] (null: nothing to do). */
export function staffUpdate(r: Repair, staffUid: string, status: RepairStatus, note: string | null, at: Timestamp): Change | null {
  const n = note || undefined;
  if (status === r.status) {
    return n === undefined ? null : { status, quote: r.quote, event: { status, note: n, by: "staff", byUid: staffUid, at } };
  }
  if (!STEPS[r.status].includes(status)) fail("INVALID_TRANSITION", `${r.status} -> ${status}`);
  if ((status === "in_progress" || status === "ready") && r.quote.status !== "approved") fail("QUOTE_NOT_APPROVED", r.quote.status);
  return {
    status,
    quote: r.quote,
    event: event({ status, note: n ?? (status === "cancelled" ? "Cancelled by the store." : undefined), by: "staff", byUid: staffUid, at }),
  };
}

/** Staff send or change the quote while the booking is requested, confirmed or in repair; it waits for the customer
 * again. [approved]: the customer said yes at the counter or on the phone. */
export function setQuote(r: Repair, staffUid: string, quotePaise: number, note: string | null, approved: boolean, at: Timestamp): Change {
  if (!QUOTABLE.includes(r.status)) fail("INVALID_TRANSITION", `no quotes once ${r.status}`);
  const status: QuoteStatus = approved ? "approved" : "pending";
  return {
    status: r.status,
    quote: approved ? { paise: quotePaise, status, decidedAt: at } : { paise: quotePaise, status },
    event: event({
      status: r.status, quoteStatus: status, quotePaise, note: note || (approved ? "Agreed with the store." : undefined),
      by: "staff", byUid: staffUid, at,
    }),
  };
}
