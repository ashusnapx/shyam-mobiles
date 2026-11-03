import { onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import type { BrandDoc, CategoryDoc, CollectionDoc } from "../model/catalog.js";
import { db } from "../shared/db.js";
import { BACKGROUND } from "../shared/options.js";
import { refreshIndex } from "./repository.js";

// Keep the denormalised copies in step (docs/FIREBASE.md §3 "Denormalised fields"). Retried: every body recomputes
// from the source docs, so a second run is a no-op.

const opts = <D extends string>(document: D) => ({ ...BACKGROUND, document, retry: true });

/** A product's own edits (and saveProduct's): its entry in both indexes. */
export const catalogOnProduct = onDocumentWritten(opts("products/{id}"), (e) => refreshIndex([e.params.id]));

/** Stock, price and visibility (staff edits, and C's orders, cancels and refunds): the product's entry. */
export const catalogOnVariant = onDocumentWritten(opts("variants/{id}"), (e) => {
  const ids = [e.data?.before.get("productId") as unknown, e.data?.after.get("productId") as unknown];
  return refreshIndex(ids.filter((id): id is string => typeof id === "string"));
});

/** A collection's members: only the products that joined or left it get a new `col` list. */
export const catalogOnCollection = onDocumentWritten(opts("collections/{id}"), (e) => {
  const before = new Set((e.data?.before.data() as CollectionDoc | undefined)?.productIds ?? []);
  const after = new Set((e.data?.after.data() as CollectionDoc | undefined)?.productIds ?? []);
  return refreshIndex([...before, ...after].filter((id) => before.has(id) !== after.has(id)));
});

/** A renamed brand: every product's brandName (their own triggers then refresh the index). */
export const catalogOnBrand = onDocumentUpdated(opts("brands/{id}"), async (e) => {
  const name = (e.data?.after.data() as BrandDoc | undefined)?.name;
  if (name === undefined || name === (e.data?.before.data() as BrandDoc | undefined)?.name) return;
  await rewriteProducts("brandId", e.params.id, { brandName: name });
});

/** A category moved between phones and accessories: every product's categoryKind. */
export const catalogOnCategory = onDocumentUpdated(opts("categories/{id}"), async (e) => {
  const kind = (e.data?.after.data() as CategoryDoc | undefined)?.kind;
  if (kind === undefined || kind === (e.data?.before.data() as CategoryDoc | undefined)?.kind) return;
  await rewriteProducts("categoryId", e.params.id, { categoryKind: kind });
});

async function rewriteProducts(field: "brandId" | "categoryId", id: string, data: Record<string, unknown>): Promise<void> {
  const writer = db().bulkWriter();
  for (const d of (await db().collection("products").where(field, "==", id).get()).docs) void writer.update(d.ref, { ...data, updatedAt: FieldValue.serverTimestamp() });
  await writer.close();
}
