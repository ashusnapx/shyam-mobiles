import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, Timestamp, updateDoc, where } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, test } from "vitest";

// Engineer D's Rules sections: repairs, feedback, notifications (ports of supabase/tests/rls.test.sql and
// repair_flow.test.sql's direct-write checks). Runs under `npm run test:rules`.

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
    await setDoc(doc(db, "repairs/r1"), { uid: "alice", status: "requested", number: "RP100001" });
    await setDoc(doc(db, "feedback/order_o1"), { uid: "alice", kind: "order", rating: 4, message: "", status: "new" });
    await setDoc(doc(db, "users/alice/notifications/n1"), { kind: "order_update", title: "Hi", body: "", link: "/orders/o1", readAt: null });
  });
});

const alice = () => env.authenticatedContext("alice").firestore();
const bob = () => env.authenticatedContext("bob").firestore();
const staffToken = { role: "staff", firebase: { sign_in_provider: "google.com", sign_in_second_factor: "totp" } } as unknown as { role: string };
const staff = () => env.authenticatedContext("staff", staffToken).firestore();
const smsStaff = () => env.authenticatedContext("staff", { role: "staff" }).firestore(); // no TOTP: no staff power

describe("repairs", () => {
  test("the owner and staff read; nobody writes", async () => {
    await assertSucceeds(getDoc(doc(alice(), "repairs/r1")));
    await assertSucceeds(getDocs(query(collection(alice(), "repairs"), where("uid", "==", "alice"))));
    await assertSucceeds(getDocs(collection(staff(), "repairs")));
    await assertFails(getDoc(doc(bob(), "repairs/r1")));
    await assertFails(getDocs(collection(alice(), "repairs")));
    await assertFails(getDoc(doc(smsStaff(), "repairs/r1")));
    await assertFails(updateDoc(doc(alice(), "repairs/r1"), { status: "confirmed" }));
    await assertFails(updateDoc(doc(staff(), "repairs/r1"), { status: "completed" }));
    await assertFails(setDoc(doc(alice(), "repairs/r2"), { uid: "alice", status: "requested" }));
  });
});

describe("feedback", () => {
  test("staff move it along and keep a note; the customer only reads their own", async () => {
    await assertSucceeds(getDoc(doc(alice(), "feedback/order_o1")));
    await assertFails(getDoc(doc(bob(), "feedback/order_o1")));
    await assertSucceeds(updateDoc(doc(staff(), "feedback/order_o1"), { status: "seen", adminNote: "Called her", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(staff(), "feedback/order_o1"), { rating: 5, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(staff(), "feedback/order_o1"), { status: "deleted", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(staff(), "feedback/order_o1"), { status: "seen" })); // updatedAt not stamped
    await assertFails(updateDoc(doc(alice(), "feedback/order_o1"), { status: "resolved", updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), "feedback/x"), { uid: "alice", kind: "general", message: "hi", status: "new" }));
  });
});

describe("users/{uid}/notifications", () => {
  test("the owner reads, marks read with the server's time and deletes; nothing else", async () => {
    await assertSucceeds(getDocs(collection(alice(), "users/alice/notifications")));
    await assertFails(getDocs(collection(bob(), "users/alice/notifications")));
    await assertFails(getDocs(collection(staff(), "users/alice/notifications")));
    await assertFails(updateDoc(doc(alice(), "users/alice/notifications/n1"), { readAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(doc(alice(), "users/alice/notifications/n1"), { title: "Free phone", readAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(alice(), "users/alice/notifications/n1"), { readAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), "users/alice/notifications/n2"), { kind: "order_update", title: "x", body: "", link: "/orders/x", readAt: null }));
    await assertFails(deleteDoc(doc(bob(), "users/alice/notifications/n1")));
    await assertSucceeds(deleteDoc(doc(alice(), "users/alice/notifications/n1")));
  });
});
