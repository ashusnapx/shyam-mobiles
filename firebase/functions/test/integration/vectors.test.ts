import { Timestamp } from "firebase-admin/firestore";
import type { CallableRequest } from "firebase-functions/v2/https";
import { afterAll, beforeAll, describe, expect, test, vi } from "vitest";
import * as offers from "../../src/offers/handlers.js";
import * as orders from "../../src/orders/handlers.js";
import { offerOpenFor } from "../../src/orders/pricing.js";
import { promoOf, promotionOf } from "../../src/orders/repository.js";
import { settleOnlinePayment, settleRefund } from "../../src/orders/settlement.js";
import { fakeGateway } from "../../src/payments/fake_gateway.js";
import { startRefund } from "../../src/payments/flows.js";
import * as payments from "../../src/payments/handlers.js";
import { PaymentError } from "../../src/payments/service.js";
import * as referrals from "../../src/referrals/handlers.js";
import { db } from "../../src/shared/db.js";
import { reasonOf } from "../../src/shared/errors.js";
import { loadVectors, resolveTimes, startingDocs, type VectorCase, type VectorFile } from "../vectors.js";

// Engineer C's vectors (pricing, offers, referrals, orders-state, settlement) on the Firestore emulator: each case
// writes its world, calls the real handler in-process as its caller (fake Date = the file's "now"), then reads the
// docs back. Run alone: firebase emulators:exec --only firestore "vitest run test/integration/vectors.test.ts".

type Docs = Record<string, unknown>;
type Out = { result?: Docs; reason?: string | null; detail?: unknown };

const host = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
const clear = () => fetch(`http://${host}/emulator/v1/projects/${process.env.GCLOUD_PROJECT ?? "demo-shyam-mobiles"}/databases/(default)/documents`, { method: "DELETE" });

async function write(docs: Record<string, Docs>) {
  const entries = Object.entries(docs);
  for (let i = 0; i < entries.length; i += 400) {
    const batch = db().batch();
    for (const [path, d] of entries.slice(i, i + 400)) batch.set(db().doc(path), d);
    await batch.commit();
  }
}

function request(c: VectorCase, docs: Record<string, Docs>, data: unknown): CallableRequest {
  if (c.as === "anon" || c.as === "system") return { data, rawRequest: {} } as unknown as CallableRequest;
  const role = docs[`users/${c.as}`]?.role as string | undefined;
  const token = { uid: c.as, auth_time: Date.now() / 1000, firebase: { sign_in_provider: "google.com", ...(role ? { sign_in_second_factor: "totp" } : {}) }, ...(role ? { role } : {}) };
  return { data, auth: { uid: c.as, token }, rawRequest: {} } as unknown as CallableRequest;
}

const CALLABLES: Record<string, { run: (r: CallableRequest) => unknown }> = {
  quoteOrder: orders.quoteOrder, placeOrder: orders.placeOrder, cancelOrder: orders.cancelOrder, adminUpdateOrder: orders.adminUpdateOrder,
  adminSetImeis: orders.adminSetImeis, savePromotion: offers.savePromotion, myReferral: referrals.myReferral,
  applyReferralCode: referrals.applyReferralCode,
};

async function call(c: VectorCase, docs: Record<string, Docs>, input: Docs): Promise<Out> {
  try {
    const fn = CALLABLES[c.call];
    if (fn) return { result: (await fn.run(request(c, docs, input))) as Docs };
    const { orderId, refundId, ...rest } = input as { orderId: string; refundId: string } & Docs;
    switch (c.call) {
      case "expireUnpaidOrders": return { result: await orders.expireUnpaid() };
      case "settleOnlinePayment":
        return { result: await db().runTransaction((tx) => settleOnlinePayment(tx, orderId, rest as Parameters<typeof settleOnlinePayment>[2])) };
      case "settleRefund": {
        const r = { state: rest.state, gatewayRefundId: rest.gatewayRefundId ?? null, failure: rest.failure ?? null };
        return { result: await db().runTransaction((tx) => settleRefund(tx, orderId, refundId, r as Parameters<typeof settleRefund>[3])) };
      }
      case "startRefund": {
        if (!docs[`users/${c.as}`]?.role) return { result: await payments.startRefund.run(request(c, docs, input)) };
        const deps = { db: db(), gateway: fakeGateway().gateway, settlement: { settleOnlinePayment, settleRefund } };
        return { result: await startRefund(input, c.as, deps) };
      }
      case "offerOpenFor": {
        const i = input as { promotion: Docs; uid: string | null; usesTotal: number; usesByUser: number; hasPlacedOrder: boolean };
        return { result: { open: offerOpenFor(promoOf("p", promotionOf(i.promotion)), i.uid, i.usesTotal, i.usesByUser, i.hasPlacedOrder, new Date()) } };
      }
    }
    throw new Error(`no runner for ${c.call}`);
  } catch (e) {
    if (e instanceof PaymentError) return { reason: e.reason, detail: e.message };
    const reason = reasonOf(e);
    if (reason === null) throw e;
    return { reason, detail: ((e as { details?: { detail?: unknown } }).details)?.detail };
  }
}

