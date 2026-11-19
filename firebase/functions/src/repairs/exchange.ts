import { inr, paise } from "../shared/money.js";

// Growth (docs/GROWTH.md §2c). Pure: the customer's notice when staff estimate their old phone. Never a single
// promised price: a range, and the final value is the shop's after checking the phone.

/** "₹4,000–₹5,000", or "₹4,000" when both ends match. */
export const estimateRange = (low: number, high: number): string =>
  low === high ? inr(paise(low)) : `${inr(paise(low))}–${inr(paise(high))}`;

export function exchangeNotice(uid: string, phone: { brand: string; model: string }, low: number, high: number, atMs: number) {
  return {
    recipient: uid,
    key: String(atMs), // a new estimate notifies again; a retry doesn't
    kind: "exchange_estimate",
    title: `Exchange estimate: ${phone.brand} ${phone.model}`.slice(0, 80),
    body: `About ${estimateRange(low, high)} for your old phone. The final value is set when the shop checks it.`,
    link: "/repairs/exchanges",
  };
}
