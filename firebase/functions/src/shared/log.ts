import { logger } from "firebase-functions";

// The only logger in the backend (docs/SECURITY.md §2.6, §4.1): structured lines with no personal data. Keys that
// hold personal data are redacted whatever their value, and strings are scrubbed of phone numbers, emails and
// token-like runs, so a careless `log.info("x", order)` still leaks nothing. Uids, doc ids, amounts and reasons stay.

const PII_KEYS = new Set([
  "name", "fullname", "legalname", "displayname", "phone", "contactphone", "phonenumber", "email", "address", "line1",
  "line2", "landmark", "pincode", "gstin", "imeis", "token", "idtoken", "fcmtoken", "authorization", "password",
  "secret", "otp", "code", "photourl", "description", "message", "note", "adminnote",
]);

const SCRUB: [RegExp, string][] = [
  [/eyJ[\w-]+\.[\w-]+\.[\w-]*/g, "[jwt]"],
  [/[\w.+-]+@[\w-]+\.[\w.-]+/g, "[email]"],
  [/(?<!\d)(?:\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}(?!\d)/g, "[phone]"],
  [/\b[A-Za-z0-9_-]{32,}\b/g, "[token]"],
];

function scrubString(s: string): string {
  return SCRUB.reduce((out, [re, mask]) => out.replace(re, mask), s);
}

/** A copy of [value] that is safe to log. Exported for tests. */
export function redact(value: unknown, depth = 0): unknown {
  if (typeof value === "string") return scrubString(value);
  if (value === null || typeof value !== "object") return value;
  if (depth > 6) return "[deep]";
  if (value instanceof Error) return { error: value.name, message: scrubString(value.message) };
  if (Array.isArray(value)) return value.slice(0, 50).map((v) => redact(v, depth + 1));
  return Object.fromEntries(
    Object.entries(value).map(([k, v]) => [k, PII_KEYS.has(k.toLowerCase()) ? "[redacted]" : redact(v, depth + 1)]),
  );
}

type Fields = Record<string, unknown>;
const line = (fields?: Fields) => (fields === undefined ? [] : [redact(fields)]);

export const log = {
  debug: (msg: string, fields?: Fields): void => {
    logger.debug(scrubString(msg), ...line(fields));
  },
  info: (msg: string, fields?: Fields): void => {
    logger.info(scrubString(msg), ...line(fields));
  },
  warn: (msg: string, fields?: Fields): void => {
    logger.warn(scrubString(msg), ...line(fields));
  },
  error: (msg: string, fields?: Fields): void => {
    logger.error(scrubString(msg), ...line(fields));
  },
};

/** One audit line per staff action, routed to the 400-day security log bucket by its `audit: true` field. */
export function audit(action: string, actorUid: string, targetId: string | null, fields?: Fields): void {
  logger.info(`audit ${action}`, { audit: true, action, actorUid, targetId, ...(redact(fields ?? {}) as Fields) });
}
