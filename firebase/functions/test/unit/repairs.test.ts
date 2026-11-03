import type { Timestamp } from "firebase-admin/firestore";
import { expect, test } from "vitest";
import * as c from "../../src/repairs/contract.js";
import { approveQuote, cancelByCustomer, type Change, declineQuote, newBooking, OPEN, type Repair, setQuote, staffUpdate } from "../../src/repairs/state.js";
import { reasonOf } from "../../src/shared/errors.js";
import { parse } from "../../src/shared/validation.js";
import { istDate } from "../../src/shared/time.js";
import { loadVectors, resolveTimes, startingDocs, type VectorCase } from "../vectors.js";
import { matches } from "./match.js";

// test-vectors/repairs-state.json through the pure state machine, with the handlers' load and guards done here.
const file = loadVectors("repairs-state");
const now = new Date(file.now);
type Docs = Record<string, Record<string, unknown>>;

function run(docs: Docs, k: VectorCase): { reply: Record<string, unknown> } {
  const contract = Object.values(c).find((x) => x.name === k.call);
  if (!contract) throw new Error(k.call);
  const input = parse(contract.input, k.input, contract.invalid) as Record<string, unknown>;
  if (k.as === "anon") throw Object.assign(new Error(), { reason: "UNAUTHORIZED" });
  const staff = docs[`users/${k.as}`]?.role !== undefined;
  const at = now as unknown as Timestamp;
  if (k.call === "bookRepair") {
    const open = Object.entries(docs).filter(([p, d]) => p.startsWith("repairs/") && d.uid === k.as && OPEN.includes(d.status as never)).length;
    const next = (docs["counters/repairs"]?.next as number | undefined) ?? 100001;
    const doc = newBooking(input as never, k.as, open, next, istDate(now), at);
    docs["repairs/new"] = { ...doc, createdAt: now, purgeAt: new Date(now.getTime() + 3 * 366 * 86_400_000) };
    docs["counters/repairs"] = { next: next + 1 };
    return { reply: { repairId: "new" } };
  }
  if (k.call.startsWith("admin") && !staff) throw Object.assign(new Error(), { reason: "FORBIDDEN" });
  const path = `repairs/${String(input.repairId)}`;
  const r = docs[path] as unknown as (Repair & { events: unknown[] }) | undefined;
  if (!r) throw Object.assign(new Error(), { reason: "NOT_FOUND" });
  const i = input as { quotePaise: number; reason?: string | null; status: never; note?: string | null; approved: boolean };
  const table: Record<string, () => Change | null> = {
    cancelRepair: () => cancelByCustomer(r, k.as, at),
    approveRepairQuote: () => approveQuote(r, k.as, i.quotePaise, at),
    declineRepairQuote: () => declineQuote(r, k.as, i.reason ?? null, at),
    adminUpdateRepair: () => staffUpdate(r, k.as, i.status, i.note ?? null, at),
    adminSetRepairQuote: () => setQuote(r, k.as, i.quotePaise, i.note ?? null, i.approved, at),
  };
  const decided = table[k.call]?.() ?? null;
  if (decided) docs[path] = { ...r, status: decided.status, quote: decided.quote, events: [...r.events, decided.event], updatedAt: now };
  return { reply: {} };
}

test.each(file.cases.map((k) => [k.id, k] as const))("%s", (_id, k) => {
  const docs = startingDocs(file, k) as Docs;
  let reply: Record<string, unknown> | null = null;
  let error: { reason: string | null; detail: unknown } | null = null;
  try {
    reply = run(docs, k).reply;
  } catch (e) {
    error = { reason: reasonOf(e) ?? (e as { reason?: string }).reason ?? null, detail: (e as { details?: { detail?: unknown } }).details?.detail };
  }
  if (k.error !== undefined) {
    expect(error?.reason).toBe(k.error);
    if (k.errorDetail !== undefined) expect(error?.detail).toEqual(k.errorDetail);
  } else {
    expect(error).toBeNull();
    if (k.expect) matches(reply, resolveTimes({ ...k.expect, repairId: k.expect.repairId === "$repairId" ? "new" : k.expect.repairId }, now));
  }
  for (const [path, want] of Object.entries(resolveTimes(k.then ?? {}, now))) {
    matches(docs[path.replace("$repairId", "new")], want, path);
  }
});
