import { assert, assertEquals, assertMatch, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import { HttpError } from "../_shared/http.ts";
import type { Rpc } from "../_shared/supabase.ts";
import { type Account, type Accounts, randomInt, resetPassword, temporaryPassword, WORDS } from "./handler.ts";

const STAFF = "0b8f5a3e-1111-4222-8333-944445555999";
const RAVI: Account = { user_id: "0b8f5a3e-1111-4222-8333-944445555111", full_name: "Ravi Kumar", staff: false, created_at: "2026-11-01T10:00:00Z" };

function fakeAccounts(account: Account | null = RAVI, failUpdate = false) {
  const log: unknown[][] = [];
  const rpc: Rpc = async (fn, args) => {
    log.push([fn, args]);
    return { data: account, error: null };
  };
  const accounts: Accounts = {
    rpc,
    async update(id, attrs) {
      log.push(["update", id, attrs]);
      if (failUpdate) throw new Error("auth down");
    },
  };
  return { accounts, log };
}

async function refusal(p: Promise<unknown>) {
  const e = await assertRejects(() => p, HttpError);
  return [e.status, e.code];
}

Deno.test("bad bodies -> 400 before any lookup", async () => {
  const { accounts, log } = fakeAccounts();
  for (const body of [{}, { phone: "9876543210" }, { phone: "+915876543210" }, { phone: "+91987654321" },
    { phone: 9876543210 }, { phone: "+919876543210", reset: "yes" }]) {
    assertEquals(await refusal(resetPassword(body, STAFF, accounts)), [400, "BAD_REQUEST"], JSON.stringify(body));
  }
  assertEquals(log, []);
});

Deno.test("lookup: whose account it is, nothing changed", async () => {
  const { accounts, log } = fakeAccounts();
  const res = await resetPassword({ phone: "+919876543210" }, STAFF, accounts);
  assertEquals(await res.json(), { user_id: RAVI.user_id, full_name: "Ravi Kumar", phone: "+919876543210", created_at: RAVI.created_at });
  assertEquals(log, [["account_by_phone", { p_phone: "+919876543210" }]]);
});

Deno.test("reset: the password first, then the must-change flag, and the password comes back", async () => {
  const { accounts, log } = fakeAccounts();
  const res = await resetPassword({ phone: "+919876543210", reset: true }, STAFF, accounts);
  const body = await res.json();
  assertMatch(body.password, /^[A-Z][a-z]+-[A-Z][a-z]+-\d{4}$/);
  assertEquals(body.full_name, "Ravi Kumar");
  assertEquals(log.slice(1), [
    ["update", RAVI.user_id, { password: body.password }],
    ["update", RAVI.user_id, { app_metadata: { must_change_password: true } }],
  ]);
});

Deno.test("no account for the number -> 404 NO_ACCOUNT; staff accounts are refused", async () => {
  assertEquals(await refusal(resetPassword({ phone: "+919876543210", reset: true }, STAFF, fakeAccounts(null).accounts)), [404, "NO_ACCOUNT"]);
  const staff = fakeAccounts({ ...RAVI, staff: true });
  assertEquals(await refusal(resetPassword({ phone: "+919876543210", reset: true }, STAFF, staff.accounts)), [403, "STAFF_ACCOUNT"]);
  assertEquals(staff.log.filter(([what]) => what === "update"), []);
});

Deno.test("Auth refusing the update is a server error, not a fake success", async () => {
  await assertRejects(() => resetPassword({ phone: "+919876543210", reset: true }, STAFF, fakeAccounts(RAVI, true).accounts), Error, "auth down");
});

Deno.test("temporary passwords: two different words and 4 digits, from the CSPRNG", () => {
  assertEquals(new Set(WORDS).size, WORDS.length);
  assertEquals(temporaryPassword(() => 0), "Apple-Mango-0000");
  const last = (n: number) => n - 1;
  assertEquals(temporaryPassword(last), `Jade-Pearl-9999`); // the second word skips the first, wrapping round
  const seen = new Set<string>();
  for (let i = 0; i < 200; i++) {
    const p = temporaryPassword();
    const [a, b, digits] = p.split("-");
    assert(WORDS.includes(a) && WORDS.includes(b) && /^\d{4}$/.test(digits), p);
    assertNotEquals(a, b);
    assert(p.length >= 8);
    seen.add(p);
  }
  assert(seen.size > 190, "random enough");
  for (let i = 0; i < 1000; i++) {
    const n = randomInt(7);
    assert(n >= 0 && n < 7);
  }
});
