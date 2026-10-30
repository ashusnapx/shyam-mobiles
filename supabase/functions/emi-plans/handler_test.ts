import { assertEquals } from "jsr:@std/assert@1";
import { fakeFetch, ok } from "../_shared/fake_fetch.ts";
import { emiPlans, forgetCache, plansFrom } from "./handler.ts";

const methods = {
  emi: true,
  emi_options: {
    KKBK: [
      { duration: 3, interest: 12, subvention: "customer", min_amount: 300000, merchant_payback: "1.97" },
      { duration: 6, interest: 12, subvention: "customer", min_amount: 300000 },
    ],
    UTIB: [
      { duration: 3, interest: 13, subvention: "customer", min_amount: 300000 },
      { duration: 3, interest: 12, subvention: "customer", min_amount: 300000 }, // Razorpay lists some twice
      { duration: 6, interest: 0, subvention: "merchant", min_amount: 1000000 },
    ],
    "bad code": [{ duration: 3, interest: 12, min_amount: 1 }],
    HDFC: [{ duration: "x", interest: 12, min_amount: 1 }, { duration: 9, interest: -1, min_amount: 1 }],
  },
  netbanking: { KKBK: "Kotak Bank (from netbanking)" },
};

Deno.test("plansFrom: one plan per bank and tenure, cheapest kept, junk dropped, sorted", () => {
  assertEquals(plansFrom(methods), [
    { bank: "UTIB", name: "Axis Bank", months: 3, rate: 12, min_paise: 300000, no_cost: false },
    { bank: "UTIB", name: "Axis Bank", months: 6, rate: 0, min_paise: 1000000, no_cost: true },
    { bank: "KKBK", name: "Kotak Mahindra Bank", months: 3, rate: 12, min_paise: 300000, no_cost: false },
    { bank: "KKBK", name: "Kotak Mahindra Bank", months: 6, rate: 12, min_paise: 300000, no_cost: false },
  ]);
});

Deno.test("plansFrom: EMI off (this test account) or missing -> none", () => {
  assertEquals(plansFrom({ emi: false, emi_options: methods.emi_options }), []);
  assertEquals(plansFrom({}), []);
});

Deno.test("plansFrom: older accounts send only emi_plans", () => {
  assertEquals(plansFrom({ emi: true, emi_subvention: "customer", emi_plans: { RATN: { min_amount: 250000, plans: { "3": 14, "12": 15 } } } }), [
    { bank: "RATN", name: "RBL Bank", months: 3, rate: 14, min_paise: 250000, no_cost: false },
    { bank: "RATN", name: "RBL Bank", months: 12, rate: 15, min_paise: 250000, no_cost: false },
  ]);
});

Deno.test("emiPlans: key id only, cached for a day", async () => {
  forgetCache();
  const fake = fakeFetch(() => ok(methods));
  try {
    const first = await (await emiPlans(1_000)).json();
    assertEquals(first.plans.length, 4);
    await emiPlans(1_000 + 3_600_000);
    assertEquals(fake.calls.length, 1, "an hour later: from the cache");
    assertEquals(fake.calls[0].url, "https://api.razorpay.com/v1/methods");
    assertEquals(fake.calls[0].headers.get("authorization"), `Basic ${btoa("rzp_test_fake:")}`, "no secret sent");
    await emiPlans(1_000 + 86_400_001);
    assertEquals(fake.calls.length, 2, "a day later: fetched again");
  } finally {
    fake.restore();
    forgetCache();
  }
});
