import { type DocumentSnapshot, getFirestore, type Transaction } from "firebase-admin/firestore";
import type { Db, Doc, Tx } from "./db.js";

// db.ts's Db on Firestore. runTransaction may run fn more than once on contention: the payment code only reads and
// writes through tx inside it, and calls PhonePe outside.
export function firestoreDb(fs = getFirestore()): Db {
  const data = <T>(s: DocumentSnapshot) => (s.exists ? (s.data() as T) : null);
  return {
    async get<T>(path: string) {
      return data<T>(await fs.doc(path).get());
    },
    async update(path: string, d: Doc) {
      await fs.doc(path).update(d);
    },
    tx<T>(fn: (tx: Tx) => Promise<T>) {
      return fs.runTransaction((t: Transaction) =>
        fn({
          get: async <U>(path: string) => data<U>(await t.get(fs.doc(path))),
          set: (path, d) => void t.set(fs.doc(path), d),
          update: (path, d) => void t.update(fs.doc(path), d),
          add: (collection, d) => void t.set(fs.collection(collection).doc(), d),
        }));
    },
  };
}
