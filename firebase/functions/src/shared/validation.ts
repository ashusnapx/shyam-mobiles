import { z } from "zod";
import { fail, type Reason } from "./errors.js";

// Input rules for every callable (docs/FIREBASE.md §3 "Where each invariant is enforced"). The same rules run in
// firestore.rules (RE2 regexes) and app/lib/core/input.dart; all three are checked against test-vectors/input.json
// (test/unit/validation.test.ts here). Change a rule and its vector samples together.

// Characters people never mean to type: controls, soft hyphen, bidi overrides, zero-width (ZWJ/ZWNJ stay: Hindi).
// eslint-disable-next-line no-control-regex -- matching control characters is the point
const INVISIBLE = /[\u{0}-\u{1F}\u{7F}-\u{9F}\u{AD}\u{61C}\u{180E}\u{200B}\u{200E}\u{200F}\u{2028}\u{2029}\u{202A}-\u{202E}\u{2060}-\u{2064}\u{2066}-\u{206F}\u{FEFF}\u{FFF9}-\u{FFFB}]/u;
const INVISIBLE_BUT_NEWLINE = new RegExp(INVISIBLE.source.replace("\\u{0}-\\u{1F}", "\\u{0}-\\u{9}\\u{B}-\\u{1F}"), "u");
const LETTER = /\p{L}/u;
const LETTER_OR_DIGIT = /[\p{L}\p{N}]/u;
const codePoints = (s: string) => Array.from(s).length; // code points, not UTF-16 units: "क्ष" is 3

/** One-line text: no invisible characters, trimmed, [min]..[max] code points ("क्ष" counts 3). */
export function cleanText(max: number, { min = 0, mustHave }: { min?: number; mustHave?: "letter" | "letterOrDigit" } = {}) {
  return z.string().refine(
    (s) =>
      !INVISIBLE.test(s) && s === s.trim() && codePoints(s) >= min && codePoints(s) <= max &&
      (s === "" || /\S/u.test(s)) &&
      (mustHave === undefined || (mustHave === "letter" ? LETTER : LETTER_OR_DIGIT).test(s)),
    { message: "text" },
  );
}

/** Text with line breaks: each line trimmed, at most one blank line in a row, no blank first or last line. */
export function cleanMultiline(max: number, { min = 0 }: { min?: number } = {}) {
  return z.string().refine((s) => {
    if (INVISIBLE_BUT_NEWLINE.test(s) || codePoints(s) < min || codePoints(s) > max) return false;
    if (s === "") return true;
    const lines = s.split("\n");
    return lines.every((l) => l === l.trim()) && !s.includes("\n\n\n") && lines[0] !== "" && lines.at(-1) !== "" && /\S/u.test(s);
  }, { message: "text" });
}

function luhnOk(digits: string): boolean {
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let d = Number(digits[digits.length - 1 - i]);
    if (i % 2 === 1) d = d * 2 > 9 ? d * 2 - 9 : d * 2;
    sum += d;
  }
  return sum % 10 === 0;
}

function realDate(s: string): boolean {
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().startsWith(s);
}

const intIn = (min: number, max: number) => z.number().int().min(min).max(max);

export const v = {
  /** A Firestore doc id we accept from a client. */
  docId: z.string().regex(/^[A-Za-z0-9_-]{1,128}$/),
  phone: z.string().regex(/^\+91[6-9][0-9]{9}$/),
  pincode: z.string().regex(/^[1-9][0-9]{5}$/),
  personName: z.string().refine(
    (s) => /^[\p{L}\p{M} .'-]+$/u.test(s) && s === s.trim() && codePoints(s) >= 2 && codePoints(s) <= 60 &&
      (s.match(/\p{L}/gu)?.length ?? 0) >= 2,
    { message: "name" },
  ),
  addressName: cleanText(80, { min: 2, mustHave: "letter" }),
  placeName: cleanText(60, { min: 2, mustHave: "letter" }),
  imei: z.string().regex(/^[0-9]{15}$/).refine(luhnOk, { message: "imei" }),
  slug: z.string().regex(/^[a-z0-9-]{1,160}$/),
  sku: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._/-]{0,59}$/),
  hexColor: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  /** Both the old DB rule and the app's route list must agree (test-vectors/input.json bannerLink). */
  bannerLink: z.string().max(200).regex(/^\/(search|product\/|offers|repairs)[A-Za-z0-9/?=&%._~+-]*$/)
    .regex(/^\/(search(\?[^#\s]*)?|product\/[a-z0-9-]{1,160}|offers(\/[0-9a-f-]{36})?|repairs(\/new)?)$/),
  appRoute: z.string().max(200)
    .regex(/^\/(orders\/|repairs\/|offers|product\/|admin\/orders\/|admin\/repairs\/|admin\/feedback\/|admin\/products\/|admin\/catalogue)[A-Za-z0-9/?=&%._~+-]*$/),
  feedbackScreen: z.string().max(200).regex(/^\/[A-Za-z0-9/_?=&.%-]*$/),
  /** The stored form. Typed codes go through [typedCode] first. */
  couponCode: z.string().regex(/^[A-Z0-9]{4,20}$/),
  referralCode: z.string().regex(/^[A-Z0-9]{6,10}$/),
  /** What a customer types: uppercased, all whitespace removed, then at most 40 characters. */
  typedCode: z.string().max(60).transform((s) => s.replace(/\s+/gu, "").toUpperCase()).pipe(z.string().max(40)),
  imagePath: z.string().regex(/^[A-Za-z0-9_-]{1,80}\/[A-Za-z0-9_@-]{1,80}\.(webp|jpe?g|png)$/),
  storePhotoPath: z.string().regex(/^store\/[0-9]{1,15}\.(webp|jpe?g|png)$/),
  appVersion: z.string().max(40).regex(/^[0-9A-Za-z.+-]+$/),
  /** An IST calendar date, 'YYYY-MM-DD'. */
  calendarDate: z.string().regex(/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/).refine(realDate, { message: "date" }),
  mapPin: z.strictObject({ lat: z.number().min(6).max(38), lng: z.number().min(68).max(98) }),
  addressLabel: z.enum(["home", "work", "other"]),
  repairIssue: z.enum(["screen", "battery", "charging", "camera", "audio", "water_damage", "software", "other"]),
  repairSlot: z.enum(["morning", "afternoon", "evening"]),
  paymentMethod: z.enum(["online", "cod"]),
  /** Prices: whole paise, ₹0.01 to ₹10,00,000 (the app's cap). */
  pricePaise: intIn(1, 100_000_000),
  deliveryFeePaise: intIn(0, 1_000_000),
  codMaxPaise: intIn(0, 100_000_000),
  stock: intIn(0, 1_000_000),
  gstRateBp: intIn(0, 2800),
  cartQty: intIn(1, 5),
};

/** Parses callable input, or fails with [reason]; BAD_REQUEST names only the failing paths (never the values). */
export function parse<S extends z.ZodType>(schema: S, data: unknown, reason: Reason = "BAD_REQUEST"): z.output<S> {
  const r = schema.safeParse(data);
  if (!r.success) fail(reason, reason === "BAD_REQUEST" ? r.error.issues.map((i) => i.path.join(".")).slice(0, 10) : undefined);
  return r.data;
}