/** Deep-partial: null = absent or null, {} = empty, arrays element by element, Dates against Timestamps. */
function mismatch(actual: unknown, want: unknown, at: string): string | null {
  const a = actual instanceof Timestamp ? actual.toDate() : actual;
  if (want === null) return a === null || a === undefined ? null : `${at}: want null, got ${JSON.stringify(a)}`;
  if (want instanceof Date) return a instanceof Date && a.getTime() === want.getTime() ? null : `${at}: want ${want.toISOString()}, got ${String(a)}`;
  if (Array.isArray(want)) {
    if (!Array.isArray(a) || a.length !== want.length) return `${at}: want ${want.length} items, got ${JSON.stringify(a)}`;
    return want.map((w, i) => mismatch(a[i], w, `${at}[${i}]`)).find((m) => m !== null) ?? null;
  }
  if (typeof want === "object") {
    if (typeof a !== "object" || a === null) return `${at}: want object, got ${JSON.stringify(a)}`;
    if (Object.keys(want).length === 0 && Object.keys(a).length > 0) return `${at}: want {}, got ${JSON.stringify(a)}`;
    return Object.entries(want).map(([k, w]) => mismatch((a as Docs)[k], w, `${at}.${k}`)).find((m) => m !== null) ?? null;
  }
  return a === want ? null : `${at}: want ${JSON.stringify(want)}, got ${JSON.stringify(a)}`;
}

function fill<T>(v: T, ids: Record<string, string>): T {
  if (typeof v === "string") return (ids[v] ?? v) as T;
  if (Array.isArray(v)) return v.map((x: unknown) => fill(x, ids)) as T;
  if (v && typeof v === "object" && !(v instanceof Date)) return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fill(x, ids)])) as T;
  return v;
}

async function check(c: VectorCase, file: VectorFile): Promise<void> {
  const now = new Date(file.now);
  await clear();
  const docs = startingDocs(file, c) as Record<string, Docs>;
  await write(docs);
  const out = await call(c, docs, resolveTimes(c.input, now));
  if (c.error !== undefined) {
    expect(out.reason, JSON.stringify(out)).toBe(c.error);
    if (c.errorDetail !== undefined) expect(out.detail).toEqual(c.errorDetail);
  } else {
    expect(out.reason, JSON.stringify(out.detail)).toBeUndefined();
    if (c.expect && Object.keys(c.expect).length) expect(mismatch(out.result, resolveTimes(c.expect, now), "result")).toBeNull();
  }
  const r = out.result ?? {};
  const ids = Object.fromEntries([["$orderId", r.orderId], ["$refundId", r.refundId], ["$id", r.id]].filter(([, x]) => typeof x === "string")) as Record<string, string>;
  for (const [key, want] of Object.entries(fill(resolveTimes(c.then ?? {}, now), ids))) {
    const path = fill(key.replace(/\$\w+/g, (k) => ids[k] ?? k), ids);
    if (path.endsWith("/*")) {
      const snap = await db().collection(path.slice(0, -2)).get();
      if (want === null) expect(snap.size, path).toBe(0);
      else {
        expect(snap.size, path).toBe(1);
        expect(mismatch(snap.docs[0]?.data(), want, path)).toBeNull();
      }
    } else {
      expect(mismatch((await db().doc(path).get()).data() ?? null, want, path)).toBeNull();
    }
  }
}

beforeAll(() => {
  vi.useFakeTimers({ toFake: ["Date"], now: new Date("2026-11-03T12:00:00+05:30") });
});
afterAll(() => {
  vi.useRealTimers();
});

describe.each(["pricing", "offers", "referrals", "orders-state", "settlement"])("%s.json", (name) => {
  const file = loadVectors(name);
  test.each(file.cases.map((c) => [c.id, c] as const))("%s", async (_id, c) => {
    vi.setSystemTime(new Date(file.now));
    await check(c, file);
  });
});
