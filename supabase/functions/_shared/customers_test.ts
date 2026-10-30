import { assertEquals } from "jsr:@std/assert@1";
import { fakeFetch, ok, refused } from "./fake_fetch.ts";
import { customerFor, type CustomerStore, forgetCustomer } from "./customers.ts";

function fakeStore(who: Awaited<ReturnType<CustomerStore["who"]>>, saved: string | null = null) {
  const rows = new Map<string, string>();
  if (saved) rows.set("u1", saved);
  const store: CustomerStore = {
    async find(userId) {
      return rows.get(userId) ?? null;
    },
    async who() {
      return who;
    },
    async save(userId, id) {
      if (!rows.has(userId)) rows.set(userId, id);
      return rows.get(userId)!;
    },
  };
  return { store, rows };
}

Deno.test("customerFor: made once from the verified phone, then reused", async () => {
  const { store, rows } = fakeStore({ phone: "919876543210", email: "asha@example.com", name: "Asha Devi" });
  const fake = fakeFetch(() => ok({ id: "cust_1" }));
  try {
    assertEquals(await customerFor(store, "u1"), "cust_1");
    assertEquals(fake.calls[0].body, { name: "Asha Devi", contact: "+919876543210", fail_existing: "0" });
    assertEquals(await customerFor(store, "u1"), "cust_1");
    assertEquals(fake.calls.length, 1);
    assertEquals(rows.get("u1"), "cust_1");
  } finally {
    fake.restore();
  }
});

Deno.test("customerFor: email accounts; a name Razorpay won't take is left out", async () => {
  const { store } = fakeStore({ phone: null, email: "asha@example.com", name: "आशा देवी" });
  const fake = fakeFetch(() => ok({ id: "cust_2" }));
  try {
    assertEquals(await customerFor(store, "u2"), "cust_2");
    assertEquals(fake.calls[0].body, { email: "asha@example.com", fail_existing: "0" });
  } finally {
    fake.restore();
  }
});

Deno.test("customerFor: Razorpay down or no contact -> null, never throws", async () => {
  const fake = fakeFetch(() => refused(500, "down"));
  try {
    assertEquals(await customerFor(fakeStore({ phone: "+919876543210" }).store, "u3"), null);
    assertEquals(await customerFor(fakeStore({}).store, "u4"), null);
    assertEquals(fake.calls.length, 1, "nothing to make a customer from: no call");
  } finally {
    fake.restore();
  }
});

Deno.test("forgetCustomer deletes every saved card; errors are swallowed", async () => {
  const fake = fakeFetch((c) => c.method === "GET" ? ok({ items: [{ id: "token_a" }, { id: "token_b" }] }) : ok({ deleted: true }));
  try {
    await forgetCustomer("cust_1");
    assertEquals(fake.calls.map((c) => `${c.method} ${c.url}`), [
      "GET https://api.razorpay.com/v1/customers/cust_1/tokens",
      "DELETE https://api.razorpay.com/v1/customers/cust_1/tokens/token_a",
      "DELETE https://api.razorpay.com/v1/customers/cust_1/tokens/token_b",
    ]);
  } finally {
    fake.restore();
  }
  const down = fakeFetch(() => refused(500, "down"));
  try {
    await forgetCustomer("cust_1");
  } finally {
    down.restore();
  }
});
