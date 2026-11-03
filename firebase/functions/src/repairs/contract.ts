import { z } from "zod";
import { contract } from "../shared/callable.js";
import { cleanMultiline, cleanText, v } from "../shared/validation.js";

// Owner: engineer D. Repair bookings (docs/FIREBASE.md §3 "Repair state machine").
const ok = z.object({});
const booking = z.strictObject({ repairId: v.docId });

/** REPAIR_LIMIT at 3 open bookings; preferredDate today..+30 days (IST). */
export const bookRepair = contract(
  "bookRepair",
  z.strictObject({
    deviceBrand: cleanText(40, { min: 1, mustHave: "letterOrDigit" }),
    deviceModel: cleanText(60, { min: 1, mustHave: "letterOrDigit" }),
    issue: v.repairIssue,
    description: cleanMultiline(500),
    preferredDate: v.calendarDate,
    slot: v.repairSlot,
    contactPhone: v.phone,
  }),
  z.object({ repairId: z.string() }),
);

export const cancelRepair = contract("cancelRepair", booking, ok);

/** Sends the amount the customer was shown: QUOTE_CHANGED if staff changed it meanwhile. */
export const approveRepairQuote = contract("approveRepairQuote", booking.extend({ quotePaise: v.pricePaise }), ok);

export const declineRepairQuote = contract("declineRepairQuote", booking.extend({ reason: cleanMultiline(500).nullish() }), ok);

/** Staff: one step forward or a cancel; the current status again only adds [note]. QUOTE_NOT_APPROVED before work. */
export const adminUpdateRepair = contract(
  "adminUpdateRepair",
  booking.extend({
    status: z.enum(["requested", "confirmed", "in_progress", "ready", "completed", "cancelled"]),
    note: cleanMultiline(500).nullish(),
  }),
  ok,
);

/** Staff: sends or changes the quote; [approved] records a yes given at the counter or on the phone. */
export const adminSetRepairQuote = contract(
  "adminSetRepairQuote",
  booking.extend({ quotePaise: v.pricePaise, note: cleanMultiline(500).nullish(), approved: z.boolean().default(false) }),
  ok,
);
