import { inr, paise } from "../shared/money.js";
import type { Notice } from "./contract.js";

// Who is told what (docs/FIREBASE.md §6), ported word for word from supabase/migrations/20261030000400_notifications.sql
// (notify_order_change, notify_order_event, notify_repair_event, notify_personal_coupon, notify_feedback,
// notify_low_stock), 20261030000500_refunds.sql (settle_refund) and 20261030000600_notification_images.sql (photos).
// Pure: the triggers hand in the docs before and after a write and send what comes back. Staff are never told about
// their own action (`except`). Vectors: test-vectors/notifications.json.

type Stamp = Date | { toDate(): Date };
type By = "customer" | "staff" | "system";
type OrderEvent = { status: string; note?: string | null; by: By; byUid?: string | null };
type Order = {
  number: string; uid: string | null; status: string; paymentMethod: string; paymentStatus: string; totalPaise: number;
  items: { id: string; productName: string; unitPricePaise: number; imagePath?: string | null }[];
  address?: { city?: string | null } | null; events: OrderEvent[]; reservedUntil?: Stamp | null;
  courier?: string | null; trackingNumber?: string | null;
};
type RepairEvent = OrderEvent & { quoteStatus?: string | null; quotePaise?: number | null };
type Repair = {
  number: string; uid: string | null; deviceBrand: string; deviceModel: string; issue: string; description: string;
  preferredDate: string; slot: string; status: string; quote: { paise: number | null }; events: RepairEvent[];
};

// Copy helpers -------------------------------------------------------------------------------------------------------

const money = (p: number) => inr(paise(p));
/** One line, at most [n] characters (an ellipsis marks a cut): private.clip. */
export const clip = (s: string, n: number): string => {
  const v = Array.from(s.replace(/\s+/gu, " ").trim()); // code points, as Postgres counts them
  return v.length <= n ? v.join("") : `${v.slice(0, n - 1).join("")}…`;
};
const blank = (s: string | null | undefined): string | null => (s?.trim() ? s.trim() : null);
const ist = (d: Stamp) => new Date((d instanceof Date ? d : d.toDate()).getTime() + 330 * 60_000);
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** "3:05 pm" in IST (to_char FMHH12:MI am). */
const clock = (d: Stamp) => {
  const t = ist(d);
  const h = t.getUTCHours();
  return `${String(h % 12 || 12)}:${String(t.getUTCMinutes()).padStart(2, "0")} ${h < 12 ? "am" : "pm"}`;
};
/** "5 Dec" in IST. */
const dayMonth = (d: Stamp) => `${String(ist(d).getUTCDate())} ${MONTHS[ist(d).getUTCMonth()] ?? ""}`;

const ISSUE: Record<string, string> = {
  screen: "Screen", battery: "Battery", charging: "Charging port", camera: "Camera", audio: "Speaker or mic",
  water_damage: "Water damage", software: "Software",
};
const issueWords = (issue: string) => ISSUE[issue] ?? "Repair";
const SLOT: Record<string, string> = { morning: "10 am – 1 pm", afternoon: "1 pm – 5 pm", evening: "5 pm – 9 pm" };
/** "Tue 4 Nov, morning (10 am – 1 pm)". */
function repairWhen(b: Pick<Repair, "preferredDate" | "slot">): string {
  const d = new Date(`${b.preferredDate}T00:00:00Z`);
  const day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()] ?? "";
  return `${day} ${String(d.getUTCDate())} ${MONTHS[d.getUTCMonth()] ?? ""}, ${b.slot} (${SLOT[b.slot] ?? SLOT.evening ?? ""})`;
}

