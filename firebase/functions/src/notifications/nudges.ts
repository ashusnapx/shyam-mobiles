import { DAY_MS } from "../model/retention.js";
import { inr, paise } from "../shared/money.js";

// Growth (docs/GROWTH.md §2d, e). Pure rules for the gentle marketing pushes: a cart left 24 h with something still in
// stock, a wishlist item whose price dropped, and "Protect your new phone" 2 days after a phone is delivered. At most
// one per customer per 3 days, none from 9 pm to 9 am IST, never to someone who turned "Offers & reminders" off
// (users/{uid}.prefs.offers false). That is the Dark Patterns Guidelines' nagging rule: few, timely, switchable.

export const CAP_MS = 3 * DAY_MS;
export const HOUR_MS = 3_600_000;
const IST_OFFSET_MS = 330 * 60_000;

/** 9 pm to 9 am IST. */
export function quietHours(now: Date): boolean {
  const h = new Date(now.getTime() + IST_OFFSET_MS).getUTCHours();
  return h >= 21 || h < 9;
}

/** Another marketing push is allowed only 3 days after the last. */
export const capped = (lastAtMs: number | null | undefined, nowMs: number): boolean => lastAtMs != null && nowMs - lastAtMs < CAP_MS;

/** "Offers & reminders" is on unless the customer turned it off. */
export const optedIn = (prefs: unknown): boolean => (prefs as { offers?: unknown } | undefined)?.offers !== false;

export interface Nudge { id: string; kind: string; title: string; body: string; link: string; imagePath?: string }

/** One push per cart state: the id carries the cart's last change. */
export function cartNudge(cartUpdatedAtMs: number, inStockNames: readonly string[]): Nudge | null {
  const [first, ...rest] = inStockNames;
  if (first === undefined) return null;
  return {
    id: `nudge_cart_${cartUpdatedAtMs}`,
    kind: "cart_reminder",
    title: "Your cart is waiting",
    body: (rest.length === 0 ? `${first} is still in stock.` : `${first} and ${rest.length} more are still in stock.`).slice(0, 300),
    link: "/cart",
  };
}

/** A real drop only: an active, in-stock variant whose price went down. */
export function priceDropped(before: { pricePaise?: unknown }, after: { pricePaise?: unknown; isActive?: unknown; productActive?: unknown; stock?: unknown }): boolean {
  return typeof before.pricePaise === "number" && typeof after.pricePaise === "number" && after.pricePaise < before.pricePaise
    && after.isActive === true && after.productActive === true && typeof after.stock === "number" && after.stock > 0;
}

/** One push per drop: the id carries the variant and its new price. */
export function priceDropNudge(d: { variantId: string; productId: string; productName: string; fromPaise: number; toPaise: number }): Nudge {
  return {
    id: `nudge_drop_${d.variantId}_${d.toPaise}`,
    kind: "price_drop",
    title: `Price dropped: ${d.productName}`.slice(0, 80),
    body: `Now ${inr(paise(d.toPaise))}, was ${inr(paise(d.fromPaise))}. It’s on your wishlist.`,
    link: `/product/${d.productId}?variant=${d.variantId}`,
  };
}

/** When the order was delivered (its first "delivered" event), or null. */
export function deliveredAtMs(events: unknown): number | null {
  for (const e of Array.isArray(events) ? events : []) {
    const { status, at } = (e ?? {}) as { status?: unknown; at?: unknown };
    if (status !== "delivered") continue;
    const ms = at instanceof Date ? at.getTime() : (at as { toMillis?: () => number } | undefined)?.toMillis?.();
    if (typeof ms === "number") return ms;
  }
  return null;
}

/** 2 to 3 days after delivery: the hourly run sends it once in that window. */
export const protectDue = (deliveredMs: number | null, nowMs: number): boolean =>
  deliveredMs !== null && nowMs - deliveredMs >= 2 * DAY_MS && nowMs - deliveredMs < 3 * DAY_MS;

export function protectNudge(orderId: string, phoneName: string, imagePath?: string): Nudge {
  return {
    id: `nudge_protect_${orderId}`,
    kind: "protect_phone",
    title: "Protect your new phone",
    body: `Cases, screen guards and chargers that fit your ${phoneName}.`.slice(0, 300),
    link: `/orders/${orderId}`,
    ...(imagePath ? { imagePath } : {}),
  };
}

/** "Samsung Galaxy S25" → "Galaxy S25" (the app's shortName): accessories' "Fits" spec names the phone this way. */
export const shortName = (name: string, brand: string): string =>
  name.length > brand.length + 1 && name.toLowerCase().startsWith(`${brand.toLowerCase()} `) ? name.slice(brand.length + 1) : name;

/** Is there an in-stock accessory whose "Fits" spec names this phone? (catalogIndex/public cards) */
export function hasFittingAccessory(cards: Record<string, { ft?: unknown; i?: unknown }>, phone: { name: string; brandName: string }): boolean {
  const names = new Set([shortName(phone.name, phone.brandName), phone.name]);
  return Object.values(cards).some((c) => c.i === true && Array.isArray(c.ft) && c.ft.some((f) => typeof f === "string" && names.has(f)));
}
