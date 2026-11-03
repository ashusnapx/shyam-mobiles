import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, Timestamp, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, test } from "vitest";

// Runs under `npm run test:rules` (firebase emulators:exec sets FIRESTORE_EMULATOR_HOST). Each owner adds a
// describe() for their section; ports of supabase/tests/rls.test.sql and attacks.test.sql belong here.

let env: RulesTestEnvironment;
const days = (n: number) => Timestamp.fromMillis(Date.now() + n * 86_400_000);

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-shyam-mobiles",
    firestore: { rules: readFileSync(new URL("../../../firestore.rules", import.meta.url), "utf8") },
  });
});
afterAll(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const alice = () => env.authenticatedContext("alice", { phone_number: "+919876543210" }).firestore();
const bob = () => env.authenticatedContext("bob").firestore();
// A TOTP session (the SDK's token type predates sign_in_second_factor).
const staffToken = { role: "staff", firebase: { sign_in_provider: "google.com", sign_in_second_factor: "totp" } } as unknown as { role: string };
const staff = () => env.authenticatedContext("staff", staffToken).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe("deny by default", () => {
  test("paths no section allows are closed, even to staff", async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), "users/staff"), { role: "staff" });
      await setDoc(doc(c.firestore(), "secrets/x"), { a: 1 });
    });
    await assertFails(getDoc(doc(staff(), "secrets/x")));
    await assertFails(setDoc(doc(staff(), "secrets/y"), { a: 1 }));
    await assertFails(getDoc(doc(anon(), "secrets/x")));
  });
});

describe("users/{uid}", () => {
  const profile = { fullName: "Alice Rao", createdAt: serverTimestamp(), updatedAt: serverTimestamp() };

  test("a customer creates and edits only their own profile", async () => {
    await assertSucceeds(setDoc(doc(alice(), "users/alice"), { ...profile, phone: "+919876543210" }));
    await assertSucceeds(updateDoc(doc(alice(), "users/alice"), { fullName: "राम कुमार", defaultAddressId: "a3", updatedAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(alice(), "users/alice")));
    await assertFails(getDoc(doc(bob(), "users/alice")));
    await assertFails(setDoc(doc(bob(), "users/alice"), profile));
    await assertFails(getDocs(collection(alice(), "users")));
  });

  test("server fields, a foreign phone and bad names are refused", async () => {
    await assertFails(setDoc(doc(alice(), "users/alice"), { ...profile, role: "owner" }));
    await assertFails(setDoc(doc(alice(), "users/alice"), { ...profile, phone: "+919999999999" }));
    await assertFails(setDoc(doc(alice(), "users/alice"), { ...profile, fullName: "Ravi 2" }));
    await assertFails(setDoc(doc(alice(), "users/alice"), { ...profile, fullName: " Alice" }));
    await assertFails(setDoc(doc(alice(), "users/alice"), { ...profile, createdAt: Timestamp.fromMillis(0) }));
    await assertSucceeds(setDoc(doc(alice(), "users/alice"), profile));
    await assertFails(updateDoc(doc(alice(), "users/alice"), { role: "staff", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), "users/alice"), { referralCode: "FREE1234", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), "users/alice"), { defaultAddressId: "a10", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), "users/alice"), { fullName: "Alice" })); // updatedAt not stamped
    await assertFails(deleteDoc(doc(alice(), "users/alice")));
  });

  test("consent is recorded with the server's time", async () => {
    await assertSucceeds(setDoc(doc(alice(), "users/alice"), { ...profile, consent: { noticeVersion: 1, acceptedAt: serverTimestamp(), analytics: false } }));
    await assertFails(updateDoc(doc(alice(), "users/alice"), { consent: { noticeVersion: 1, acceptedAt: Timestamp.fromMillis(0), analytics: true }, updatedAt: serverTimestamp() }));
  });
});

describe("devices/{token}", () => {
  const device = (uid: string) => ({ uid, platform: "android", updatedAt: serverTimestamp(), expireAt: days(270 - 1) });

  test("a phone registers its token for the signed-in user only", async () => {
    await assertSucceeds(setDoc(doc(alice(), "devices/tok1"), device("alice")));
    await assertSucceeds(getDoc(doc(alice(), "devices/tok1")));
    await assertFails(getDoc(doc(bob(), "devices/tok1")));
    await assertFails(setDoc(doc(bob(), "devices/tok2"), device("alice")));
    await assertFails(setDoc(doc(alice(), "devices/tok3"), { ...device("alice"), expireAt: days(400) }));
    await assertFails(setDoc(doc(alice(), "devices/tok4"), { ...device("alice"), platform: "web" }));
    await assertFails(getDocs(collection(alice(), "devices")));
  });

  test("signing in on the same phone takes the token over; only the holder deletes it", async () => {
    await assertSucceeds(setDoc(doc(alice(), "devices/tok1"), device("alice")));
    await assertFails(deleteDoc(doc(bob(), "devices/tok1")));
    await assertSucceeds(setDoc(doc(bob(), "devices/tok1"), device("bob")));
    await assertSucceeds(deleteDoc(doc(bob(), "devices/tok1")));
  });
});
