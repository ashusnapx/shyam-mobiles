import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/http.ts";
import { fakeFetch, ok, refused } from "../_shared/fake_fetch.ts";
import { type Link, type LinkStore, paymentLink } from "./handler.ts";

const ORDER = "0b8f5a3e-1111-4222-8333-944445555666";
const LINK = "0b8f5a3e-1111-4222-8333-944445555777";
const STAFF = "0b8f5a3e-1111-4222-8333-944445555999";
const row: Link = {
  id: LINK, order_id: ORDER, amount_paise: 44900, description: "Shyam Mobiles order SM100001", customer_name: "Asha Devi",
  customer_phone: "+919876543210", status: "created", short_url: null, expires_at: "2026-11-02T10:00:00.000Z",
};

function fakeStore(link: Partial<Link> & { reused?: boolean } = {}) {
  const log: unknown[][] = [];
  const store: LinkStore = {
    async rpc(fn, args) {
      log.push([fn, args]);
      return { data: { ...row, reused: false, ...link }, error: null };
    },
    async get() {
      return { ...row, ...link };
    },
    async saved(...args) {
      log.push(["saved", ...args]);
    },
    async remove(id) {
      log.push(["remove", id]);
    },
  };
  return { store, log };
}

async function status(p: Promise<unknown>) {
  const e = await assertRejects(() => p, HttpError);
  return [e.status, e.code, e.message];
}

Deno.test("bad bodies -> 400, nothing made", async () => {
  const { store, log } = fakeStore();
  for (const body of [{}, { order_id: "x" }, { amount_paise: 99, phone: "+919876543210", description: "x" },
    { amount_paise: 1000.5, phone: "+919876543210", description: "x" }, { amount_paise: 1000, phone: "9876543210", description: "x" },
    { amount_paise: 1000, phone: "+919876543210", description: "  " }, { amount_paise: 1000, phone: "+919876543210" },
    { order_id: ORDER, amount_paise: 1000, phone: "+919876543210", description: "both" }, { cancel: "x" }]) {
    assertEquals((await status(paymentLink(body, STAFF, store)))[0], 400, JSON.stringify(body));
  }
  assertEquals(log, []);
});

Deno.test("order link: amount and phone from the database, reference = the link's own id, no Razorpay SMS", async () => {
  const { store, log } = fakeStore();
  const fake = fakeFetch(() => ok({ id: "plink_1", short_url: "https://rzp.io/rzp/abc", status: "created" }));
  try {
    const res = await (await paymentLink({ order_id: ORDER }, STAFF, store)).json();
    assertEquals(res.short_url, "https://rzp.io/rzp/abc");
    assertEquals(log[0], ["admin_new_payment_link", { p_staff: STAFF, p_order_id: ORDER, p_amount_paise: null, p_phone: null, p_name: null, p_description: null }]);
    assertEquals(fake.calls[0].url, "https://api.razorpay.com/v1/payment_links");
    assertEquals(fake.calls[0].body, {
      amount: 44900, currency: "INR", description: "Shyam Mobiles order SM100001",
      customer: { contact: "+919876543210", name: "Asha Devi" }, notify: { sms: false, email: false }, reminder_enable: false,
      expire_by: 1793613600, reference_id: LINK, notes: { link_id: LINK, shop_order_id: ORDER },
    });
    assertEquals(log[1], ["saved", LINK, "plink_1", "https://rzp.io/rzp/abc"]);
  } finally {
    fake.restore();
  }
});

Deno.test("an open link is sent again without asking Razorpay", async () => {
  const { store } = fakeStore({ reused: true, short_url: "https://rzp.io/rzp/old" });
  const fake = fakeFetch(() => ok({}));
  try {
    assertEquals((await (await paymentLink({ order_id: ORDER }, STAFF, store)).json()).short_url, "https://rzp.io/rzp/old");
    assertEquals(fake.calls, []);
    const making = fakeStore({ reused: true, short_url: null });
    assertEquals((await status(paymentLink({ order_id: ORDER }, STAFF, making.store)))[1], "LINK_IN_PROGRESS");
  } finally {
    fake.restore();
  }
});

Deno.test("custom amount; Razorpay refusing removes the row and shows staff why", async () => {
  const { store, log } = fakeStore({ order_id: null, customer_name: null, amount_paise: 2500000, description: "10 × Redmi 13C" });
  const fake = fakeFetch(() => refused(400, "expire_by should be at least 15 minutes after current time"));
  try {
    assertEquals(await status(paymentLink({ amount_paise: 2500000, phone: "+919812345678", description: "10 × Redmi 13C" }, STAFF, store)),
      [409, "LINK_REFUSED", "Razorpay refused to make the link: expire_by should be at least 15 minutes after current time"]);
    const body = fake.calls[0].body as Record<string, unknown>;
    assertEquals([body.customer, body.notes], [{ contact: "+919876543210" }, { link_id: LINK }]);
    assertEquals(log.at(-1), ["remove", LINK]);
  } finally {
    fake.restore();
  }
});

Deno.test("cancel: only an open link, then closed in the database", async () => {
  const { store, log } = fakeStore({ razorpay_link_id: "plink_1", short_url: "https://rzp.io/rzp/abc" });
  const fake = fakeFetch(() => ok({ id: "plink_1", status: "cancelled" }));
  try {
    assertEquals(await (await paymentLink({ cancel: LINK }, STAFF, store)).json(), { id: LINK, status: "cancelled" });
    assertEquals([fake.calls[0].method, fake.calls[0].url], ["POST", "https://api.razorpay.com/v1/payment_links/plink_1/cancel"]);
    assertEquals(log.at(-1), ["close_payment_link", { p_razorpay_link_id: "plink_1", p_status: "cancelled" }]);
    const paid = fakeStore({ razorpay_link_id: "plink_1", status: "paid" });
    assertEquals(await status(paymentLink({ cancel: LINK }, STAFF, paid.store)), [409, "LINK_NOT_OPEN", "This link is paid already."]);
  } finally {
    fake.restore();
  }
});
