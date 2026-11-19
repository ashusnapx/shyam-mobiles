import { Timestamp } from "firebase-admin/firestore";
import { readPublicCards } from "../catalog/repository.js";
import { DAY_MS } from "../model/retention.js";
import { db } from "../shared/db.js";
import { log } from "../shared/log.js";
import { cartNudge, capped, hasFittingAccessory, type Nudge, optedIn, priceDropNudge, protectDue, protectNudge, deliveredAtMs, quietHours } from "./nudges.js";

// Growth (docs/GROWTH.md §2d, e): the hourly run's reads and writes. Every send goes through offer(), which checks
// the switch, the 3-day cap and the notification's own id in one transaction, so a retry or an overlapping run never
// sends twice and two kinds never both slip under the cap.

const TTL_MS = 90 * DAY_MS; // model/notifications.ts retention
const CAP_TTL_MS = 4 * DAY_MS; // model/notifications.ts marketingCaps
/** shortcut: one page per kind per hour is every candidate at shop volume; page past ~200 carts or orders a day. */
const PAGE = 200;

/** Writes [n] to users/{uid}/notifications (the push trigger sends it) unless the customer opted out, was sent one
 * in the last 3 days, or already has this one. True when sent. */
export async function offer(uid: string, n: Nudge, now: Date): Promise<boolean> {
  const { id, ...doc } = n;
  const user = db().doc(`users/${uid}`), cap = db().doc(`marketingCaps/${uid}`), note = db().doc(`users/${uid}/notifications/${id}`);
  return db().runTransaction(async (tx) => {
    const [u, c, existing] = await tx.getAll(user, cap, note);
    if (!u?.exists || !optedIn(u.get("prefs")) || existing?.exists) return false;
    if (capped((c?.get("lastAt") as Timestamp | undefined)?.toMillis(), now.getTime())) return false;
    const at = Timestamp.fromDate(now);
    tx.create(note, { ...doc, readAt: null, createdAt: at, expireAt: Timestamp.fromMillis(now.getTime() + TTL_MS) });
    tx.set(cap, { lastAt: at, expireAt: Timestamp.fromMillis(now.getTime() + CAP_TTL_MS) });
    return true;
  });
}

/** Carts last changed 24 to 48 hours ago that still hold something in stock. */
async function cartNudges(now: Date): Promise<number> {
  const carts = await db().collection("carts")
    .where("updatedAt", ">=", Timestamp.fromMillis(now.getTime() - 2 * DAY_MS))
    .where("updatedAt", "<=", Timestamp.fromMillis(now.getTime() - DAY_MS)).limit(PAGE).get();
  let sent = 0;
  for (const cart of carts.docs) {
    const ids = Object.keys((cart.get("lines") ?? {}) as Record<string, unknown>).slice(0, 20);
    if (ids.length === 0) continue;
    const variants = await db().getAll(...ids.map((v) => db().doc(`variants/${v}`)));
    const names = variants.filter((v) => v.exists && v.get("isActive") === true && v.get("productActive") === true && Number(v.get("stock")) > 0)
      .map((v) => String(v.get("productName")));
    const n = cartNudge((cart.get("updatedAt") as Timestamp).toMillis(), names);
    if (n && await offer(cart.id, n, now)) sent++;
  }
  return sent;
}

/** Drops in the last 48 hours whose price still holds: everyone with that product on their wishlist. */
async function dropNudges(now: Date): Promise<number> {
  const drops = await db().collection("priceDrops").where("at", ">=", Timestamp.fromMillis(now.getTime() - 2 * DAY_MS)).limit(50).get();
  let sent = 0;
  for (const d of drops.docs) {
    const drop = d.data() as { variantId: string; productId: string; productName: string; fromPaise: number; toPaise: number };
    const v = await db().doc(`variants/${drop.variantId}`).get();
    if (v.get("pricePaise") !== drop.toPaise || v.get("isActive") !== true || v.get("productActive") !== true || !(Number(v.get("stock")) > 0)) continue;
    // orderBy waitVariant: the existing (productId, waitVariant) collection-group index; every entry holds the field
    const fans = await db().collectionGroup("wishlist").where("productId", "==", drop.productId).orderBy("waitVariant").limit(500).get();
    for (const w of fans.docs) {
      const uid = w.ref.parent.parent?.id;
      if (uid && await offer(uid, priceDropNudge(drop), now)) sent++;
    }
  }
  return sent;
}

/** Phones delivered 2 to 3 days ago, when something in stock fits them. */
async function protectNudges(now: Date): Promise<number> {
  const orders = await db().collection("orders").where("status", "==", "delivered")
    .where("updatedAt", ">=", Timestamp.fromMillis(now.getTime() - 3 * DAY_MS)).limit(PAGE).get();
  const due = orders.docs.filter((o) => typeof o.get("uid") === "string" && protectDue(deliveredAtMs(o.get("events")), now.getTime()));
  if (due.length === 0) return 0;
  const cards = (await readPublicCards()) as Record<string, { ft?: unknown; i?: unknown }>;
  let sent = 0;
  for (const o of due) {
    const items = (o.get("items") ?? []) as { productId?: string; imagePath?: string }[];
    const products = await db().getAll(...items.filter((i) => i.productId).map((i) => db().doc(`products/${i.productId ?? ""}`)));
    const phone = products.find((p) => p.get("categoryKind") === "phone");
    if (!phone || !hasFittingAccessory(cards, { name: String(phone.get("name")), brandName: String(phone.get("brandName")) })) continue;
    const image = items.find((i) => i.productId === phone.id)?.imagePath;
    if (await offer(o.get("uid") as string, protectNudge(o.id, String(phone.get("name")), image), now)) sent++;
  }
  return sent;
}

/** The hourly run: nothing in quiet hours; otherwise each kind, one failing kind not stopping the others. */
export async function sendNudges(now = new Date()): Promise<void> {
  if (quietHours(now)) return;
  const counts: Record<string, number> = {};
  for (const [kind, run] of [["cart", cartNudges], ["drop", dropNudges], ["protect", protectNudges]] as const) {
    try {
      counts[kind] = await run(now);
    } catch (e) {
      log.error("nudges failed", { kind, error: e });
    }
  }
  log.info("nudges sent", counts);
}

/** A variant got cheaper: remembered for the next runs (priceDrops/{variantId}_{toPaise}, kept 7 days). */
export async function recordPriceDrop(variantId: string, v: { productId: string; productName: string }, fromPaise: number, toPaise: number): Promise<void> {
  const at = Timestamp.now();
  await db().doc(`priceDrops/${variantId}_${toPaise}`).set({
    variantId, productId: v.productId, productName: v.productName, fromPaise, toPaise, at,
    expireAt: Timestamp.fromMillis(at.toMillis() + 7 * DAY_MS),
  });
}
