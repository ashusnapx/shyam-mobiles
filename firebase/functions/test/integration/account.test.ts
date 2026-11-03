import { initializeApp as initAdmin } from "firebase-admin/app";
import { getAuth as adminAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInWithCustomToken, signInWithEmailAndPassword } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { afterAll, expect, test } from "vitest";

// The account callables on the emulator suite (docs/SECURITY.md §2.2, §4.6, §4.7). The Admin SDK seeds data; the web
// SDK signs in and calls, as the app does.
const project = "demo-shyam-mobiles";
const admin = initAdmin({ projectId: project }, "admin");
const fs = getFirestore(admin);
const auth = adminAuth(admin);
const apps: ReturnType<typeof initializeApp>[] = [];
afterAll(() => Promise.all(apps.map((a) => deleteApp(a))));

function client() {
  const app = initializeApp({ projectId: project, apiKey: "demo" }, `c${apps.length}`);
  apps.push(app);
  const a = getAuth(app);
  connectAuthEmulator(a, "http://127.0.0.1:9099", { disableWarnings: true });
  const f = getFunctions(app, "asia-south1");
  connectFunctionsEmulator(f, "127.0.0.1", 5001);
  return { auth: a, call: (name: string, data: unknown = {}) => httpsCallable(f, name)(data).then((r) => r.data) };
}
const reasonOf = (p: Promise<unknown>) => p.then(() => "ok", (e: unknown) => (e as { details?: { reason?: string } }).details?.reason);

test("deleteAccount waits for open orders, then keeps orders anonymised and deletes the rest", async () => {
  const uid = "del-1";
  await auth.createUser({ uid, phoneNumber: "+919800000001" });
  await fs.doc(`users/${uid}`).set({ fullName: "Asha Rao" });
  await fs.doc(`users/${uid}/addresses/a0`).set({ city: "Waidhan" });
  await fs.doc(`carts/${uid}`).set({ lines: {} });
  await fs.doc("devices/tok-del-1").set({ uid });
  await fs.doc("orders/del-o1").set({ uid, status: "delivered", paymentStatus: "paid" });
  await fs.doc("orders/del-o2").set({ uid, status: "confirmed", paymentStatus: "pending" });
  await fs.doc("feedback/order_del-o1").set({ uid, kind: "order" });
  const c = client();
  await signInWithCustomToken(c.auth, await auth.createCustomToken(uid));

  expect(await reasonOf(c.call("deleteAccount"))).toBe("ACTIVE_ORDERS");
  expect((await fs.doc(`users/${uid}`).get()).exists).toBe(true);

  await fs.doc("orders/del-o2").update({ status: "cancelled", paymentStatus: "failed" });
  expect(await reasonOf(c.call("deleteAccount"))).toBe("ok");
  for (const path of [`users/${uid}`, `users/${uid}/addresses/a0`, `carts/${uid}`, "devices/tok-del-1", "feedback/order_del-o1"]) {
    expect((await fs.doc(path).get()).exists, path).toBe(false);
  }
  expect((await fs.doc("orders/del-o1").get()).get("uid")).toBeNull();
  await expect(auth.getUser(uid)).rejects.toMatchObject({ code: "auth/user-not-found" });
});

test("exportMyData returns the caller's data once a day", async () => {
  const uid = "exp-1";
  await auth.createUser({ uid });
  await fs.doc(`users/${uid}`).set({ fullName: "Ravi Kumar", createdAt: new Date("2026-11-01T00:00:00Z") });
  await fs.doc("orders/exp-o1").set({ uid, number: "SM100009" });
  await fs.doc("orders/exp-other").set({ uid: "someone-else", number: "SM100010" });
  const c = client();
  await signInWithCustomToken(c.auth, await auth.createCustomToken(uid));
  const { data } = (await c.call("exportMyData")) as { data: { profile: { fullName: string; createdAt: string }; orders: { number: string }[] } };
  expect(data.profile).toMatchObject({ fullName: "Ravi Kumar", createdAt: "2026-11-01T00:00:00.000Z" });
  expect(data.orders.map((o) => o.number)).toEqual(["SM100009"]);
  expect(await reasonOf(c.call("exportMyData"))).toBe("RATE_LIMITED");
});

test("the shop's phone claims the owner role once; the owner adds and removes staff by phone", async () => {
  await fs.doc("settings/business").set({ phone: "+917987559272" });
  // A dev login (email/password): on the demo project it stands in for Google + TOTP (firebase/README.md).
  await auth.createUser({ uid: "own-1", email: "owner@dev.test", password: "dev-pass-1", phoneNumber: "+917987559272" });
  await auth.createUser({ uid: "own-2", email: "other@dev.test", password: "dev-pass-2", phoneNumber: "+919800000002" });
  await auth.createUser({ uid: "stf-1", phoneNumber: "+919800000003" });
  const other = client();
  await signInWithEmailAndPassword(other.auth, "other@dev.test", "dev-pass-2");
  expect(await reasonOf(other.call("claimOwner"))).toBe("FORBIDDEN"); // not the shop's phone

  const owner = client();
  await signInWithEmailAndPassword(owner.auth, "owner@dev.test", "dev-pass-1");
  expect(await owner.call("claimOwner")).toEqual({ role: "owner" });
  expect((await auth.getUser("own-1")).customClaims).toMatchObject({ role: "owner" });
  expect((await fs.doc("users/own-1").get()).get("role")).toBe("owner");
  await owner.auth.currentUser!.getIdToken(true); // the app refreshes its token when users/{uid}.role changes

  expect(await reasonOf(other.call("setRole", { phone: "+919800000003", role: "staff" }))).toBe("FORBIDDEN");
  expect(await owner.call("setRole", { phone: "+919800000003", role: "staff" })).toEqual({ uid: "stf-1" });
  expect((await auth.getUser("stf-1")).customClaims).toMatchObject({ role: "staff" });
  expect((await fs.doc("users/stf-1").get()).get("role")).toBe("staff");
  expect(await reasonOf(owner.call("setRole", { phone: "+917987559272", role: null }))).toBe("FORBIDDEN"); // not yourself
  expect(await reasonOf(owner.call("setRole", { phone: "+919899999999", role: "staff" }))).toBe("NOT_FOUND");

  await owner.call("setRole", { phone: "+919800000003", role: null });
  expect((await auth.getUser("stf-1")).customClaims?.role).toBeUndefined();
  expect((await fs.doc("users/stf-1").get()).get("role")).toBeUndefined();
  expect(await reasonOf(other.call("claimOwner"))).toBe("FORBIDDEN");
});
