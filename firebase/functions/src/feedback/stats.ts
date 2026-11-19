import { addDays } from "../shared/time.js";

// Growth (docs/GROWTH.md §2b). Pure rules for the counted numbers on a product page: "N bought this week" and
// "Frequently bought together". An order counts once, when it is first paid or delivered, and comes back out if it
// is later cancelled or refunded. Only counted numbers are shown, never typed-in ones (false urgency).

export const SOLD_DAYS = 7;

interface OrderLike { status?: unknown; paymentStatus?: unknown; items?: unknown }

/** Paid or delivered, and not taken back. */
export const counts = (o: OrderLike | undefined | null): boolean =>
  !!o && (o.paymentStatus === "paid" || o.status === "delivered") && !gone(o);

/** Cancelled or refunded: whatever it counted comes back out. */
export const gone = (o: OrderLike): boolean => o.status === "cancelled" || o.status === "refunded" || o.paymentStatus === "refunded";

/** Units per product in the order. */
export function units(items: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  for (const i of Array.isArray(items) ? items : []) {
    const { productId, qty } = (i ?? {}) as { productId?: unknown; qty?: unknown };
    if (typeof productId !== "string" || typeof qty !== "number" || !Number.isInteger(qty) || qty <= 0) continue;
    out[productId] = (out[productId] ?? 0) + qty;
  }
  return out;
}

/** The daily counts with [qty] (negative to take back) added on [day], days older than the 7 ending [today] dropped,
 * and no day left at 0 or below. */
export function addSold(sold: Record<string, number> | undefined, day: string, qty: number, today: string): Record<string, number> {
  const oldest = addDays(today, -(SOLD_DAYS - 1));
  const next = { ...sold, [day]: (sold?.[day] ?? 0) + qty };
  return Object.fromEntries(Object.entries(next).filter(([d, n]) => d >= oldest && d <= today && n > 0));
}

/** The other products' co-purchase counts with [sign] (+1 or −1) for every product the order held besides [self];
 * none left at 0 or below. */
export function addWith(withCounts: Record<string, number> | undefined, self: string, productIds: readonly string[], sign: 1 | -1): Record<string, number> {
  const next = { ...withCounts };
  for (const p of productIds) if (p !== self) next[p] = (next[p] ?? 0) + sign;
  return Object.fromEntries(Object.entries(next).filter(([, n]) => n > 0));
}