const byPrice = (o: Pick<Order, "items">) =>
  [...o.items].sort((a, b) => b.unitPricePaise - a.unitPricePaise || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
/** The order's priciest line with a photo (notification_image). */
export const orderImage = (o: Pick<Order, "items">): string | undefined => byPrice(o).find((i) => i.imagePath)?.imagePath ?? undefined;
/** "₹1,29,999 · Cash on delivery · Samsung Galaxy S25 + 1 more · Waidhan", for staff. */
function orderSummary(o: Order): string {
  const first = byPrice(o)[0]?.productName;
  const lines = first === undefined ? null : `${first}${o.items.length > 1 ? ` + ${String(o.items.length - 1)} more` : ""}`;
  return [money(o.totalPaise), o.paymentMethod === "cod" ? "Cash on delivery" : "Paid online", lines, o.address?.city]
    .filter((x) => x).join(" · ");
}
function trackingLine(o: Order): string | null {
  const courier = blank(o.courier), tracking = blank(o.trackingNumber);
  if (courier && tracking) return `${courier}, tracking ${tracking}.`;
  if (tracking) return `Tracking ${tracking}.`;
  return courier ? `With ${courier}.` : null;
}

function builder(link: string, staffLink: string, key: string, extra: Partial<Notice>, except?: string | null) {
  const out: Notice[] = [];
  const add = (recipient: string | null, kind: string, title: string, body: string) => {
    if (!recipient) return;
    const staff = recipient === "staff";
    out.push({ recipient, kind, title: clip(title, 80), body: clip(body, 300), link: staff ? staffLink : link, key, ...extra,
      ...(staff && except ? { except } : {}) });
  };
  return { out, add };
}

// Orders ------------------------------------------------------------------------------------------------------------

/** Everything one write of orders/{id} says: the payment, refund and tracking changes, then each new timeline event
 * (an event that comes with a customer notice of the same write only adds its note to it, as the SQL did). */
export function orderNotices(id: string, before: Order | null, o: Order): Notice[] {
  const fresh = o.events.slice(before?.events.length ?? 0);
  const actor = fresh.at(-1)?.byUid ?? null;
  const image = orderImage(o);
  const extra = { orderId: id, ...(image ? { imagePath: image } : {}) };
  const write = builder(`/orders/${id}`, `/admin/orders/${id}`, `p${String(o.events.length)}`, extra, actor);
  const { add } = write;
  const total = money(o.totalPaise);

  if (before && o.paymentStatus !== before.paymentStatus) {
    if (o.paymentStatus === "failed") {
      add(o.uid, "payment_failed", `Payment failed for ${o.number}`,
        `Your items are still held for you. Try paying again before ${o.reservedUntil ? clock(o.reservedUntil) : "the hold ends"}.`);
    } else if (o.paymentStatus === "paid" && o.paymentMethod === "online" && o.status === "cancelled") {
      add(o.uid, "order_late_payment", `We got your payment for ${o.number}`,
        `The order was already cancelled, so we’re refunding ${total} to your original payment method.`);
      add("staff", "staff_refund_needed", `Refund ${total} for ${o.number}`, "The payment arrived after the order was cancelled.");
    } else if (o.paymentStatus === "paid" && o.paymentMethod === "online") {
      add(o.uid, "payment_received", `Payment received for ${o.number}`, `${total} paid. Your order is confirmed.`);
      add("staff", "staff_order_paid", `Paid order ${o.number}`, orderSummary(o));
    } else if (o.paymentStatus === "refunded") {
      add(o.uid, "order_refunded", `Refund of ${total} for ${o.number}`,
        "It’s on its way to your original payment method. Banks usually take 5–7 working days to show it.");
    }
  } else if (before && o.status === before.status && ["packed", "shipped", "delivered"].includes(o.status) &&
    ((o.courier ?? null) !== (before.courier ?? null) || (o.trackingNumber ?? null) !== (before.trackingNumber ?? null))) {
    add(o.uid, "order_tracking", `Tracking updated for ${o.number}`, trackingLine(o) ?? "The courier details were removed.");
  }

  const told = write.out.find((n) => n.recipient === o.uid);
  if (told) {
    for (const e of fresh) {
      const note = blank(e.note);
      if (!note) continue;
      if (told.kind === "order_tracking" && !note.includes(o.trackingNumber ?? o.courier ?? "")) told.body = clip(`${told.body} ${note}`, 300);
      else if (told.kind === "order_refunded") told.body = clip(note, 300); // "Refunded in cash at the store"
    }
    return write.out;
  }

  const out = [...write.out];
  const first = o.events.length - fresh.length;
  fresh.forEach((e, n) => {
    const i = first + n;
    const prev = o.events[i - 1]?.status;
    const note = blank(e.note);
    const ev = builder(`/orders/${id}`, `/admin/orders/${id}`, String(i), extra, e.byUid);
    const say = ev.add;
    if (prev === undefined) {
      if (e.status === "pending_payment") {
        say(o.uid, "order_awaiting_payment", `Finish paying for ${o.number}`, `${total} to pay online. We hold your items for 15 minutes.`);
      } else {
        say(o.uid, "order_confirmed", `${o.number} is confirmed`, `${total}, cash on delivery. We’ll tell you when it’s packed.`);
        say("staff", "staff_new_order", `New order ${o.number}`, orderSummary(o));
      }
    } else if (e.status === prev) {
      if (note && e.by === "staff") say(o.uid, "order_update", `Update on ${o.number}`, note);
    } else if (e.status === "packed") {
      say(o.uid, "order_packed", `${o.number} is packed`, note ?? "It ships soon. We’ll tell you when it’s on the way.");
    } else if (e.status === "shipped") {
      say(o.uid, "order_shipped", `${o.number} is on its way`, [trackingLine(o) ?? "Out for delivery.", note].filter((x) => x).join(" "));
    } else if (e.status === "delivered") {
      say(o.uid, "order_delivered", `${o.number} is delivered`, "How was it? Tap to rate your order.");
    } else if (e.status === "cancelled" && e.by === "customer") {
      const paid = o.paymentStatus === "paid";
      say(o.uid, "order_cancelled", `You cancelled ${o.number}`, paid
        ? `A full refund of ${total} to your original payment method is on its way; banks usually take 5–7 working days.`
        : "Nothing was charged.");
      if (paid) say("staff", "staff_refund_needed", `Refund ${total} for ${o.number}`, "The customer cancelled a paid order. Its stock is back.");
      else if (prev !== "pending_payment") say("staff", "staff_order_cancelled", `${o.number} cancelled by the customer`, `Stock is back: ${orderSummary(o)}`);
    } else if (e.status === "cancelled" && e.by === "system") {
      say(o.uid, "order_expired", `${o.number} was cancelled`, "The payment didn’t come through in 15 minutes. Order again any time.");
    } else if (e.status === "cancelled") {
      say(o.uid, "order_cancelled", `${o.number} was cancelled by the shop`, note ?? "Cancelled by the store.");
      if (o.paymentStatus === "paid") {
        say("staff", "staff_refund_needed", `Refund ${total} for ${o.number}`, "Staff cancelled a paid order. Refund it, then mark it refunded.");
      }
    }
    out.push(...ev.out);
  });
  return out;
}

/** orders/{id}/refunds/{refundId} settled: staff hear of a failure; the customer of a partial refund (a full one moves
 * the order to refunded, which says it). */
export function refundNotices(orderId: string, refundId: string, before: { status: string } | null,
  r: { status: string; amountPaise: number; fullRefund: boolean; itemIds?: string[]; failure?: string | null }, o: Order): Notice[] {
  if (before?.status !== "pending" || r.status === "pending") return [];
  const image = orderImage(o);
  const { out, add } = builder(`/orders/${orderId}`, `/admin/orders/${orderId}`, `r${refundId}`, { orderId, ...(image ? { imagePath: image } : {}) });
  const amount = money(r.amountPaise);
  if (r.status === "failed") {
    add("staff", "staff_refund_failed", `Refund failed for ${o.number}`,
      `${amount}: ${r.failure ?? "PhonePe couldn’t complete it."} Try again, or refund it another way and tap Mark refunded.`);
  } else if (r.status === "processed" && o.paymentStatus !== "refunded") {
    const names = byPrice(o).filter((i) => r.itemIds?.includes(i.id)).map((i) => i.productName).join(", ");
    add(o.uid, "order_refunded", `Refund of ${amount} for ${o.number}`,
      `Refund of ${amount}${r.fullRefund || !names ? "" : ` for ${names}`} issued to your original payment method. Banks usually take 5–7 working days to show it.`);
  }
  return out;
}

// Repairs -----------------------------------------------------------------------------------------------------------

/** Each new event of repairs/{id}: booked, each step, quotes and the answers, cancels, staff notes. */
export function repairNotices(id: string, before: Repair | null, b: Repair): Notice[] {
  const out: Notice[] = [];
  const what = `${b.deviceModel} ${issueWords(b.issue).toLowerCase()}`; // "Galaxy A56 screen"
  const from = before?.events.length ?? 0;
  b.events.slice(from).forEach((e, n) => {
    const i = from + n;
    const prev = b.events[i - 1]?.status;
    const note = blank(e.note);
    const byCustomer = e.by === "customer";
    const amount = e.quotePaise == null ? "" : money(e.quotePaise);
    const { out: o, add } = builder(`/repairs/${id}`, `/admin/repairs/${id}`, String(i), { repairId: id }, e.byUid);
    if (e.quoteStatus === "pending") {
      add(b.uid, "repair_quote", b.status === "in_progress"
        ? `New ${amount} quote for your ${what}: approve to continue`
        : `${amount} quote for your ${what}: approve to start`, note ?? "Work starts only after you approve this price.");
    } else if (e.quoteStatus === "approved" && byCustomer) {
      add("staff", "staff_quote_approved", `Quote approved for ${b.number}`, `${amount} for the ${b.deviceBrand} ${what}. You can start the repair.`);
    } else if (e.quoteStatus === "approved") {
      add(b.uid, "repair_quote_agreed", `${amount} agreed for your ${what}`, note ?? "Agreed with the store.");
    } else if (e.quoteStatus === "declined") {
      add("staff", "staff_quote_declined", `Quote declined for ${b.number}`,
        `${amount} for the ${b.deviceBrand} ${what}. ${note ? `Reason: “${note}”.` : "No reason given."} Quote again or cancel it.`);
    } else if (prev === undefined) {
      add(b.uid, "repair_booked", `Repair booked for your ${b.deviceModel}`,
        [`${issueWords(b.issue)} · ${repairWhen(b)}.`, e.status === "requested" ? "We’ll confirm the time soon." : null].filter((x) => x).join(" "));
      add("staff", "staff_new_repair", `New repair ${b.number}: ${b.deviceBrand} ${b.deviceModel}`,
        [issueWords(b.issue), repairWhen(b), blank(b.description)].filter((x) => x).join(" · "));
    } else if (e.status === prev) {
      if (note && e.by === "staff") add(b.uid, "repair_update", `Update on your ${b.deviceModel} repair`, note);
    } else if (e.status === "confirmed") {
      add(b.uid, "repair_confirmed", `Repair confirmed for ${repairWhen(b)}`, [`Bring your ${b.deviceModel} to the store then.`, note].filter((x) => x).join(" "));
    } else if (e.status === "in_progress") {
      add(b.uid, "repair_started", `Work has started on your ${b.deviceModel}`, note ?? "We’ll tell you when it’s ready.");
    } else if (e.status === "ready") {
      const pay = b.quote.paise == null ? null : `Pay ${money(b.quote.paise)} when you collect it.`;
      add(b.uid, "repair_ready", `Your ${b.deviceModel} is ready for pickup`, [pay, note].filter((x) => x).join(" ") || "Collect it from the store.");
    } else if (e.status === "completed") {
      add(b.uid, "repair_completed", `Your ${b.deviceModel} repair is complete`, "How did we do? Tap to rate the repair.");
    } else if (e.status === "cancelled" && byCustomer) {
      add("staff", "staff_repair_cancelled", `${b.number} cancelled by the customer`,
        [`${b.deviceBrand} ${b.deviceModel}`, issueWords(b.issue), repairWhen(b)].join(" · "));
    } else if (e.status === "cancelled") {
      add(b.uid, "repair_cancelled", `Your ${b.deviceModel} repair was cancelled`, note ?? "Cancelled by the store.");
    }
    out.push(...o);
  });
  return out;
}

// Coupons, feedback, stock --------------------------------------------------------------------------------------------

/** users/{uid}/coupons/{id} created: a referral gift or reward, or a coupon staff made for this customer. */
export function couponNotice(id: string, uid: string, c: { code: string | null; kind: string; value: number; title: string;
  minSubtotalPaise?: number; endsAt?: Stamp | null }): Notice[] {
  const code = c.code ?? "";
  const value = c.kind === "flat" ? money(c.value) : c.kind === "percent" ? `${String(c.value)}%` : "free delivery";
  const reward = code.startsWith("REWARD"), welcome = code.startsWith("FRIEND");
  const { out, add } = builder(`/offers/${id}`, `/offers/${id}`, "0", {});
  add(uid, reward ? "referral_reward" : welcome ? "referral_welcome" : "coupon",
    reward ? `You earned a ${value} coupon for referring a friend` : welcome ? `Your welcome gift: ${value} off your first order` : `A coupon just for you: ${c.title}`,
    `Use code ${code}${(c.minSubtotalPaise ?? 0) > 0 ? ` on an order of ${money(c.minSubtotalPaise ?? 0)} or more` : ""}${c.endsAt ? ` by ${dayMonth(c.endsAt)}` : ""}.`);
  return out;
}

/** A new rating or comment, or a re-rating; staff changing status or their note is not news. [about]: "order SM100001",
 * "repair RP100001" or the product's name. */
export function feedbackNotices(id: string, before: { rating?: number | null; message: string } | null,
  f: { uid: string | null; kind: string; rating?: number | null; message: string }, about: string | null, imagePath?: string): Notice[] {
  if (before && (before.rating ?? null) === (f.rating ?? null) && before.message === f.message) return [];
  const r = f.rating ?? null;
  const stars = r === null ? "" : `${String(r)} ${r === 1 ? "star" : "stars"}`;
  const low = r !== null && r <= 2;
  const { out, add } = builder("", `/admin/feedback/${id}`, "0", imagePath ? { imagePath } : {}, f.uid);
  add("staff", low ? "staff_feedback_low" : "staff_feedback",
    low ? `Low rating: ${stars}${about ? ` for ${about}` : ""}`
      : r !== null ? `New rating: ${stars}${about ? ` for ${about}` : ""}`
        : f.kind === "bug" ? "New problem report" : `New feedback${about ? ` on ${about}` : ""}`,
    blank(f.message) ?? "No comment.");
  return out;
}

type Variant = { productId: string; productName: string; productActive: boolean; isActive: boolean; name: string; sku: string;
  stock: number; lastStockChange: string; restockSeq?: number };

/** A sale takes a live variant to 3 or fewer, or to none: once per crossing. Staff edits aren't sales. */
export function stockNotices(before: Variant, v: Variant, key: string, imagePath?: string): Notice[] {
  if (v.lastStockChange !== "order" || !v.isActive || !v.productActive) return [];
  if (!(v.stock < before.stock && v.stock <= 3 && (before.stock > 3 || v.stock === 0))) return [];
  const { out, add } = builder("", `/admin/products/${v.productId}`, `s${key}`, imagePath ? { imagePath } : {});
  if (v.stock === 0) add("staff", "staff_out_of_stock", `Out of stock: ${v.productName}`, `${v.name} (${v.sku}) just sold out. Restock it or hide it.`);
  else add("staff", "staff_low_stock", `Low stock: ${v.productName}`, `${v.name} (${v.sku}): only ${String(v.stock)} left.`);
  return out;
}

/** The variant came back (0 → > 0) and can be bought: what each waiting customer gets (docs/FIREBASE.md §6). */
export function backInStock(variantId: string, before: Pick<Variant, "stock">, v: Variant): Omit<Notice, "recipient"> | null {
  if (!(before.stock <= 0 && v.stock > 0 && v.isActive && v.productActive)) return null;
  return {
    kind: "back_in_stock", key: `bis_${variantId}_${String(v.restockSeq ?? 0)}`, title: clip(`Back in stock: ${v.productName}`, 80),
    body: clip(`${v.name} is available again. Tap to buy before it sells out.`, 300), link: `/product/${v.productId}?variant=${variantId}`,
  };
}
