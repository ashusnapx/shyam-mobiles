import type { OrderDoc } from "../model/orders.js";
import type { RepairDoc } from "../model/repairs.js";

// Owner: engineer A. The account rules as pure functions (docs/FIREBASE.md §4, docs/SECURITY.md §4.6–4.7), so unit
// tests cover them without an emulator; repository.ts and handlers.ts do the reads and writes.

const ORDER_DONE = new Set<OrderDoc["status"]>(["delivered", "cancelled", "refunded"]);
const REPAIR_DONE = new Set<RepairDoc["status"]>(["completed", "cancelled"]);

/**
 * ACTIVE_ORDERS (today's delete-account Edge Function): an order or repair still open, or a cancelled order that was
 * paid and not yet refunded, which the customer would lose sight of.
 */
export function blocksDeletion(
  orders: readonly Pick<OrderDoc, "status" | "paymentStatus">[],
  repairs: readonly Pick<RepairDoc, "status">[],
): boolean {
  return orders.some((o) => !ORDER_DONE.has(o.status) || (o.status === "cancelled" && o.paymentStatus === "paid")) ||
    repairs.some((r) => !REPAIR_DONE.has(r.status));
}

/** Who may become the owner (claimOwner): nobody holds the role yet (or the caller already does, so a retry after a
 * half-done claim finishes it), and the caller's verified phone is the shop's own. */
export function mayClaimOwner(caller: { uid: string; phone: string | undefined }, shopPhone: string | undefined, ownerUids: readonly string[]): boolean {
  return shopPhone !== undefined && caller.phone === shopPhone && ownerUids.every((u) => u === caller.uid);
}

/** A Firestore value as plain JSON for "Download my data": Timestamps become ISO strings, nothing else changes. */
export function plain(value: unknown): unknown {
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map(plain);
  const ts = value as { toDate?: unknown };
  if (typeof ts.toDate === "function") return (ts.toDate as () => Date).call(value).toISOString();
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
}
