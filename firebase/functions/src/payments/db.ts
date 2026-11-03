// The few document operations the payment code needs, so it runs against Firestore (firestore.ts) in production and
// against memoryDb() in tests. Paths are Firestore paths ("orders/abc"). Inside tx(), every get comes before any write
// (Firestore's transaction rule; memoryDb enforces it too).

export type Doc = Record<string, unknown>;

export interface Tx {
  get<T = Doc>(path: string): Promise<T | null>;
  set(path: string, data: Doc): void; // create or replace
  update(path: string, data: Doc): void; // merge these fields into an existing doc
  add(collection: string, data: Doc): void; // a new doc with a generated id
}

export interface Db {
  get<T = Doc>(path: string): Promise<T | null>;
  update(path: string, data: Doc): Promise<void>;
  tx<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
}

// In-memory Db for tests: transactions run one at a time and commit only if fn returns.
export function memoryDb(seed: Record<string, Doc> = {}) {
  const docs = new Map<string, Doc>(Object.entries(seed).map(([k, v]) => [k, structuredClone(v)]));
  let queue: Promise<unknown> = Promise.resolve();
  let ids = 0;
  const read = <T>(path: string) => (docs.has(path) ? (structuredClone(docs.get(path)) as T) : null);

  const db: Db & { docs: Map<string, Doc>; under(collection: string): [string, Doc][] } = {
    docs,
    under: (collection) => [...docs].filter(([k]) => k.startsWith(`${collection}/`) && !k.slice(collection.length + 1).includes("/")),
    async get<T>(path: string) {
      return read<T>(path);
    },
    async update(path, data) {
      if (!docs.has(path)) throw new Error(`no document ${path}`);
      docs.set(path, { ...docs.get(path), ...structuredClone(data) });
    },
    tx<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
      const run = async () => {
        const writes: (() => void)[] = [];
        const tx: Tx = {
          async get<U>(path: string) {
            if (writes.length) throw new Error("transaction read after a write");
            return read<U>(path);
          },
          set: (path, data) => void writes.push(() => docs.set(path, structuredClone(data))),
          update: (path, data) => {
            if (!Object.keys(data).length) throw new Error("empty update"); // Firestore refuses these too
            writes.push(() => {
              if (!docs.has(path)) throw new Error(`no document ${path}`);
              docs.set(path, { ...docs.get(path), ...structuredClone(data) });
            });
          },
          add: (collection, data) => void writes.push(() => docs.set(`${collection}/auto${++ids}`, structuredClone(data))),
        };
        const result = await fn(tx);
        for (const w of writes) w();
        return result;
      };
      const next = queue.then(run, run);
      queue = next.catch(() => undefined);
      return next;
    },
  };
  return db;
}
