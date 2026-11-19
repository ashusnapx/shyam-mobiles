import { z } from "zod";
import { contract } from "../shared/callable.js";
import { cleanMultiline, cleanText, v } from "../shared/validation.js";

// Owner: engineer D. Repair bookings (docs/FIREBASE.md §3 "Repair state machine").
const ok = z.object({});
const booking = z.strictObject({ repairId: v.docId });
const quotePaise = z.number().int().min(0).max(100_000_000); // ₹0 (warranty) to the app's ₹10,00,000 cap

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
export const approveRepairQuote = contract("approveRepairQuote", booking.extend({ quotePaise }), ok);

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
  booking.extend({ quotePaise, note: cleanMultiline(500).nullish(), approved: z.boolean().default(false) }),
  ok,
);

// Growth (docs/GROWTH.md §2c). Exchange your old phone: the customer's description, then staff's estimate (a range).
export const requestExchange = contract(
  "requestExchange",
  z.strictObject({
    brand: cleanText(40, { min: 1, mustHave: "letterOrDigit" }),
    model: cleanText(60, { min: 1, mustHave: "letterOrDigit" }),
    age: z.enum(["under_1", "1_2", "2_3", "over_3"]),
    condition: z.enum(["like_new", "good", "fair", "damaged"]),
    photos: z.array(z.string().regex(/^exchange-photos\/[A-Za-z0-9]{1,128}\/[0-9]{1,15}\.webp$/)).max(3).default([]),
    forProductId: v.slug.nullish(),
  }),
  z.object({ exchangeId: z.string() }),
);

/** Staff: an estimate range (low ≤ high, ₹0 to ₹10,00,000) and a short note; the customer is notified. */
export const estimateExchange = contract(
  "estimateExchange",
  z.strictObject({ exchangeId: v.docId, lowPaise: quotePaise, highPaise: quotePaise, note: cleanMultiline(300).default("") })
    .refine((e) => e.lowPaise <= e.highPaise, { message: "range", path: ["highPaise"] }),
  ok,
);
