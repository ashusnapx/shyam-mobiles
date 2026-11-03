import { execFile } from "node:child_process";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { promisify } from "node:util";
import { getApp } from "firebase-admin/app";
import { getStorage } from "firebase-admin/storage";
import { initializeApp as clientApp } from "firebase/app";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { saveProductAs, saveVariantAs, setFeaturedAs, setProductImagesAs, updateVariantsAs, deleteProductAs } from "../../src/catalog/handlers.js";
import { db } from "../../src/shared/db.js";
import { reasonOf } from "../../src/shared/errors.js";

// Engineer B on the full emulator suite: the seed script, the catalogue writes (their bodies, run as a staff uid: the
// emulator can't mint a TOTP session), the index triggers, and the photo copy script.
const run = promisify(execFile);
const SEED = new URL("../../../seed/", import.meta.url).pathname;
const fs = db;
const cards = async (which: "public" | "staff") => ((await fs().doc(`catalogIndex/${which}`).get()).get("cards") ?? {}) as Record<string, Record<string, unknown>>;
const reason = (p: Promise<unknown>) => p.then(() => null, (e: unknown) => reasonOf(e));
async function eventually(check: () => Promise<boolean>, ms = 15_000): Promise<void> {
  for (const end = Date.now() + ms; Date.now() < end; await new Promise((r) => setTimeout(r, 250))) if (await check()) return;
  throw new Error("timed out");
}

const product = { id: null, slug: "test-phone", name: "Test Phone 5G", brandId: "samsung", categoryId: "smartphones", description: "", specs: [], gstRateBp: 1800, isActive: true, isFeatured: false };
const variant = { productId: "test-phone", id: null, sku: "TEST-1", name: "8 GB", attributes: { ram: "8 GB" }, pricePaise: 1_000_000, mrpPaise: 1_200_000, stock: 0, isActive: true };

beforeAll(async () => {
  const { stdout } = await run("node", [`${SEED}seed.ts`], { env: process.env });
  expect(stdout).toMatch(/seeded \d+ docs and 35 public cards/);
}, 60_000);

describe("seed", () => {
  test("loads the sample catalogue with slugs as ids, and both indexes", async () => {
    expect((await fs().doc("products/samsung-galaxy-s25").get()).get("brandName")).toBe("Samsung");
    expect((await fs().doc("variants/sam-s25-12-256-nvy").get()).get("attributes")).toEqual({ ram: "12 GB", storage: "256 GB", color: "Navy", colorHex: "#2C3646" });
    expect((await cards("public"))["samsung-galaxy-s25"]).toMatchObject({ p: 7_499_900, i: true, f: true, k: "phone" });
    expect((await cards("staff"))["apple-iphone-15"]).toMatchObject({ i: false, active: true });
    expect((await fs().doc("settings/business").get()).data()).toMatchObject({ gstin: "23BXEPG0619P2ZG", stateCode: "23" });
    expect((await fs().doc("settings/business").get()).get("pan")).toBeUndefined();
  });
});

