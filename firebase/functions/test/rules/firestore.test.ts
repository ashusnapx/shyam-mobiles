import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, limit, query, serverTimestamp, setDoc, Timestamp, updateDoc, where } from "firebase/firestore";
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

const owner = () => env.authenticatedContext("owner", { ...staffToken, role: "owner" }).firestore();
const asStaff = (uid: string, role: string) => env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), `users/${uid}`), { role }));

describe("users: prefs and the staff list", () => {
  test("prefs are three switches", async () => {
    await assertSucceeds(setDoc(doc(alice(), "users/alice"), { fullName: null, prefs: { crashReports: false }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(alice(), "users/alice"), { prefs: { backInStock: true, offers: false, crashReports: true }, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), "users/alice"), { prefs: { ads: true }, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), "users/alice"), { prefs: { offers: "yes" }, updatedAt: serverTimestamp() }));
  });

  test("only the owner lists staff, and only staff", async () => {
    await asStaff("owner", "owner");
    await asStaff("staff", "staff");
    const staffList = (db: ReturnType<typeof owner>) => getDocs(query(collection(db, "users"), where("role", "in", ["owner", "staff"]), limit(50)));
    await assertSucceeds(staffList(owner()));
    await assertFails(staffList(staff()));
    await assertFails(staffList(alice()));
    await assertFails(getDocs(query(collection(owner(), "users"), limit(50)))); // customers stay private
    await assertFails(getDocs(query(collection(owner(), "users"), where("role", "in", ["owner", "staff"])))); // unbounded
  });

  test("staff power needs TOTP; the dev logins stand in for it on the demo project only", async () => {
    await asStaff("staff", "staff");
    await asStaff("dev", "owner");
    const staffList = (db: ReturnType<typeof owner>) => getDocs(query(collection(db, "users"), where("role", "in", ["owner", "staff"]), limit(50)));
    const dev = (claims: Record<string, unknown>) => env.authenticatedContext("dev", { role: "owner", ...claims }).firestore();
    await assertSucceeds(staffList(dev({ firebase: { sign_in_provider: "password" } })));
    await assertFails(staffList(dev({ firebase: { sign_in_provider: "password" }, aud: "shyam-mobiles" })));
    await assertFails(staffList(dev({ firebase: { sign_in_provider: "phone" } })));
    await assertFails(staffList(dev({ firebase: { sign_in_provider: "google.com" } })));
  });
});

describe("users/{uid}/addresses", () => {
  const home = { name: "Asha Rao", phone: "+919876543210", line1: "12 Station Road", city: "Waidhan", district: "Singrauli", state: "Madhya Pradesh", stateCode: "23", pincode: "486886", label: "home", createdAt: serverTimestamp(), updatedAt: serverTimestamp() };

  test("ten fixed ids, own addresses only, with the GST state code of the state", async () => {
    await assertSucceeds(setDoc(doc(alice(), "users/alice/addresses/a0"), home));
    await assertSucceeds(setDoc(doc(alice(), "users/alice/addresses/a9"), { ...home, line2: "Near the temple", landmark: "", label: "work" }));
    await assertSucceeds(getDocs(collection(alice(), "users/alice/addresses")));
    await assertFails(setDoc(doc(alice(), "users/alice/addresses/a10"), home));
    await assertFails(setDoc(doc(alice(), "users/alice/addresses/x"), home));
    await assertFails(setDoc(doc(bob(), "users/alice/addresses/a1"), home));
    await assertFails(getDocs(collection(bob(), "users/alice/addresses")));
    await assertFails(setDoc(doc(alice(), "users/alice/addresses/a1"), { ...home, stateCode: "09" }));
    await assertFails(setDoc(doc(alice(), "users/alice/addresses/a1"), { ...home, isDefault: true }));
    await assertFails(setDoc(doc(alice(), "users/alice/addresses/a1"), Object.fromEntries(Object.entries(home).filter(([k]) => k !== "label"))));
    await assertSucceeds(updateDoc(doc(alice(), "users/alice/addresses/a0"), { city: "Singrauli", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice(), "users/alice/addresses/a0"), { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(bob(), "users/alice/addresses/a0")));
    await assertSucceeds(deleteDoc(doc(alice(), "users/alice/addresses/a0")));
  });

  // test-vectors/input.json: the Rules side of the rules zod and Dart also run.
  const vectors = (JSON.parse(readFileSync(new URL("../../../test-vectors/input.json", import.meta.url), "utf8")) as {
    rules: Record<string, { valid: unknown[]; invalid: unknown[] }>;
  }).rules;
  const fields: [rule: string, field: string][] = [["addressName", "name"], ["phone", "phone"], ["placeName", "city"], ["pincode", "pincode"], ["cleanText", "line2"], ["addressLabel", "label"]];
  // Each sample is a fresh create; a failure names the sample.
  const check = async (rule: string, write: (s: unknown) => Promise<unknown>) => {
    for (const [ok, samples] of [[true, vectors[rule]!.valid], [false, vectors[rule]!.invalid]] as const) {
      for (const s of samples) {
        await env.clearFirestore();
        await (ok ? assertSucceeds(write(s)) : assertFails(write(s))).catch((e: unknown) => {
          throw new Error(`${rule} ${ok ? "valid" : "invalid"} ${JSON.stringify(s)}: ${String(e)}`);
        });
      }
    }
  };
  test.each(fields)("%s samples land on their side (%s)", (rule, field) =>
    check(rule, (s) => setDoc(doc(alice(), "users/alice/addresses/a1"), { ...home, [field]: s })));
  test("personName samples land on their side (users.fullName)", () =>
    check("personName", (s) => setDoc(doc(alice(), "users/alice"), { fullName: s, createdAt: serverTimestamp(), updatedAt: serverTimestamp() })));
});
