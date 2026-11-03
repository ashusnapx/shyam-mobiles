import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, Timestamp, updateDoc, where } from "firebase/firestore";
import { ref, uploadBytes, deleteObject, getBytes } from "firebase/storage";
import { afterAll, beforeAll, beforeEach, describe, test } from "vitest";
import { VECTORS_DIR } from "../vectors.js";

// Engineer B's Rules sections: catalog, settings, banners, collections, wishlist, and storage.rules' product-images.
let env: RulesTestEnvironment;
const rulesFile = (f: string) => readFileSync(new URL(`../../../${f}`, import.meta.url), "utf8");
const vectors = (JSON.parse(readFileSync(`${VECTORS_DIR}input.json`, "utf8")) as { rules: Record<string, { valid: string[]; invalid: string[] }> }).rules;

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
    await setDoc(doc(db, "products/shown"), { name: "Shown", isActive: true });
    await setDoc(doc(db, "products/hidden"), { name: "Hidden", isActive: false });
    await setDoc(doc(db, "variants/v1"), { productId: "shown", isActive: true, productActive: true, stock: 1 });
    await setDoc(doc(db, "variants/v2"), { productId: "hidden", isActive: true, productActive: false, stock: 1 });
    await setDoc(doc(db, "catalogIndex/public"), { cards: {} });
    await setDoc(doc(db, "catalogIndex/staff"), { cards: {} });
  });
});

const totp = (role: string, authTime = Math.floor(Date.now() / 1000)) =>
  ({ role, auth_time: authTime, firebase: { sign_in_provider: "google.com", sign_in_second_factor: "totp" } }) as unknown as { role: string };
const staff = (authTime?: number) => env.authenticatedContext("staff", totp("staff", authTime));
const alice = () => env.authenticatedContext("alice");
const anon = () => env.unauthenticatedContext();
// The claim alone is not staff: no TOTP second factor.
const claimOnly = () => env.authenticatedContext("staff", { role: "staff" });

describe("products, variants, catalogIndex", () => {
  test("customers see only what is shown; nobody writes them from the app", async () => {
    const db = anon().firestore();
    await assertSucceeds(getDoc(doc(db, "products/shown")));
    await assertSucceeds(getDoc(doc(db, "products/missing")));
    await assertFails(getDoc(doc(db, "products/hidden")));
    await assertSucceeds(getDocs(query(collection(db, "products"), where("isActive", "==", true))));
    await assertFails(getDocs(collection(db, "products")));
    await assertSucceeds(getDoc(doc(db, "variants/v1")));
    await assertFails(getDoc(doc(db, "variants/v2")));
    await assertSucceeds(getDocs(query(collection(db, "variants"), where("productId", "==", "shown"), where("isActive", "==", true), where("productActive", "==", true))));
    await assertSucceeds(getDoc(doc(db, "catalogIndex/public")));
    await assertFails(getDoc(doc(db, "catalogIndex/staff")));
    for (const path of ["products/x", "variants/x", "catalogIndex/public"]) {
      await assertFails(setDoc(doc(staff().firestore(), path), { isActive: true }));
    }
  });
  test("staff (TOTP, role still on users/) read everything", async () => {
    const db = staff().firestore();
    await assertSucceeds(getDoc(doc(db, "products/hidden")));
    await assertSucceeds(getDocs(collection(db, "variants")));
    await assertSucceeds(getDoc(doc(db, "catalogIndex/staff")));
    await assertFails(getDoc(doc(claimOnly().firestore(), "catalogIndex/staff")));
  });
});

