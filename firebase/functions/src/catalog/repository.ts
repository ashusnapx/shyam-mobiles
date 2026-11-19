import { FieldPath, FieldValue, type DocumentReference, type Transaction } from "firebase-admin/firestore";
import type { CollectionDoc, ProductDoc, VariantDoc } from "../model/catalog.js";
import { db } from "../shared/db.js";
import { log } from "../shared/log.js";
import { cardsFor, INDEX_WARN_BYTES, type WithId } from "./cards.js";
import { categoryOf, chunkId, KINDS, manifestId, planChunks } from "./shard.js";

// Firestore reads and writes of the catalog. The index chunks are rebuilt one product at a time from the source
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
 * Recomputes the index entries of [productIds] (deleted or hidden products drop out of the public ones) in one
 * transaction, writing only the chunks that changed (shard.ts) and bumping their versions in the manifests. Called by
 * the triggers and, after their own write, by the handlers, so staff see an edit as soon as the callable returns.
 */
export async function refreshIndex(productIds: Iterable<string>): Promise<void> {
  const ids = [...new Set(productIds)];
  if (ids.length === 0) return;
  const fs = db();
  const index = fs.collection("catalogIndex");
  await fs.runTransaction(async (tx) => {
    const products = await tx.getAll(...ids.map(productRef));
    const variants = new Map<string, WithId<VariantDoc>[]>(ids.map((id) => [id, []]));
    const collections = new Map<string, Set<string>>(ids.map((id) => [id, new Set()])); // a doc can match two chunks
    const loaded = new Map<string, Record<string, unknown>>(); // chunk id -> its cards
    const versions = new Map<string, number>();
    const keep = (cid: string, d: { get(f: string): unknown }) => {
      loaded.set(cid, (d.get("cards") ?? {}) as Record<string, unknown>);
      versions.set(cid, (d.get("v") as number | undefined) ?? 0);
    };
    for (const part of chunks(ids, IN_LIMIT)) {
      for (const d of (await tx.get(fs.collection("variants").where("productId", "in", part))).docs) {
        const v = { ...(d.data() as VariantDoc), id: d.id };
        variants.get(v.productId)?.push(v);
      }
      for (const d of (await tx.get(fs.collection("collections").where("productIds", "array-contains-any", part))).docs) {
        for (const pid of (d.data() as CollectionDoc).productIds) collections.get(pid)?.add(d.id);
      }
      for (const d of (await tx.get(index.where("ids", "array-contains-any", part))).docs) keep(d.id, d); // where they are now
    }
    const next = new Map(ids.map((id, i) => {
      const snap = products[i];
      return [id, cardsFor(id, snap?.exists ? (snap.data() as ProductDoc) : null, variants.get(id) ?? [], [...(collections.get(id) ?? [])])] as const;
    }));
    const wanted = new Set<string>(); // where they belong now
    for (const [id, e] of next) for (const kind of KINDS) {
      const card = e[kind];
      if (card !== null) wanted.add(chunkId(kind, card.c, id));
    }
    const missing = [...wanted].filter((cid) => !loaded.has(cid));
    if (missing.length > 0) {
      const docs = await tx.getAll(...missing.map((cid) => index.doc(cid)));
      docs.forEach((d, i) => { keep(missing[i] ?? "", d); });
    }
    const plan = planChunks(loaded, next);
    for (const kind of KINDS) {
      const man: Record<string, unknown> = {};
      for (const [cid, { set, del }] of plan) {
        if (!cid.startsWith(`${kind}_`)) continue;
        const cards = { ...loaded.get(cid), ...set };
        const have = Object.keys(cards).filter((id) => !del.includes(id));
        const ref = index.doc(cid);
        if (have.length === 0) {
          tx.delete(ref);
          man[cid] = FieldValue.delete();
          continue;
        }
        const v = (versions.get(cid) ?? 0) + 1;
        const c = categoryOf(cid);
        const size = JSON.stringify(have.map((id) => cards[id])).length;
        if (size > INDEX_WARN_BYTES) log.warn("an index chunk is getting big: raise BUCKETS in catalog/shard.ts (docs/FIREBASE.md D3)", { chunk: cid, bytes: size });
        tx.set(ref, { cards: { ...set, ...Object.fromEntries(del.map((id) => [id, FieldValue.delete()])) }, ids: have, v, c, updatedAt: FieldValue.serverTimestamp() }, {
          mergeFields: [...[...Object.keys(set), ...del].map((id) => new FieldPath("cards", id)), "ids", "v", "c", "updatedAt"],
        });
        man[cid] = { v, c, n: have.length };
      }
      const ids2 = Object.keys(man);
      if (ids2.length > 0) {
        tx.set(index.doc(manifestId(kind)), { updatedAt: FieldValue.serverTimestamp(), chunks: man }, {
          mergeFields: [...ids2.map((cid) => new FieldPath("chunks", cid)), "updatedAt"],
        });
      }
    }
  });
}

/** Every public card (all chunks), for the server-side checks that scan the catalogue (nudges). */
export async function readPublicCards(): Promise<Record<string, Record<string, unknown>>> {
  const snap = await db().collection("catalogIndex").where(FieldPath.documentId(), ">=", "public_").where(FieldPath.documentId(), "<", "public`").get();
  return Object.assign({}, ...snap.docs.map((d) => (d.get("cards") ?? {}) as Record<string, Record<string, unknown>>)) as Record<string, Record<string, unknown>>;
}

/** Builds every chunk from the source docs (first deploy of the sharded index, or after changing BUCKETS), 100 products at a time. */
export async function rebuildIndex(): Promise<void> {
  const refs = await db().collection("products").listDocuments();
  for (const part of chunks(refs.map((r) => r.id), 100)) await refreshIndex(part);
}
