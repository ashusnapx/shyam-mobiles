// Money is whole paise in safe integers, never floats (docs/FIREBASE.md §2 "Money"). The brand stops a raw number
// (a quantity, a rupee amount) from being passed where paise are meant; every constructor checks the value.

export type Paise = number & { readonly __paise: true };

/** Largest order total the old int4 columns allowed; placeOrder refuses more with ORDER_TOO_LARGE. */
export const MAX_ORDER_PAISE = 2_147_483_647 as Paise;

export function paise(n: number): Paise {
  if (!Number.isSafeInteger(n) || n < 0) throw new RangeError(`not a paise amount: ${n}`);
  return n as Paise;
}

export const ZERO = 0 as Paise;
export const add = (a: Paise, b: Paise): Paise => paise(a + b);
/** a − b, refusing to go below zero. */
export const sub = (a: Paise, b: Paise): Paise => paise(a - b);
export const times = (a: Paise, qty: number): Paise => paise(a * qty);
export const sum = (xs: readonly Paise[]): Paise => xs.reduce(add, ZERO);
export const min = (a: Paise, b: Paise): Paise => (a < b ? a : b);

/** [pct]% of [a], rounded down: percent offers never give away a fraction of a paisa. */
export function percentOf(a: Paise, pct: number): Paise {
  if (!Number.isInteger(pct) || pct < 0 || pct > 100) throw new RangeError(`not a percent: ${pct}`);
  return paise(Math.floor((a * pct) / 100));
}

/** ₹ in Indian grouping, as the app's formatInr: 12999900 → "₹1,29,999", 4950 → "₹49.50". */
export function inr(a: Paise): string {
  const rupees = String(Math.floor(a / 100)).replace(/(\d)(?=(\d\d)+\d$)/g, "$1,");
  return `₹${rupees}${a % 100 ? `.${String(a % 100).padStart(2, "0")}` : ""}`;
}
