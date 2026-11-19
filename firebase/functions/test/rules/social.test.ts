import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, serverTimestamp, setDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, test } from "vitest";

// The social section of firestore.rules (docs/SOCIAL.md). Runs under `npm run test:rules`.

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
    await setDoc(doc(db, "social/instagram"), { posts: [], updatedAt: new Date() });
    await setDoc(doc(db, "socialPosts/b1"), { status: "done", attempts: 1 });
    await setDoc(doc(db, "private/instagramToken"), { token: "fake-token" });
    await setDoc(doc(db, "settings/social"), { autoPost: false });
  });
});

const staffToken = { role: "staff", firebase: { sign_in_provider: "google.com", sign_in_second_factor: "totp" } } as unknown as { role: string };
const staff = () => env.authenticatedContext("staff", staffToken).firestore();
const alice = () => env.authenticatedContext("alice", { phone_number: "+919876543210" }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe("social", () => {
  test("social/* is public to read and closed to every client write", async () => {
    await assertSucceeds(getDoc(doc(anon(), "social/instagram")));
    await assertSucceeds(getDoc(doc(alice(), "social/instagram")));
    for (const db of [anon(), alice(), staff()]) await assertFails(setDoc(doc(db, "social/instagram"), { posts: [] }));
  });

  test("private/* is closed to everyone, staff included", async () => {
    for (const db of [anon(), alice(), staff()]) {
      await assertFails(getDoc(doc(db, "private/instagramToken")));
      await assertFails(setDoc(doc(db, "private/instagramToken"), { token: "x" }));
    }
  });

  test("socialPosts: staff read, nobody writes", async () => {
    await assertSucceeds(getDoc(doc(staff(), "socialPosts/b1")));
    await assertFails(getDoc(doc(alice(), "socialPosts/b1")));
    await assertFails(setDoc(doc(staff(), "socialPosts/b1"), { status: "done", attempts: 0 }));
  });

  test("settings/social: staff turn auto-post on; customers can't read or write it", async () => {
    await assertSucceeds(setDoc(doc(staff(), "settings/social"), { autoPost: true, updatedAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(staff(), "settings/social")));
    await assertFails(setDoc(doc(staff(), "settings/social"), { autoPost: "yes", updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(staff(), "settings/social"), { autoPost: true, extra: 1, updatedAt: serverTimestamp() }));
    await assertFails(getDoc(doc(alice(), "settings/social")));
    await assertFails(setDoc(doc(alice(), "settings/social"), { autoPost: true, updatedAt: serverTimestamp() }));
  });
});
