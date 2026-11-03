import type { DocumentReference, FieldValue, Timestamp, Transaction } from "firebase-admin/firestore";
import type { VariantDoc } from "../model/catalog.js";
import { fail } from "../shared/errors.js";

// The one stock writer (docs/FIREBASE.md §3 "Stock never negative", §6 back-in-stock). Staff edits (saveVariant,
// updateVariants) and C's order, cancel, expiry and refund code all go through applyStockChange, so stock never goes
// below 0 and every 0 → > 0 bumps restockSeq, which D's back-in-stock trigger keys its notifications on.

export const MAX_STOCK = 1_000_000;

/** Set the count (a stock take, the variant form) or move it (an order −qty, a restock +qty). */
export type StockChange = { set: number } | { delta: number };

export type StockReason = VariantDoc["lastStockChange"];

/** What the change does to [current]. OUT_OF_STOCK (detail: [variantId]) below 0; BAD_REQUEST above 1e6. */
export function nextStock(
  variantId: string,
  current: Pick<VariantDoc, "stock"> & { restockSeq?: number },
  change: StockChange,
): { stock: number; restockSeq: number } {
  const stock = "set" in change ? change.set : current.stock + change.delta;
  if (!Number.isSafeInteger(stock)) fail("BAD_REQUEST", ["stock"]);
  if (stock < 0) fail("OUT_OF_STOCK", [variantId]);
  if (stock > MAX_STOCK) fail("BAD_REQUEST", ["stock"]);
  const seq = current.restockSeq ?? 0;
  return { stock, restockSeq: current.stock <= 0 && stock > 0 ? seq + 1 : seq };
}

/**
 * Writes [change] to the variant in [tx]: stock, restockSeq, lastStockChange = [by], updatedAt = [at], plus [also]
 * (the caller's other fields, so the variant gets one write). [current] is the variant as read earlier in the same
 * transaction (Firestore reads come before writes). Returns the new stock.
 */
export function applyStockChange(
  tx: Transaction,
  ref: DocumentReference,
  current: Pick<VariantDoc, "stock"> & { restockSeq?: number },
  change: StockChange,
  by: StockReason,
  at: Timestamp | FieldValue,
  also: Record<string, unknown> = {},
): number {
  const next = nextStock(ref.id, current, change);
  tx.update(ref, { ...also, stock: next.stock, restockSeq: next.restockSeq, lastStockChange: by, updatedAt: at });
  return next.stock;
}
