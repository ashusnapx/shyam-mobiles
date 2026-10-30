import { HttpError, json, UUID } from "../_shared/http.ts";
import { razorpay, RazorpayError } from "../_shared/razorpay.ts";
import { callRpc, type Rpc } from "../_shared/supabase.ts";

export type Link = {
  id: string; order_id: string | null; amount_paise: number; description: string; customer_name: string | null;
  customer_phone: string; status: string; short_url: string | null; expires_at: string; razorpay_link_id?: string | null;
};

export interface LinkStore {
  rpc: Rpc;
  get(id: string): Promise<Link | null>;
  saved(id: string, razorpayLinkId: string, shortUrl: string): Promise<void>;
  remove(id: string): Promise<void>; // a row Razorpay never made a link for
}

const CODES: Record<string, [number, string]> = {
  FORBIDDEN: [403, "This is for Shyam Mobiles staff."],
  NOT_FOUND: [404, "Order not found."],
  BAD_REQUEST: [400, "Add the amount, the customer's mobile number and what it's for."],
  LINK_NOT_ALLOWED: [409, "This order is already paid or cancelled."],
};
const PHONE = /^\+91[6-9][0-9]{9}$/;

const gateway = (e: unknown, what: string) =>
  e instanceof RazorpayError && e.gatewayStatus === 400 && e.description
    ? new HttpError(409, "LINK_REFUSED", `Razorpay refused to ${what}: ${e.description}`)
    : e;

// {order_id} | {amount_paise, phone, name?, description} -> the link; {cancel: link_id} -> {status}. Staff only.
export async function paymentLink(body: Record<string, unknown>, staffId: string, store: LinkStore): Promise<Response> {
  if (body.cancel !== undefined) return await cancel(body.cancel, store);
  const { order_id = null, amount_paise = null, phone = null, name = null, description = null } = body;
  const forOrder = typeof order_id === "string" && UUID.test(order_id) && amount_paise === null && phone === null &&
    name === null && description === null;
  const custom = order_id === null && Number.isInteger(amount_paise) && (amount_paise as number) >= 100 &&
    (amount_paise as number) <= 500000000 && typeof phone === "string" && PHONE.test(phone) &&
    (name === null || (typeof name === "string" && name.length <= 60)) &&
    typeof description === "string" && description.trim().length > 0 && description.length <= 200;
  if (!forOrder && !custom) {
    throw new HttpError(400, "BAD_REQUEST", "Send order_id, or amount_paise (₹1 to ₹50 lakh), phone (+91…) and description.");
  }

  const link = await callRpc<Link & { reused: boolean }>(store.rpc, "admin_new_payment_link", {
    p_staff: staffId, p_order_id: order_id, p_amount_paise: amount_paise, p_phone: phone, p_name: name, p_description: description,
  }, CODES);
  if (link.reused) {
    if (!link.short_url) throw new HttpError(409, "LINK_IN_PROGRESS", "That link is still being made. Try again in a moment.");
    return json(link);
  }

  let made: { id: string; short_url: string };
  try {
    made = await razorpay("/payment_links", {
      amount: link.amount_paise,
      currency: "INR",
      description: link.description,
      customer: { contact: link.customer_phone, ...(link.customer_name ? { name: link.customer_name } : {}) },
      notify: { sms: false, email: false }, // staff send it on WhatsApp
      reminder_enable: false,
      expire_by: Math.floor(Date.parse(link.expires_at) / 1000),
      reference_id: link.id, // unique per link, so a second link for the same order gets its own
      // not `order_id`: payment.captured must leave link payments to payment_link.paid
      notes: { link_id: link.id, ...(link.order_id ? { shop_order_id: link.order_id } : {}) },
    });
  } catch (e) {
    await store.remove(link.id);
    throw gateway(e, "make the link");
  }
  await store.saved(link.id, made.id, made.short_url);
  return json({ ...link, short_url: made.short_url, razorpay_link_id: made.id });
}

async function cancel(id: unknown, store: LinkStore): Promise<Response> {
  if (typeof id !== "string" || !UUID.test(id)) throw new HttpError(400, "BAD_REQUEST", "cancel is a link id.");
  const link = await store.get(id);
  if (!link) throw new HttpError(404, "NOT_FOUND", "Link not found.");
  if (link.status !== "created" || !link.razorpay_link_id) {
    throw new HttpError(409, "LINK_NOT_OPEN", `This link is ${link.status} already.`);
  }
  try {
    await razorpay(`/payment_links/${encodeURIComponent(link.razorpay_link_id)}/cancel`, {});
  } catch (e) {
    throw gateway(e, "cancel it");
  }
  await callRpc(store.rpc, "close_payment_link", { p_razorpay_link_id: link.razorpay_link_id, p_status: "cancelled" }, CODES);
  return json({ id, status: "cancelled" });
}
