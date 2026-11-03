// Cut-over step 3 (docs/FIREBASE.md §7): copies every photo the catalogue points at (products' images, banners'
// imagePath, settings/store storePhotos, each with its @thumb.webp when there is one) from the public Supabase bucket
// to Storage under the same keys (product-images/<key>). Idempotent: a key already there with the same size is skipped.
//
//   SOURCE=https://<ref>.supabase.co/storage/v1/object/public/product-images node seed/copy-photos.ts
//
// Emulator by default (FIRESTORE_EMULATOR_HOST + FIREBASE_STORAGE_EMULATOR_HOST, a demo- project). The real project
// needs --live and is run by the owner at cut-over only, never by an engineer or CI.
import { createRequire } from "node:module";

const require = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const PROJECT = process.env.GCLOUD_PROJECT ?? "demo-shyam-mobiles";
const live = process.argv.includes("--live");
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST) && PROJECT.startsWith("demo-");
const source = process.env.SOURCE?.replace(/\/+$/, "");
if (!source?.startsWith("http") || (!emulated && !live) || (emulated && live)) {
  console.error("Set SOURCE to the public bucket URL. Without --live this only writes to a demo- project's emulators.");
  process.exit(1);
}

const app = initializeApp({ projectId: PROJECT, storageBucket: process.env.STORAGE_BUCKET ?? `${PROJECT}.appspot.com` });
const db = getFirestore(app);
const bucket = getStorage(app).bucket();
const KEY = /^[A-Za-z0-9_-]{1,80}\/[A-Za-z0-9_@-]{1,80}\.(webp|jpe?g|png)$/; // test-vectors/input.json imagePath
const TYPES = new Set(["image/webp", "image/jpeg", "image/png"]);

const keys = new Set<string>();
for (const d of (await db.collection("products").get()).docs) for (const i of d.get("images") ?? []) keys.add(i.path);
for (const d of (await db.collection("banners").get()).docs) if (d.get("imagePath")) keys.add(d.get("imagePath"));
for (const p of (await db.doc("settings/store").get()).get("storePhotos") ?? []) keys.add(p);
const wanted = [...keys].flatMap((k) => [{ key: k, thumb: false }, ...(k.endsWith(".webp") ? [{ key: k.replace(/\.webp$/, "@thumb.webp"), thumb: true }] : [])]);

const n = { copied: 0, skipped: 0, missing: 0, refused: 0 };
for (const { key, thumb } of wanted) {
  if (!KEY.test(key)) { n.refused++; console.error(`refused key ${key}`); continue; }
  const res = await fetch(`${source}/${key}`);
  if (res.status === 404 || res.status === 400) { n.missing++; if (!thumb) console.error(`missing ${key}`); continue; } // older uploads have no thumb
  if (!res.ok) throw new Error(`${res.status} for ${key}`);
  const type = (res.headers.get("content-type") ?? "").split(";")[0]!.trim();
  const body = Buffer.from(await res.arrayBuffer());
  if (!TYPES.has(type) || body.length > 1_048_576) { n.refused++; console.error(`refused ${key}: ${type}, ${body.length} bytes`); continue; }
  const file = bucket.file(`product-images/${key}`);
  const [exists] = await file.exists();
  if (exists && Number((await file.getMetadata())[0].size) === body.length) { n.skipped++; continue; }
  await file.save(body, { contentType: type, metadata: { cacheControl: "public, max-age=31536000" } });
  n.copied++;
}
console.log(JSON.stringify(n));
