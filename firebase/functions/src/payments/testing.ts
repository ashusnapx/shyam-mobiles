// Test helpers: a recording fetch for PhonePe's HTTP API, a small in-memory Firestore (the calls the payment flows use),
// and a stand-in for orders/settlement.ts with the semantics docs/FIREBASE.md §5 gives it.
import type { Firestore, Transaction } from "firebase-admin/firestore";
import type { Settlement } from "./flows.js";
import type { PhonePeConfig } from "./phonepe.js";
import { PaymentError } from "./service.js";

export type Call = { method: string; url: string; headers: Headers; body: unknown };

export const CONFIG: PhonePeConfig = {
  env: "SANDBOX", clientId: "pp_client_fake", clientSecret: "pp_secret_fake", clientVersion: "1", merchantId: "PPFAKEMERCHANT",
};
export const SANDBOX = "https://api-preprod.phonepe.com/apis/pg-sandbox";
export const TOKEN_URL = `${SANDBOX}/v1/oauth/token`;

export function fakeFetch(reply: (call: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fetcher = (async (input: string | URL | Request, init?: RequestInit) => {
    const call = {
      method: init?.method ?? "GET",
      url: typeof input === "string" ? input : input instanceof URL ? input.href : input.url,
      headers: new Headers(init?.headers),
      body: init?.body instanceof URLSearchParams ? Object.fromEntries(init.body) : typeof init?.body === "string" ? JSON.parse(init.body) as unknown : undefined,
    };
    calls.push(call);
    return await reply(call);
  }) as typeof fetch;
  return { calls, fetcher };
}

export const ok = (body: unknown) => Response.json(body);

/** What [p] rejected with; fails the test if it resolved. */
export async function rejection(p: Promise<unknown>): Promise<Record<string, unknown>> {
  try {
    await p;
  } catch (e) {
    return e as Record<string, unknown>;
  }
  throw new Error("expected a rejection");
}
export const token = (accessToken = "pp_access_fake") => {
  const now = Math.floor(Date.now() / 1000);
  return ok({ access_token: accessToken, token_type: "O-Bearer", issued_at: now, expires_at: now + 3600 });
};
export const refused = (status: number, code: string, message: string) => Response.json({ code, message, data: {} }, { status });

// In-memory Firestore ------------------------------------------------------------------------------------------------

type Data = Record<string, unknown>;
type Where = [field: string, value: unknown];

/** doc / collection().where("f", "==", v).limit(n) / get / update / runTransaction (serialised; reads before writes;
 * create fails on an existing doc, update on a missing one). */
export function fakeFirestore(seed: Record<string, Data> = {}) {
  const docs = new Map<string, Data>(Object.entries(seed).map(([k, v]) => [k, structuredClone(v)]));
  const copy = (d: Data | undefined) => (d === undefined ? undefined : structuredClone(d));
  const snap = (path: string) => {
    const d = copy(docs.get(path));
    return { id: path.slice(path.lastIndexOf("/") + 1), ref: ref(path), exists: d !== undefined, data: () => copy(d) };
  };
  const ref = (path: string) => ({
    path, id: path.slice(path.lastIndexOf("/") + 1), kind: "doc" as const,
    get: () => Promise.resolve(snap(path)),
    update: (d: Data) => new Promise<void>((resolve) => {
      write(path, d, "update");
      resolve();
    }),
  });
  const query = (collection: string, where: Where[] = [], max = Infinity) => {
    const run = () => {
      const hits = [...docs.keys()].filter((k) => k.startsWith(`${collection}/`) && !k.slice(collection.length + 1).includes("/"))
        .sort().filter((k) => where.every(([f, v]) => docs.get(k)?.[f] === v)).slice(0, max);
      return { empty: hits.length === 0, docs: hits.map(snap) };
    };
    return {
      kind: "query" as const,
      where: (field: string, _op: "==", value: unknown) => query(collection, [...where, [field, value]], max),
      limit: (n: number) => query(collection, where, n),
      get: () => Promise.resolve(run()),
      run,
    };
  };
  function write(path: string, d: Data, how: "create" | "update" | "set") {
    if (how === "create" && docs.has(path)) throw Object.assign(new Error(`ALREADY_EXISTS ${path}`), { code: 6 });
    if (how === "update" && !docs.has(path)) throw Object.assign(new Error(`NOT_FOUND ${path}`), { code: 5 });
    if (how === "update" && !Object.keys(d).length) throw new Error("empty update");
    docs.set(path, { ...(how === "update" ? docs.get(path) : {}), ...structuredClone(d) });
  }
  let queue: Promise<unknown> = Promise.resolve();
  const db = {
    docs,
    doc: ref,
    collection: (path: string) => query(path),
    runTransaction<T>(fn: (tx: Transaction) => Promise<T>): Promise<T> {
      const go = async () => {
        const writes: (() => void)[] = [];
        const later = (f: () => void) => {
          writes.push(f);
        };
        const tx = {
          get(r: ReturnType<typeof ref> | ReturnType<typeof query>) {
            if (writes.length) return Promise.reject(new Error("transaction read after a write"));
            return Promise.resolve(r.kind === "doc" ? snap(r.path) : r.run());
          },
          create: (r: { path: string }, d: Data) => {
            later(() => { write(r.path, d, "create"); });
          },
          set: (r: { path: string }, d: Data) => {
            later(() => { write(r.path, d, "set"); });
          },
          update: (r: { path: string }, d: Data) => {
            if (!Object.keys(d).length) throw new Error("empty update"); // Firestore refuses these
            later(() => { write(r.path, d, "update"); });
          },
        };
        const result = await fn(tx as unknown as Transaction);
        for (const w of writes) w();
        return result;
      };
      const next = queue.then(go, go);
      queue = next.catch(() => undefined);
      return next;
    },
  };
  return { db, firestore: db as unknown as Firestore };
}

// Stand-in for orders/settlement.ts ----------------------------------------------------------------------------------

type Order = Data & { status: string; paymentStatus: string; totalPaise: number; events?: Data[]; items: Data[] };

/** Engineer C's settleOnlinePayment / settleRefund, reduced to what §5 promises; records each call. */
export function fakeSettlement(now: number) {
  const calls: string[] = [];
  const get = async <T>(tx: Transaction, path: string, fs: Firestore) => (await tx.get(fs.doc(path))).data() as T | undefined;
  const make = (fs: Firestore): Settlement => ({
    async settleOnlinePayment(tx, orderId, p) {
      calls.push(`payment ${p.merchantOrderId} ${p.state}`);
      const aPath = `orders/${orderId}/payments/${p.merchantOrderId}`;
      const a = await get<{ state: string }>(tx, aPath, fs);
      const o = await get<Order>(tx, `orders/${orderId}`, fs);
      if (!a || !o) throw new PaymentError(404, "NOT_FOUND", "no such payment");
      if (a.state === "completed" || p.state === "pending") return;
      const at = new Date(now);
      if (p.state === "failed") {
        if (a.state !== "pending") return;
        tx.update(fs.doc(aPath), { state: "failed", updatedAt: at });
        if (o.paymentStatus === "pending") tx.update(fs.doc(`orders/${orderId}`), { paymentStatus: "failed", updatedAt: at });
        return;
      }
      if (p.amountPaise !== o.totalPaise) throw new PaymentError(409, "PAYMENT_MISMATCH", "amount differs");
      tx.update(fs.doc(aPath), { state: "completed", transactionId: p.transactionId, updatedAt: at });
      const events = [...(o.events ?? [])];
      if (o.paymentStatus === "paid" || o.paymentStatus === "refunded") {
        events.push({ status: o.status, note: "second payment: refund due", by: "system", at });
        tx.update(fs.doc(`orders/${orderId}`), { events, updatedAt: at });
        return;
      }
      events.push({ status: "confirmed", note: "Payment received", by: "system", at });
      tx.update(fs.doc(`orders/${orderId}`), {
        status: o.status === "pending_payment" ? "confirmed" : o.status, paymentStatus: "paid", reservedUntil: null, events,
        payment: { gateway: "phonepe", merchantOrderId: p.merchantOrderId, transactionId: p.transactionId, paidAt: at }, updatedAt: at,
      });
    },
    async settleRefund(tx, orderId, refundId, r) {
      calls.push(`refund ${refundId} ${r.state}`);
      const rPath = `orders/${orderId}/refunds/${refundId}`;
      const f = await get<{ status: string; amountPaise: number }>(tx, rPath, fs);
      const o = await get<Order>(tx, `orders/${orderId}`, fs);
      if (!f || !o) throw new PaymentError(404, "NOT_FOUND", "no such refund");
      if (f.status !== "pending" || r.state === "pending") return;
      const at = new Date(now);
      const status = r.state === "completed" ? "processed" : "failed";
      tx.update(fs.doc(rPath), { status, gatewayRefundId: r.gatewayRefundId, failure: r.failure, updatedAt: at });
      tx.update(fs.doc(`orders/${orderId}`), {
        pendingRefundId: null, updatedAt: at,
        items: o.items.map((i) => (status === "failed" && i.refundId === refundId ? { ...i, refundId: null } : i)),
        ...(status === "processed" && f.amountPaise >= o.totalPaise ? { paymentStatus: "refunded" } : {}),
      });
    },
  });
  return { calls, make };
}