describe("categories, brands, collections", () => {
  const cat = { name: "Smartphones", kind: "phone", sort: 0, createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
  test("staff create and edit with valid fields; customers only read", async () => {
    await assertSucceeds(setDoc(doc(staff().firestore(), "categories/smartphones"), cat));
    await assertSucceeds(getDoc(doc(anon().firestore(), "categories/smartphones")));
    await assertSucceeds(updateDoc(doc(staff().firestore(), "categories/smartphones"), { sort: 3, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice().firestore(), "categories/x"), cat));
    await assertFails(setDoc(doc(claimOnly().firestore(), "categories/x"), cat));
    await assertFails(setDoc(doc(staff().firestore(), "categories/Bad_Slug"), cat));
    await assertFails(setDoc(doc(staff().firestore(), "categories/x"), { ...cat, kind: "tablet" }));
    await assertFails(setDoc(doc(staff().firestore(), "categories/x"), { ...cat, extra: 1 }));
    await assertFails(setDoc(doc(staff().firestore(), "categories/x"), { ...cat, updatedAt: Timestamp.fromMillis(0) }));
    await assertFails(deleteDoc(doc(staff().firestore(), "categories/smartphones")));
    await assertSucceeds(setDoc(doc(staff().firestore(), "brands/boat"), { name: "boAt", createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(staff().firestore(), "brands/x"), { name: " boAt", createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });
  test("collections hold at most 500 products", async () => {
    const group = (n: number) => ({ name: "Under ₹1,500", productIds: Array.from({ length: n }, (_, i) => `p${i}`), createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    await assertSucceeds(setDoc(doc(staff().firestore(), "collections/under-1500"), group(500)));
    await assertFails(setDoc(doc(staff().firestore(), "collections/too-big"), group(501)));
    await assertSucceeds(deleteDoc(doc(staff().firestore(), "collections/under-1500")));
  });
});

describe("banners", () => {
  const banner = (over: Record<string, unknown> = {}) => ({
    title: "Phone repairs, same day", subtitle: "At the shop", ctaLabel: "Book a repair", link: "/repairs", tone: 2,
    startsAt: Timestamp.now(), sort: 1, isActive: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
  });
  test("bannerLink follows test-vectors/input.json", async () => {
    for (const link of vectors.bannerLink!.valid) await assertSucceeds(setDoc(doc(staff().firestore(), "banners/b"), banner({ link })));
    for (const link of vectors.bannerLink!.invalid) await assertFails(setDoc(doc(staff().firestore(), "banners/b"), banner({ link })));
  });
  test("customers list active banners only; promotion banners are the server's", async () => {
    await assertSucceeds(setDoc(doc(staff().firestore(), "banners/b"), banner({ imagePath: "banners/1.webp" })));
    await assertFails(setDoc(doc(staff().firestore(), "banners/c"), banner({ imagePath: "../x.png" })));
    await assertFails(setDoc(doc(staff().firestore(), "banners/c"), banner({ promotionId: "p1" })));
    await assertSucceeds(getDocs(query(collection(anon().firestore(), "banners"), where("isActive", "==", true))));
    await assertFails(getDocs(collection(anon().firestore(), "banners")));
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), "banners/promo"), { ...banner(), promotionId: "p1", createdAt: Timestamp.now(), updatedAt: Timestamp.now() }));
    await assertFails(deleteDoc(doc(staff().firestore(), "banners/promo")));
    await assertSucceeds(deleteDoc(doc(staff().firestore(), "banners/b")));
  });
});

describe("settings", () => {
  const store = {
    deliveryFeePaise: 4900, freeDeliveryMinPaise: 99900, codEnabled: true, codMaxPaise: 2500000, onlinePaymentEnabled: true,
    storeHours: "Every day, 9 am – 10 pm", mapPin: { lat: 24.067, lng: 82.63 }, storePhotos: ["store/1.webp"],
    repairNote: "Final price after inspection.", returnsPolicy: "7 days.\nKeep the box.",
    referral: { enabled: true, friendPaise: 20000, rewardPaise: 20000, minOrderPaise: 199900, monthlyCap: 10 },
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  };
  const business = {
    tradeName: "Shyam Online Shop", brandName: "Shyam Mobiles", legalName: "Shyam Sundar Gupta", gstin: "23BXEPG0619P2ZG",
    stateCode: "23", phone: "+917987559272", email: "shyammobilesshopes7@gmail.com",
    address: { line1: "Rajeev Complex", city: "Waidhan", district: "Singrauli", state: "Madhya Pradesh", pincode: "486886" },
    businessTypes: ["retailer", "wholesaler", "distributor", "services"], invoicePrefix: "SOS",
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  };
  test("everyone reads; staff write settings/store with valid values", async () => {
    await assertSucceeds(setDoc(doc(staff().firestore(), "settings/store"), store));
    await assertSucceeds(getDoc(doc(anon().firestore(), "settings/store")));
    await assertFails(setDoc(doc(alice().firestore(), "settings/store"), store));
    await assertFails(setDoc(doc(staff().firestore(), "settings/store"), { ...store, deliveryFeePaise: -1 }));
    await assertFails(setDoc(doc(staff().firestore(), "settings/store"), { ...store, mapPin: { lat: 51.5, lng: 0 } }));
    await assertFails(setDoc(doc(staff().firestore(), "settings/store"), { ...store, storePhotos: Array(9).fill("store/1.webp") }));
    await assertFails(setDoc(doc(staff().firestore(), "settings/store"), { ...store, storePhone: "+919999999999" }));
  });
  test("settings/business: recent sign-in, a well-formed GSTIN whose state code matches, and never a PAN", async () => {
    await assertSucceeds(setDoc(doc(staff().firestore(), "settings/business"), business));
    await assertSucceeds(getDoc(doc(anon().firestore(), "settings/business")));
    await assertFails(setDoc(doc(staff(Math.floor(Date.now() / 1000) - 600).firestore(), "settings/business"), business));
    await assertFails(setDoc(doc(staff().firestore(), "settings/business"), { ...business, pan: "BXEPG0619P" }));
    await assertFails(setDoc(doc(staff().firestore(), "settings/business"), { ...business, stateCode: "09" }));
    await assertFails(setDoc(doc(staff().firestore(), "settings/business"), { ...business, gstin: "23BXEPG0619P2Z" }));
    await assertFails(setDoc(doc(staff().firestore(), "settings/business"), { ...business, phone: "7987559272" }));
    await assertFails(setDoc(doc(alice().firestore(), "settings/business"), business));
  });
});

describe("users/{uid}/wishlist/{productId}", () => {
  const heart = (productId: string, waitVariant: string | null = null) => ({ productId, addedAt: serverTimestamp(), waitVariant });
  test("only the owner saves, marks and removes; the mark is a variant id, '*' or null", async () => {
    const db = alice().firestore();
    await assertSucceeds(setDoc(doc(db, "users/alice/wishlist/shown"), heart("shown")));
    await assertSucceeds(setDoc(doc(db, "users/alice/wishlist/hidden"), heart("hidden", "*")));
    await assertSucceeds(updateDoc(doc(db, "users/alice/wishlist/shown"), { waitVariant: "v1" }));
    await assertSucceeds(getDocs(collection(db, "users/alice/wishlist")));
    await assertFails(updateDoc(doc(db, "users/alice/wishlist/shown"), { waitVariant: "../x" }));
    await assertFails(updateDoc(doc(db, "users/alice/wishlist/shown"), { addedAt: Timestamp.fromMillis(0) }));
    await assertFails(setDoc(doc(db, "users/alice/wishlist/other"), heart("shown")));
    await assertFails(setDoc(doc(db, "users/alice/wishlist/x"), { ...heart("x"), note: "hi" }));
    await assertFails(getDocs(collection(env.authenticatedContext("bob").firestore(), "users/alice/wishlist")));
    await assertFails(setDoc(doc(env.authenticatedContext("bob").firestore(), "users/alice/wishlist/y"), heart("y")));
    await assertSucceeds(deleteDoc(doc(db, "users/alice/wishlist/shown")));
  });
});

describe("storage product-images", () => {
  const webp = new Uint8Array([82, 73, 70, 70]);
  test("anyone reads; only staff upload small webp/jpeg/png photos one folder deep", async () => {
    const s = staff().storage();
    await assertSucceeds(uploadBytes(ref(s, "product-images/shown/1.webp"), webp, { contentType: "image/webp" }));
    await assertSucceeds(getBytes(ref(anon().storage(), "product-images/shown/1.webp")));
    await assertFails(uploadBytes(ref(alice().storage(), "product-images/shown/2.webp"), webp, { contentType: "image/webp" }));
    await assertFails(uploadBytes(ref(claimOnly().storage(), "product-images/shown/2.webp"), webp, { contentType: "image/webp" }));
    await assertFails(uploadBytes(ref(s, "product-images/shown/2.gif"), webp, { contentType: "image/gif" }));
    await assertFails(uploadBytes(ref(s, "product-images/shown/2.webp"), webp, { contentType: "text/html" }));
    await assertFails(uploadBytes(ref(s, "product-images/a/b/2.webp"), webp, { contentType: "image/webp" }));
    await assertFails(uploadBytes(ref(s, "product-images/shown/big.webp"), new Uint8Array(1048577), { contentType: "image/webp" }));
    await assertSucceeds(uploadBytes(ref(s, "product-images/shown/max.webp"), new Uint8Array(1048576), { contentType: "image/webp" }));
    await assertFails(uploadBytes(ref(s, "invoices/alice/o1.pdf"), webp, { contentType: "application/pdf" }));
    await assertFails(deleteObject(ref(alice().storage(), "product-images/shown/1.webp")));
    await assertSucceeds(deleteObject(ref(s, "product-images/shown/1.webp")));
  });
});
