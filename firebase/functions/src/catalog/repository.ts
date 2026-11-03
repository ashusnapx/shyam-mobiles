import { FieldPath, FieldValue, type DocumentReference, type Transaction } from "firebase-admin/firestore";
import type { CollectionDoc, ProductDoc, VariantDoc } from "../model/catalog.js";
import { db } from "../shared/db.js";
import { log } from "../shared/log.js";
import { cardsFor, INDEX_WARN_BYTES, sameCard, type WithId } from "./cards.js";

// Firestore reads and writes of the catalog. The two index docs are rebuilt one product at a time from the source
// docs (products, variants, collections), so a retry or a duplicate run changes nothing.

export const productRef = (id: string) => db().doc(`products/${id}`) as DocumentReference<ProductDoc>;
export const variantRef = (id: string) => db().doc(`variants/${id}`) as DocumentReference<VariantDoc>;
export const variantsOf = (productId: string) => db().collection("variants").where("productId", "==", productId);

const IN_LIMIT = 30; // Firestore's `in` / `array-contains-any` cap
const chunks = <T>(xs: T[], n: number) => Array.from({ length: Math.ceil(xs.length / n) }, (_, i) => xs.slice(i * n, i * n + n));

/** Variants of [productId] in [tx], with their ids. */
export async function readVariants(tx: Transaction, productId: string): Promise<WithId<VariantDoc>[]> {
  const snap = await tx.get(variantsOf(productId));
  return snap.docs.map((d) => ({ ...(d.data() as VariantDoc), id: d.id }));
}

/**
 * Recomputes the index entries of [productIds] (deleted or hidden products drop out of the public one) in one
 * transaction, writing only the entries that changed. Called by the triggers and, after their own write, by the
 * handlers, so staff see an edit in the catalogue as soon as the callable returns.
 */
export async function refreshIndex(productIds: Iterable<string>): Promise<void> {
  const ids = [...new Set(productIds)];
  if (ids.length === 0) return;
  const fs = db();
  const pubRef = fs.doc("catalogIndex/public");
  const staffRef = fs.doc("catalogIndex/staff");
  await fs.runTransaction(async (tx) => {
    const [pub, staff] = await tx.getAll(pubRef, staffRef);
    const pubCards = (pub?.get("cards") ?? {}) as Record<string, unknown>;
    const staffCards = (staff?.get("cards") ?? {}) as Record<string, unknown>;
    const products = await tx.getAll(...ids.map(productRef));
    const variants = new Map<string, WithId<VariantDoc>[]>(ids.map((id) => [id, []]));
    const collections = new Map<string, Set<string>>(ids.map((id) => [id, new Set()])); // a doc can match two chunks
    for (const part of chunks(ids, IN_LIMIT)) {
      for (const d of (await tx.get(fs.collection("variants").where("productId", "in", part))).docs) {
        const v = { ...(d.data() as VariantDoc), id: d.id };
        variants.get(v.productId)?.push(v);
      }
      for (const d of (await tx.get(fs.collection("collections").where("productIds", "array-contains-any", part))).docs) {
        for (const pid of (d.data() as CollectionDoc).productIds) collections.get(pid)?.add(d.id);
      }
    }
    const pubChanges: Record<string, unknown> = {};
    const staffChanges: Record<string, unknown> = {};
    for (const [i, id] of ids.entries()) {
      const snap = products[i];
      const next = cardsFor(id, snap?.exists ? (snap.data() as ProductDoc) : null, variants.get(id) ?? [], [...(collections.get(id) ?? [])]);
      if (!sameCard(next.public ?? undefined, pubCards[id])) pubChanges[id] = next.public ?? FieldValue.delete();
      if (!sameCard(next.staff ?? undefined, staffCards[id])) staffChanges[id] = next.staff ?? FieldValue.delete();
    }
    writeEntries(tx, pubRef, pubChanges);
    writeEntries(tx, staffRef, staffChanges);
    const bytes = JSON.stringify(staffCards).length;
    if (bytes > INDEX_WARN_BYTES) log.warn("catalogIndex/staff is getting big: shard it by category (docs/FIREBASE.md §1)", { bytes });
  });
}

/** Sets or deletes `cards.<id>` for each change, creating the doc on first use; other entries stay as they are. */
function writeEntries(tx: Transaction, ref: DocumentReference, changes: Record<string, unknown>): void {
  const ids = Object.keys(changes);
  if (ids.length === 0) return;
  tx.set(ref, { cards: changes, updatedAt: FieldValue.serverTimestamp() }, {
    mergeFields: [...ids.map((id) => new FieldPath("cards", id)), "updatedAt"],
  });
}
