import { FieldPath, type QueryDocumentSnapshot, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onDocumentCreated, onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import type { ProductDoc } from "../model/catalog.js";
import type { NotificationDoc } from "../model/notifications.js";
import { DAY_MS } from "../model/retention.js";
import { db } from "../shared/db.js";
import { log } from "../shared/log.js";
import { BACKGROUND } from "../shared/options.js";
import { type Notice, pushData } from "./contract.js";
import { backInStock, couponNotice, feedbackNotices, orderImage, orderNotices, refundNotices, repairNotices, stockNotices } from "./notices.js";

// Owner: engineer D. Firestore triggers that turn writes into notifications (notices.ts decides), the push to phones,
// and back-in-stock alerts (docs/FIREBASE.md D8, §6). Triggers run at least once: notification ids are deterministic
// and written in one batch of create()s, so a retry finds them all there and writes nothing twice.

const TTL_MS = 90 * DAY_MS; // model/notifications.ts retention
const retried = { ...BACKGROUND, retry: true };
type Data = Record<string, unknown>;

const isAlreadyThere = (e: unknown) => (e as { code?: unknown }).code === 6; // gRPC ALREADY_EXISTS

async function staffUids(): Promise<string[]> {
  const snap = await db().collection("users").where("role", "in", ["owner", "staff"]).limit(50).get();
  return snap.docs.map((d) => d.id);
}

/** Writes [notices] as users/{uid}/notifications/{sourceId}_{key}_{kind}_{uid}, "staff" fanned out to every staff
 * member but the one who acted. */
export async function deliver(sourceId: string, notices: Notice[]): Promise<void> {
  if (notices.length === 0) return;
  const staff = notices.some((n) => n.recipient === "staff") ? await staffUids() : [];
  const at = Timestamp.now();
  const batch = db().batch();
  for (const { recipient, except, key, ...n } of notices) {
    for (const uid of recipient === "staff" ? staff.filter((u) => u !== except) : [recipient]) {
      const doc: Omit<NotificationDoc, "createdAt" | "expireAt"> & Data = { ...n, readAt: null };
      batch.create(db().doc(`users/${uid}/notifications/${sourceId}_${key}_${n.kind}_${uid}`),
        { ...doc, createdAt: at, expireAt: Timestamp.fromMillis(at.toMillis() + TTL_MS) });
    }
  }
  try {
    await batch.commit();
  } catch (e) {
    if (!isAlreadyThere(e)) throw e; // the batch is atomic: one already there means an earlier try wrote them all
  }
}

const cover = (p: Partial<ProductDoc> | undefined) => [...(p?.images ?? [])].sort((a, b) => a.sort - b.sort)[0]?.path;
const product = async (id: unknown) => (typeof id === "string" ? (await db().doc(`products/${id}`).get()).data() as ProductDoc | undefined : undefined);

export const notifyOrder = onDocumentWritten({ document: "orders/{id}", ...retried }, async (event) => {
  const after = event.data?.after.data();
  if (!after) return;
  await deliver(event.params.id, orderNotices(event.params.id, (event.data?.before.data() ?? null) as never, after as never));
});

export const notifyRefund = onDocumentWritten({ document: "orders/{orderId}/refunds/{refundId}", ...retried }, async (event) => {
  const after = event.data?.after.data();
  if (!after) return;
  const order = (await db().doc(`orders/${event.params.orderId}`).get()).data();
  if (!order) return;
  await deliver(event.params.orderId, refundNotices(event.params.orderId, event.params.refundId,
    (event.data?.before.data() ?? null) as never, after as never, order as never));
});

export const notifyRepair = onDocumentWritten({ document: "repairs/{id}", ...retried }, async (event) => {
  const after = event.data?.after.data();
  if (!after) return;
  await deliver(event.params.id, repairNotices(event.params.id, (event.data?.before.data() ?? null) as never, after as never));
});

export const notifyFeedback = onDocumentWritten({ document: "feedback/{id}", ...retried }, async (event) => {
  const f = event.data?.after.data();
  if (!f) return;
  const [order, repair, item] = await Promise.all([
    typeof f.orderId === "string" ? db().doc(`orders/${f.orderId}`).get() : null,
    typeof f.repairId === "string" ? db().doc(`repairs/${f.repairId}`).get() : null,
    product(f.productId),
  ]);
  const about = f.kind === "order" ? (order?.exists ? `order ${String(order.get("number"))}` : null)
    : f.kind === "repair" ? (repair?.exists ? `repair ${String(repair.get("number"))}` : null)
      : f.kind === "product" ? (item?.name ?? null) : null;
  const image = (order?.exists ? orderImage(order.data() as never) : undefined) ?? cover(item);
  // the feedback's own write time: a re-rating is a new event, a retry is not
  const key = String((event.data?.after.updateTime ?? Timestamp.now()).toMillis());
  const notices = feedbackNotices(event.params.id, (event.data?.before.data() ?? null) as never, f as never, about, image);
  await deliver(event.params.id, notices.map((n) => ({ ...n, key })));
});

export const notifyCoupon = onDocumentCreated({ document: "users/{uid}/coupons/{id}", ...retried }, async (event) => {
  const c = event.data?.data();
  if (c) await deliver(event.params.id, couponNotice(event.params.id, event.params.uid, c as never));
});

/** Low stock for staff, and back-in-stock alerts for the customers waiting on this variant. */
export const notifyStock = onDocumentUpdated({ document: "variants/{id}", ...retried }, async (event) => {
  const before = event.data?.before.data(), after = event.data?.after.data();
  if (!before || !after) return;
  const id = event.params.id;
  const low = stockNotices(before as never, after as never, event.id);
  const back = backInStock(id, before as never, after as never);
  if (low.length === 0 && !back) return;
  const image = cover(await product(after.productId));
  await deliver(id, low.map((n) => ({ ...n, ...(image ? { imagePath: image } : {}) })));
  if (back) await alertWaiting(id, after.productId as string, { ...back, ...(image ? { imagePath: image } : {}) });
});

/** Every customer whose wishlist waits on this variant (or any of the product's), 200 at a time: one notification
 * per restock (its id carries restockSeq), the mark cleared in the same batch. prefs.backInStock false: skipped, and
 * the mark stays for when they turn alerts back on. */
async function alertWaiting(variantId: string, productId: string, notice: Omit<Notice, "recipient">): Promise<void> {
  const { key, ...n } = notice;
  const query = db().collectionGroup("wishlist").where("productId", "==", productId).where("waitVariant", "in", [variantId, "*"])
    .orderBy(FieldPath.documentId()).limit(200);
  let last: QueryDocumentSnapshot | undefined;
  for (;;) {
    const page = await (last ? query.startAfter(last) : query).get();
    if (page.empty) return;
    last = page.docs.at(-1);
    const users = await db().getAll(...page.docs.map((d) => d.ref.parent.parent ?? d.ref));
    const at = Timestamp.now();
    const batch = db().batch();
    page.docs.forEach((w, i) => {
      const user = users[i];
      if (!user?.exists || user.get("prefs.backInStock") === false) return;
      batch.create(db().doc(`users/${user.id}/notifications/${key}`),
        { ...n, readAt: null, createdAt: at, expireAt: Timestamp.fromMillis(at.toMillis() + TTL_MS) });
      batch.update(w.ref, { waitVariant: null });
    });
    try {
      await batch.commit();
    } catch (e) {
      if (!isAlreadyThere(e)) throw e;
    }
  }
}

/** Each new notification to the user's phones: data-only, high priority, today's send-push keys, so
 * app/lib/core/push.dart draws it as before. Not retried: the in-app copy is the record. */
export const pushNotification = onDocumentCreated({ document: "users/{uid}/notifications/{id}", ...BACKGROUND, retry: false }, async (event) => {
  const n = event.data?.data() as NotificationDoc | undefined;
  if (!n) return;
  const devices = await db().collection("devices").where("uid", "==", event.params.uid).limit(10).get();
  if (devices.empty) return;
  const data = pushData.parse(Object.fromEntries(Object.entries({
    id: event.params.id, kind: n.kind, title: n.title, body: n.body, link: n.link, image_path: n.imagePath,
  }).filter(([, v]) => typeof v === "string" && v !== "")));
  try {
    const res = await getMessaging().sendEach(devices.docs.map((d) => ({ token: d.id, data, android: { priority: "high" as const } })));
    const gone = devices.docs.filter((_, i) => res.responses[i]?.error?.code === "messaging/registration-token-not-registered");
    await Promise.all(gone.map((d) => d.ref.delete())); // that install is gone
    if (res.failureCount > gone.length) log.warn("push failed", { failed: res.failureCount - gone.length });
  } catch (e) {
    log.error("push failed", { error: e });
  }
});
