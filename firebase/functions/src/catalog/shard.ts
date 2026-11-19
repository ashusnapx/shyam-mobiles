import type { CatalogCard, StaffCatalogCard } from "../model/catalog.js";
import { sameCard } from "./cards.js";

// Sharding of the catalog index (docs/FIREBASE.md D3): catalogIndex/<kind>_<category>_<bucket> holds the entries of one
// category whose id hashes to that bucket; <kind>_manifest lists every chunk with its version. The bucket count is
// fixed, so a product's chunk depends only on its id and category: it never moves unless its category changes.

export type Kind = "public" | "staff";
export const KINDS: Kind[] = ["public", "staff"];
/** shortcut: fixed 8 buckets per category (~5 MB of staff entries per category at 700 KB a chunk), raise it (and rebuild) past that. */
export const BUCKETS = 8;

/** FNV-1a: the same everywhere, unlike a platform's string hash. */
export function bucketOf(id: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 0x01000193) >>> 0;
  return h % BUCKETS;
}

export const chunkId = (kind: Kind, category: string, id: string) => `${kind}_${category}_${bucketOf(id)}`;
export const manifestId = (kind: Kind) => `${kind}_manifest`;
/** "public_phones_3" -> "phones" (category slugs have no underscore). */
export const categoryOf = (chunk: string) => chunk.split("_")[1] ?? "";

export type Entries = ReadonlyMap<string, { public: CatalogCard | null; staff: StaffCatalogCard | null }>;
export interface ChunkChange { set: Record<string, unknown>; del: string[] }

/**
 * Which chunks must change so every product in [next] is where it belongs. [chunks] holds the current entries of the
 * chunks that matter (every chunk that has one of the products, and the chunks they belong in). Only chunks with a
 * real change are returned, so an unchanged product writes nothing.
 */
export function planChunks(chunks: ReadonlyMap<string, Record<string, unknown>>, next: Entries): Map<string, ChunkChange> {
  const at = new Map<string, string>(); // `${kind}:${id}` -> chunk now holding it
  for (const [cid, cards] of chunks) for (const id of Object.keys(cards)) if (next.has(id)) at.set(`${cid.startsWith("public_") ? "public" : "staff"}:${id}`, cid);
  const out = new Map<string, ChunkChange>();
  const of = (cid: string): ChunkChange => {
    const c = out.get(cid) ?? { set: {}, del: [] };
    out.set(cid, c);
    return c;
  };
  for (const [id, e] of next) {
    const category = (e.staff ?? e.public)?.c;
    for (const kind of KINDS) {
      const card = e[kind];
      const now = at.get(`${kind}:${id}`);
      const to = card && category !== undefined ? chunkId(kind, category, id) : undefined;
      if (now !== undefined && now !== to) of(now).del.push(id);
      if (to !== undefined && !sameCard(card, chunks.get(to)?.[id])) of(to).set[id] = card;
    }
  }
  return out;
}
