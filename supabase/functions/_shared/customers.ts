import { razorpay } from "./razorpay.ts";

// Saved cards: one Razorpay customer per account (razorpay_customers), passed to Checkout as customer_id.
export interface CustomerStore {
  find(userId: string): Promise<string | null>;
  /** The account's verified phone (E.164, with or without +), email and profile name. */
  who(userId: string): Promise<{ phone?: string | null; email?: string | null; name?: string | null }>;
  /** Stores it unless the account already has one; returns the account's customer id (null: it belongs to another). */
  save(userId: string, customerId: string): Promise<string | null>;
}

// Razorpay's own rule for a customer name (3–50 characters, Latin letters); anything else is simply left out.
const NAME = /^[A-Za-z0-9.()][A-Za-z0-9 '._()@/-]{1,48}[A-Za-z0-9.)]$/;

// The account's Razorpay customer, made on first use. One identifier only (the phone, else the email), and
// fail_existing "0" hands back the customer Razorpay already has for it. Never throws: without one, Checkout just
// shows no saved cards.
export async function customerFor(store: CustomerStore, userId: string): Promise<string | null> {
  try {
    const known = await store.find(userId);
    if (known) return known;
    const who = await store.who(userId);
    const phone = who.phone ? `+${who.phone.replace(/^\+/, "")}` : null;
    if (!phone && !who.email) return null;
    const name = who.name?.trim();
    const made = await razorpay<{ id: string }>("/customers", {
      ...(name && NAME.test(name) ? { name } : {}),
      ...(phone ? { contact: phone } : { email: who.email }),
      fail_existing: "0",
    });
    return await store.save(userId, made.id);
  } catch (e) {
    console.error("razorpay customer:", e);
    return null;
  }
}

// Account deletion: delete the saved cards Razorpay holds for this customer (Razorpay can't delete a customer).
// Best effort: a failure is logged and the account is still deleted.
export async function forgetCustomer(customerId: string): Promise<void> {
  try {
    const id = encodeURIComponent(customerId);
    const tokens = await razorpay<{ items?: { id: string }[] }>(`/customers/${id}/tokens`);
    for (const t of tokens.items ?? []) {
      await razorpay(`/customers/${id}/tokens/${encodeURIComponent(t.id)}`, undefined, { method: "DELETE" });
    }
  } catch (e) {
    console.error("razorpay forget customer:", e);
  }
}
