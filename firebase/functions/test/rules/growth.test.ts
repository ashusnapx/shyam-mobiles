import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where } from "firebase/firestore";
import { deleteObject, getBytes, ref, uploadBytes } from "firebase/storage";
import { afterAll, beforeAll, beforeEach, describe, test } from "vitest";

// Growth's Rules sections (docs/GROWTH.md §2): reviews, product stats, and storage.rules' customer photo folders.
let env: RulesTestEnvironment;
const rulesFile = (f: string) => readFileSync(new URL(`../../../${f}`, import.meta.url), "utf8");

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-shyam-mobiles",
    firestore: { rules: rulesFile("firestore.rules") },
    storage: { rules: rulesFile("storage.rules") },
  });
});
afterAll(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, "users/staff"), { role: "staff" });
    await setDoc(doc(db, "reviews/p1_alice"), { productId: "p1", uid: "alice", rating: 2, text: "Meh", hidden: false });
    await setDoc(doc(db, "reviews/p1_bob"), { productId: "p1", uid: "bob", rating: 1, text: "Call 98…", hidden: true });
    await setDoc(doc(db, "productStats/p1"), { ratingCount: 1, ratingSum: 2, stars: [0, 1, 0, 0, 0] });
    await setDoc(doc(db, "reviewIndex/public"), { cards: {} });
  });
});

const staffToken = { role: "staff", firebase: { sign_in_provider: "google.com", sign_in_second_factor: "totp" } } as unknown as { role: string };
const staff = () => env.authenticatedContext("staff", staffToken);
const alice = () => env.authenticatedContext("alice");
const bob = () => env.authenticatedContext("bob");
const anon = () => env.unauthenticatedContext();
const smsStaff = () => env.authenticatedContext("staff", { role: "staff" }); // no TOTP: no staff power

describe("reviews", () => {
  test("anyone reads visible reviews; a hidden one only its author and staff", async () => {
    await assertSucceeds(getDoc(doc(anon().firestore(), "reviews/p1_alice")));
    await assertSucceeds(getDocs(query(collection(anon().firestore(), "reviews"), where("productId", "==", "p1"), where("hidden", "==", false))));
    await assertFails(getDocs(query(collection(anon().firestore(), "reviews"), where("productId", "==", "p1"))));
    await assertFails(getDoc(doc(anon().firestore(), "reviews/p1_bob")));
    await assertFails(getDoc(doc(alice().firestore(), "reviews/p1_bob")));
    await assertSucceeds(getDoc(doc(bob().firestore(), "reviews/p1_bob")));
    await assertSucceeds(getDocs(collection(staff().firestore(), "reviews")));
    await assertFails(getDocs(collection(smsStaff().firestore(), "reviews")));
    await assertSucceeds(getDoc(doc(alice().firestore(), "reviews/p9_alice"))); // not written yet: reads as missing
    await assertSucceeds(getDocs(query(collection(bob().firestore(), "reviews"), where("uid", "==", "bob"))));
  });

  test("staff only hide or unhide; nobody writes a review from the app", async () => {
    await assertSucceeds(updateDoc(doc(staff().firestore(), "reviews/p1_alice"), { hidden: true, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(staff().firestore(), "reviews/p1_alice"), { hidden: false })); // updatedAt not stamped
    await assertFails(updateDoc(doc(staff().firestore(), "reviews/p1_alice"), { rating: 5, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(staff().firestore(), "reviews/p1_alice"), { hidden: "yes", updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(smsStaff().firestore(), "reviews/p1_bob"), { hidden: false, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(alice().firestore(), "reviews/p1_alice"), { rating: 5 }));
    await assertFails(setDoc(doc(alice().firestore(), "reviews/p2_alice"), { productId: "p2", uid: "alice", rating: 5, hidden: false }));
  });

  test("stats and the tile index: public read, no client writes", async () => {
    await assertSucceeds(getDoc(doc(anon().firestore(), "productStats/p1")));
    await assertSucceeds(getDoc(doc(anon().firestore(), "reviewIndex/public")));
    await assertFails(setDoc(doc(staff().firestore(), "productStats/p1"), { ratingCount: 99 }));
    await assertFails(setDoc(doc(alice().firestore(), "reviewIndex/public"), { cards: {} }));
  });
});

describe("storage customer photos", () => {
  const webp = new Uint8Array([82, 73, 70, 70]);
  const put = (ctx: ReturnType<typeof alice>, path: string, body = webp, contentType = "image/webp") =>
    uploadBytes(ref(ctx.storage(), path), body, { contentType });

  test("review photos: the customer uploads into their own folder; anyone reads", async () => {
    await assertSucceeds(put(alice(), "review-photos/alice/1730000000000.webp"));
    await assertSucceeds(put(alice(), "review-photos/alice/1730000000000@thumb.webp"));
    await assertSucceeds(put(alice(), "review-photos/alice/1730000000001.jpg", webp, "image/jpeg"));
    await assertSucceeds(getBytes(ref(anon().storage(), "review-photos/alice/1730000000000.webp")));
    await assertFails(put(bob(), "review-photos/alice/1730000000002.webp"));
    await assertFails(put(anon(), "review-photos/alice/1730000000002.webp"));
    await assertFails(put(alice(), "review-photos/alice/x.webp"));
    await assertFails(put(alice(), "review-photos/alice/1.png", webp, "image/png"));
    await assertFails(put(alice(), "review-photos/alice/2.webp", webp, "text/html"));
    await assertFails(put(alice(), "review-photos/alice/a/3.webp"));
    await assertFails(put(alice(), "review-photos/alice/4.webp", new Uint8Array(1048577)));
    await assertSucceeds(put(alice(), "review-photos/alice/5.webp", new Uint8Array(1048576)));
    await assertFails(deleteObject(ref(bob().storage(), "review-photos/alice/1730000000000.webp")));
    await assertSucceeds(deleteObject(ref(alice().storage(), "review-photos/alice/1730000000000.webp")));
  });

  test("exchange photos: only the customer and staff read them", async () => {
    await assertSucceeds(put(alice(), "exchange-photos/alice/1730000000000.webp"));
    await assertSucceeds(getBytes(ref(alice().storage(), "exchange-photos/alice/1730000000000.webp")));
    await assertSucceeds(getBytes(ref(staff().storage(), "exchange-photos/alice/1730000000000.webp")));
    await assertFails(getBytes(ref(bob().storage(), "exchange-photos/alice/1730000000000.webp")));
    await assertFails(getBytes(ref(anon().storage(), "exchange-photos/alice/1730000000000.webp")));
    await assertFails(getBytes(ref(smsStaff().storage(), "exchange-photos/alice/1730000000000.webp")));
    await assertFails(put(bob(), "exchange-photos/alice/1730000000001.webp"));
  });
});
