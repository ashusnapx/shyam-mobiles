// Calendar maths in India Standard Time (UTC+5:30, no DST), for booking windows, monthly referral caps and the GST
// financial year. Instants stay Dates/Timestamps; only these helpers turn them into IST calendar strings.

const IST_OFFSET_MS = 330 * 60 * 1000;
const ist = (d: Date) => new Date(d.getTime() + IST_OFFSET_MS);

/** 'YYYY-MM-DD' of [d] in IST. */
export const istDate = (d: Date): string => ist(d).toISOString().slice(0, 10);

/** 'YYYYMM' of [d] in IST (users.referralRewards keys). */
export const istMonth = (d: Date): string => ist(d).toISOString().slice(0, 7).replace("-", "");

/** The IST midnight that starts [d]'s day, as an instant. */
export function istMidnight(d: Date): Date {
  const day = istDate(d);
  return new Date(Date.parse(`${day}T00:00:00Z`) - IST_OFFSET_MS);
}

/** 'YYYY-MM-DD' [days] after [date] (calendar arithmetic, no time zone involved). */
export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** The Indian financial year (April to March) holding [d], as '26-27'. */
export function financialYear(d: Date): string {
  const t = ist(d);
  const start = t.getUTCMonth() >= 3 ? t.getUTCFullYear() : t.getUTCFullYear() - 1;
  return `${String(start % 100).padStart(2, "0")}-${String((start + 1) % 100).padStart(2, "0")}`;
}
