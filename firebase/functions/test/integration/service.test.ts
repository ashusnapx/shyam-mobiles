import { deleteApp, initializeApp as initClient } from "firebase/app";
import { connectAuthEmulator, getAuth, signInWithEmailAndPassword } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { initializeApp } from "firebase-admin/app";
import { getAuth as adminAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, expect, test } from "vitest";

// Engineer D's callables and triggers on the emulator suite (`npm run test:int`): repairs end to end with their
// notifications, feedback, and a back-in-stock alert. Payments need the PhonePe sandbox (M3), not the emulator.

const PROJECT = "demo-shyam-mobiles";
const admin = initializeApp({ projectId: PROJECT }, "d-admin");
const db = getFirestore(admin);

async function signedIn(email: string, role?: "staff") {
  const user = await adminAuth(admin).createUser({ email, password: "secret123" }).catch(() => adminAuth(admin).getUserByEmail(email));
  if (role) {
    await adminAuth(admin).setCustomUserClaims(user.uid, { role });
    await db.doc(`users/${user.uid}`).set({ fullName: "Staff", role });
  } else {
    await db.doc(`users/${user.uid}`).set({ fullName: "Asha" });
  }
  const app = initClient({ projectId: PROJECT, apiKey: "demo" }, email);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  await signInWithEmailAndPassword(auth, email, "secret123");
  const functions = getFunctions(app, "asia-south1");
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  return { uid: user.uid, app, call: (name: string, data: unknown) => httpsCallable(functions, name)(data).then((r) => r.data as Record<string, unknown>) };
}

/** Triggers run after the write: wait for [path] to match. */
async function eventually<T>(read: () => Promise<T>, ok: (v: T) => boolean): Promise<T> {
  for (let i = 0; i < 60; i++) {
    const v = await read();
    if (ok(v)) return v;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error("timed out");
}
const kinds = async (uid: string) => (await db.collection(`users/${uid}/notifications`).get()).docs.map((d) => d.get("kind") as string);

let asha: Awaited<ReturnType<typeof signedIn>>;
let staff: Awaited<ReturnType<typeof signedIn>>;
beforeAll(async () => {
  asha = await signedIn(`asha-${String(Date.now())}@test.dev`);
  staff = await signedIn(`staff-${String(Date.now())}@test.dev`, "staff");
});
afterAll(async () => {
  await Promise.all([deleteApp(asha.app), deleteApp(staff.app)]);
});

const today = new Date(Date.now() + 330 * 60_000).toISOString().slice(0, 10);

test("a repair from booking to a declined, re-quoted and approved price, with the notifications each step sends", async () => {
  const { repairId } = await asha.call("bookRepair", {
    deviceBrand: "Samsung", deviceModel: "Galaxy A56", issue: "screen", description: "", preferredDate: today, slot: "evening",
    contactPhone: "+919876543210",
  });
  const id = String(repairId);
  expect((await db.doc(`repairs/${id}`).get()).get("number")).toMatch(/^RP\d{6}$/);
  await eventually(() => kinds(asha.uid), (k) => k.includes("repair_booked"));
  await eventually(() => kinds(staff.uid), (k) => k.includes("staff_new_repair"));

  await expect(asha.call("adminUpdateRepair", { repairId: id, status: "confirmed" })).rejects.toMatchObject({ details: { reason: "FORBIDDEN" } });
  await staff.call("adminSetRepairQuote", { repairId: id, quotePaise: 20000 });
  await expect(staff.call("adminUpdateRepair", { repairId: id, status: "in_progress" })).rejects.toMatchObject({ details: { reason: "INVALID_TRANSITION" } });
  await expect(asha.call("approveRepairQuote", { repairId: id, quotePaise: 15000 })).rejects.toMatchObject({ details: { reason: "QUOTE_CHANGED" } });
  await asha.call("approveRepairQuote", { repairId: id, quotePaise: 20000 });
  await staff.call("adminUpdateRepair", { repairId: id, status: "confirmed" });
  await staff.call("adminUpdateRepair", { repairId: id, status: "in_progress" });
  const r = (await db.doc(`repairs/${id}`).get()).data();
  expect(r).toMatchObject({ status: "in_progress", quote: { paise: 20000, status: "approved" } });
  expect((r?.events as unknown[]).length).toBe(5);
  await eventually(() => kinds(asha.uid), (k) => k.includes("repair_quote") && k.includes("repair_started"));
  await eventually(() => kinds(staff.uid), (k) => k.includes("staff_quote_approved"));
  expect(await kinds(staff.uid)).not.toContain("repair_started"); // staff aren't told what staff did

  // feedback on that repair: one per repair, a low rating tells staff
  const { id: fid } = await asha.call("sendFeedback", { kind: "repair", repairId: id, rating: 2, message: "Slow" });
  expect(fid).toBe(`repair_${id}`);
  await asha.call("sendFeedback", { kind: "repair", repairId: id, rating: 4 });
  expect((await db.doc(`feedback/${fid as string}`).get()).data()).toMatchObject({ rating: 4, status: "new", uid: asha.uid });
  await eventually(() => kinds(staff.uid), (k) => k.includes("staff_feedback_low"));
  await expect(staff.call("sendFeedback", { kind: "repair", repairId: id, rating: 5 })).rejects.toMatchObject({ details: { reason: "NOT_FOUND" } });
});

test("a restock tells each waiting customer once and clears the mark", async () => {
  await db.doc("products/bis-phone").set({ name: "Galaxy S25", isActive: true, images: [{ path: "bis-phone/a.webp", sort: 0 }] });
  const variant = db.doc("variants/bis-v1");
  await variant.set({ productId: "bis-phone", productName: "Galaxy S25", productActive: true, isActive: true, name: "8/256 Black", sku: "S25-BK", stock: 0, lastStockChange: "order", restockSeq: 1 });
  const wish = db.doc(`users/${asha.uid}/wishlist/bis-phone`);
  await wish.set({ productId: "bis-phone", addedAt: new Date(), waitVariant: "*" });
  await variant.update({ stock: 4, lastStockChange: "staff", restockSeq: 2 });
  const n = await eventually(() => db.doc(`users/${asha.uid}/notifications/bis_bis-v1_2`).get(), (s) => s.exists);
  expect(n.data()).toMatchObject({ kind: "back_in_stock", title: "Back in stock: Galaxy S25", link: "/product/bis-phone?variant=bis-v1", imagePath: "bis-phone/a.webp" });
  expect((await wish.get()).get("waitVariant")).toBeNull();
});
