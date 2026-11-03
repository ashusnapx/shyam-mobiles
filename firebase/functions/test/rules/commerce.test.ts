import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, limit, query, serverTimestamp, setDoc, Timestamp, updateDoc, where } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, test } from "vitest";

// Engineer C's Rules section: carts, orders, offers, referrals (ports of rls.test.sql / attacks.test.sql for them).

let env: RulesTestEnvironment;
beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-shyam-mobiles",
    firestore: { rules: readFileSync(new URL("../../../firestore.rules", import.meta.url), "utf8") },
  });
});
afterAll(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, "users/staff"), { role: "staff" });
    await setDoc(doc(db, "orders/o1"), { uid: "alice", status: "confirmed", totalPaise: 100 });
    await setDoc(doc(db, "orders/o1/refunds/r1"), { amountPaise: 100, status: "pending" });
    await setDoc(doc(db, "orders/o1/payments/SM100001-aaaaaaaa"), { state: "pending", token: "t" });
    await setDoc(doc(db, "orders/o2"), { uid: "bob", status: "confirmed", totalPaise: 100 });
    for (const p of ["promotions/p1", "promoCodes/HIDDEN1", "redemptions/o1", "referralCodes/ALICE123", "referrals/bob", "counters/orders", "publicOffers/p2", "users/alice/coupons/p3"]) {
      await setDoc(doc(db, p), { x: 1 });
    }
  });
});

const alice = () => env.authenticatedContext("alice").firestore();
const staffToken = { role: "staff", firebase: { sign_in_provider: "google.com", sign_in_second_factor: "totp" } } as unknown as { role: string };
const staff = () => env.authenticatedContext("staff", staffToken).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const line = { qty: 1, addedAt: Timestamp.now() };

describe("carts/{uid}", () => {
  test("the owner writes lines (≤ 20) stamped now; nobody else reads or writes it", async () => {
    await assertSucceeds(setDoc(doc(alice(), "carts/alice"), { lines: { v1: line }, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(alice(), "carts/alice"), { lines: {}, updatedAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(alice(), "carts/alice")));
    await assertFails(getDoc(doc(staff(), "carts/alice")));
    await assertFails(setDoc(doc(staff(), "carts/alice"), { lines: {}, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), "carts/bob"), { lines: {}, updatedAt: serverTimestamp() }));
    const many = Object.fromEntries(Array.from({ length: 21 }, (_, i) => [`v${i}`, line]));
    await assertFails(setDoc(doc(alice(), "carts/alice"), { lines: many, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), "carts/alice"), { lines: {}, pricePaise: 1, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), "carts/alice"), { lines: {}, updatedAt: Timestamp.fromMillis(0) }));
    await assertSucceeds(deleteDoc(doc(alice(), "carts/alice")));
  });
});

describe("orders", () => {
  test("the customer reads only their own orders, staff read all, nobody writes", async () => {
    await assertSucceeds(getDoc(doc(alice(), "orders/o1")));
    await assertFails(getDoc(doc(alice(), "orders/o2")));
    await assertSucceeds(getDocs(query(collection(alice(), "orders"), where("uid", "==", "alice"), limit(20))));
    await assertFails(getDocs(query(collection(alice(), "orders"), limit(20))));
    await assertSucceeds(getDoc(doc(staff(), "orders/o2")));
    await assertSucceeds(getDocs(query(collection(staff(), "orders"), limit(100))));
    await assertFails(updateDoc(doc(alice(), "orders/o1"), { status: "delivered" }));
    await assertFails(updateDoc(doc(staff(), "orders/o1"), { status: "delivered" }));
    await assertFails(setDoc(doc(alice(), "orders/o3"), { uid: "alice", totalPaise: 1 }));
    await assertFails(getDoc(doc(anon(), "orders/o1")));
  });

  test("refunds are the order's to read; payment attempts are server-only", async () => {
    await assertSucceeds(getDoc(doc(alice(), "orders/o1/refunds/r1")));
    await assertSucceeds(getDoc(doc(staff(), "orders/o1/refunds/r1")));
    await assertFails(getDoc(doc(env.authenticatedContext("bob").firestore(), "orders/o1/refunds/r1")));
    await assertFails(getDoc(doc(alice(), "orders/o1/payments/SM100001-aaaaaaaa")));
    await assertFails(setDoc(doc(staff(), "orders/o1/refunds/r2"), { amountPaise: 1 }));
  });
});

describe("offers and referrals", () => {
  test("hidden and personal codes are never listable; customers see publicOffers and their own coupons", async () => {
    await assertFails(getDoc(doc(alice(), "promotions/p1")));
    await assertSucceeds(getDoc(doc(staff(), "promotions/p1")));
    for (const p of ["promoCodes/HIDDEN1", "redemptions/o1", "referralCodes/ALICE123", "counters/orders"]) {
      await assertFails(getDoc(doc(alice(), p)));
      await assertFails(getDoc(doc(staff(), p)));
    }
    await assertSucceeds(getDoc(doc(anon(), "publicOffers/p2")));
    await assertSucceeds(getDocs(query(collection(anon(), "publicOffers"), limit(50))));
    await assertFails(setDoc(doc(staff(), "publicOffers/p2"), { x: 2 }));
    await assertSucceeds(getDoc(doc(alice(), "users/alice/coupons/p3")));
    await assertFails(getDoc(doc(env.authenticatedContext("bob").firestore(), "users/alice/coupons/p3")));
    await assertFails(setDoc(doc(alice(), "users/alice/coupons/p4"), { x: 1 }));
    await assertFails(getDoc(doc(env.authenticatedContext("bob").firestore(), "referrals/bob")));
    await assertSucceeds(getDoc(doc(staff(), "referrals/bob")));
    await assertFails(setDoc(doc(alice(), "referrals/alice"), { referrerUid: "bob", status: "pending" }));
  });
});