describe("catalogue writes", () => {
  test("a new product and variant show in the indexes when the call returns", async () => {
    expect(await saveProductAs(product, "staff")).toEqual({ id: "test-phone" });
    expect(await reason(saveProductAs(product, "staff"))).toBe("CODE_TAKEN");
    expect((await cards("staff"))["test-phone"]).toMatchObject({ active: true, variants: [] });
    expect((await cards("public"))["test-phone"]).toBeUndefined(); // no variant yet
    const { id } = await saveVariantAs(variant, "staff");
    expect(await reason(saveVariantAs({ ...variant, sku: "SAM-S25-12-256-NVY" }, "staff"))).toBe("CODE_TAKEN");
    expect((await cards("public"))["test-phone"]).toMatchObject({ p: 1_000_000, i: false, v: "8 GB" });

    // restock through the guarded edit: 0 → 3 bumps restockSeq; a stale guard is skipped
    expect(await updateVariantsAs({ edits: [{ variantId: id, expect: { stock: 0 }, stock: 3 }] }, "staff")).toEqual({ stale: [] });
    expect((await fs().doc(`variants/${id}`).get()).data()).toMatchObject({ stock: 3, restockSeq: 1, lastStockChange: "staff" });
    expect(await updateVariantsAs({ edits: [{ variantId: id, expect: { stock: 0 }, stock: 9 }, { variantId: "gone", expect: {}, stock: 1 }] }, "staff")).toEqual({ stale: [id, "gone"] });
    expect(await reason(updateVariantsAs({ edits: [{ variantId: id, expect: {}, mrpPaise: 1 }] }, "staff"))).toBe("BAD_REQUEST");
    expect((await cards("public"))["test-phone"]).toMatchObject({ i: true });

    await setProductImagesAs({ productId: "test-phone", images: [{ path: "test-phone/2.webp", sort: 5 }, { path: "test-phone/1.webp", sort: 1 }] }, "staff");
    expect((await fs().doc("products/test-phone").get()).get("images")).toEqual([{ path: "test-phone/1.webp", sort: 0 }, { path: "test-phone/2.webp", sort: 1 }]);
    await setFeaturedAs({ productIds: ["test-phone"], featured: true }, "staff");
    expect((await cards("public"))["test-phone"]).toMatchObject({ f: true, cv: "test-phone/1.webp" });

    // hiding the product hides its variants from customers and drops the public card
    await saveProductAs({ ...product, id: "test-phone", isActive: false }, "staff");
    expect((await fs().doc(`variants/${id}`).get()).get("productActive")).toBe(false);
    expect((await cards("public"))["test-phone"]).toBeUndefined();
    expect(await reason(saveProductAs({ ...product, id: "test-phone", slug: "renamed" }, "staff"))).toBe("BAD_REQUEST");
    expect(await reason(deleteProductAs({ id: "test-phone" }, "staff"))).toBe("BAD_REQUEST"); // has variants: hide instead
  });

  test("an order's stock change (any writer) reaches the index through the variant trigger", async () => {
    await fs().doc("variants/an-pc10k-blk").update({ stock: 0 });
    await eventually(async () => (await cards("public"))["anker-powercore-10000"]?.i === false);
  });

  test("the callable itself turns away a caller who isn't signed in", async () => {
    const functions = getFunctions(clientApp({ projectId: "demo-shyam-mobiles", apiKey: "demo" }, "catalog"), "asia-south1");
    connectFunctionsEmulator(functions, "127.0.0.1", 5001);
    await expect(httpsCallable(functions, "saveProduct")(product)).rejects.toMatchObject({ details: { reason: "UNAUTHORIZED" } });
  });
});

describe("copy-photos", () => {
  let server: Server;
  beforeAll(async () => {
    server = createServer((req, res) => {
      if (req.url?.endsWith("@thumb.webp") && req.url.includes("old")) {
        res.writeHead(404).end();
        return;
      }
      res.writeHead(200, { "content-type": "image/webp" }).end(Buffer.from(`photo ${req.url}`));
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    await fs().doc("products/samsung-galaxy-s25").update({ images: [{ path: "uuid1/new.webp", sort: 0 }, { path: "uuid1/old.webp", sort: 1 }] });
    await fs().doc("settings/store").update({ storePhotos: ["store/1.jpg"] });
  });
  afterAll(() => new Promise<void>((r) => { server.close(() => { r(); }); }));

  test("copies each referenced photo and its thumb under the same key, then skips them on a rerun", async () => {
    const env = { ...process.env, SOURCE: `http://127.0.0.1:${(server.address() as AddressInfo).port}/` };
    const first = await run("node", [`${SEED}copy-photos.ts`], { env });
    expect(JSON.parse(first.stdout.trim().split("\n").at(-1)!)).toMatchObject({ copied: 8, missing: 1 }); // with test-phone's two photos from above
    const bucket = (db(), getStorage(getApp())).bucket("demo-shyam-mobiles.appspot.com");
    const [body] = await bucket.file("product-images/uuid1/new@thumb.webp").download();
    expect(body.toString()).toBe("photo /uuid1/new@thumb.webp");
    const second = await run("node", [`${SEED}copy-photos.ts`], { env });
    expect(JSON.parse(second.stdout.trim().split("\n").at(-1)!)).toMatchObject({ copied: 0, skipped: 8 });
  }, 60_000);
});
