// Loads seed/dev.json (the sample catalogue converted from supabase/seed.sql, and the shop's settings) into the
// Firestore EMULATOR, then writes both catalog index docs with the same builder the triggers use. Emulator only: it
// refuses to run unless FIRESTORE_EMULATOR_HOST is set and the project id starts with demo-.
//
//   cd firebase && npm --prefix functions run build && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node seed/seed.ts
//
// Plain Node (22 strips the types); firebase-admin comes from functions/node_modules, the builder from functions/lib.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { cardsFor } from "../functions/lib/catalog/cards.js";

const require = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const PROJECT = process.env.GCLOUD_PROJECT ?? "demo-shyam-mobiles";
if (!process.env.FIRESTORE_EMULATOR_HOST || !PROJECT.startsWith("demo-")) {
  console.error("seed.ts writes only to the Firestore emulator of a demo- project. Set FIRESTORE_EMULATOR_HOST.");
  process.exit(1);
}

type Doc = Record<string, unknown>;
const { docs } = JSON.parse(readFileSync(new URL("dev.json", import.meta.url), "utf8")) as { docs: Record<string, Doc> };

const now = Timestamp.now();
const db = getFirestore(initializeApp({ projectId: PROJECT }));
const stamped = (d: Doc): Doc => ({
  ...Object.fromEntries(Object.entries(d).map(([k, v]) => [k, v === "@now" ? now : v])),
  ...("createdAt" in d ? {} : { createdAt: now }),
  updatedAt: now,
});

const all = Object.entries(docs).map(([path, d]) => [path, stamped(d)] as const);
const writer = db.bulkWriter();
for (const [path, d] of all) void writer.set(db.doc(path), d);

// The index, from the docs just written (the triggers, when the functions emulator runs too, find nothing to change).
const of = (prefix: string) => all.filter(([p]) => p.startsWith(prefix)).map(([p, d]) => ({ ...d, id: p.slice(prefix.length) }) as Doc & { id: string });
const variants = of("variants/");
const collections = of("collections/");
const pub: Doc = {};
const staff: Doc = {};
for (const p of of("products/")) {
  const cards = cardsFor(
    p.id,
    p as never,
    variants.filter((v) => v.productId === p.id) as never,
    collections.filter((c) => (c.productIds as string[]).includes(p.id)).map((c) => c.id),
  );
  if (cards.public) pub[p.id] = cards.public;
  if (cards.staff) staff[p.id] = cards.staff;
}
void writer.set(db.doc("catalogIndex/public"), { cards: pub, updatedAt: now });
void writer.set(db.doc("catalogIndex/staff"), { cards: staff, updatedAt: now });
await writer.close();
console.log(`seeded ${all.length} docs and ${Object.keys(pub).length} public cards into ${PROJECT}`);
