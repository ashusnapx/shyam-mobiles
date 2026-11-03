import { FieldValue, type Transaction } from "firebase-admin/firestore";
import type { z } from "zod";
import type { BrandDoc, CategoryDoc, ProductDoc, VariantDoc } from "../model/catalog.js";
import { requireStaff } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { db } from "../shared/db.js";
import { fail } from "../shared/errors.js";
import { audit } from "../shared/log.js";
import * as c from "./contract.js";
import { productRef, readVariants, refreshIndex, variantRef } from "./repository.js";
import { applyStockChange } from "./stock.js";

// Owner: engineer B. Staff-only catalogue writes (docs/FIREBASE.md §1 row B): guard → transaction → index refresh.
// Each body is also exported as a plain function taking the input and the acting uid, so the integration tests run
// it on the emulator without a TOTP session.

type In<K extends keyof typeof c> = z.output<(typeof c)[K]["input"]>;
const now = () => FieldValue.serverTimestamp();

async function readRefs(tx: Transaction, brandId: string, categoryId: string): Promise<{ brand: BrandDoc; category: CategoryDoc }> {
  const [brand, category] = await tx.getAll(db().doc(`brands/${brandId}`), db().doc(`categories/${categoryId}`));
  if (!brand?.exists) fail("BAD_REQUEST", ["brandId"]);
  if (!category?.exists) fail("BAD_REQUEST", ["categoryId"]);
  return { brand: brand.data() as BrandDoc, category: category.data() as CategoryDoc };
}

/** Creates `products/{slug}` or edits one. The slug is the id, so it never changes; name and visibility are copied to
 * the variants in the same transaction (Rules and cart lines read them there). */
export async function saveProductAs(input: In<"saveProduct">, actorUid: string): Promise<{ id: string }> {
  const id = input.id ?? input.slug;
  if (input.id !== null && input.slug !== input.id) fail("BAD_REQUEST", ["slug"]);
  await db().runTransaction(async (tx) => {
    const ref = productRef(id);
    const existing = await tx.get(ref);
    if (input.id === null && existing.exists) fail("CODE_TAKEN", "slug");
    if (input.id !== null && !existing.exists) fail("NOT_FOUND");
    const { brand, category } = await readRefs(tx, input.brandId, input.categoryId);
    const variants = input.id === null ? [] : await readVariants(tx, id);
    const fields = {
      name: input.name,
      brandId: input.brandId,
      brandName: brand.name,
      categoryId: input.categoryId,
      categoryKind: category.kind,
      description: input.description,
      specs: input.specs,
      gstRateBp: input.gstRateBp,
      ...(input.hsnCode === undefined ? {} : { hsnCode: input.hsnCode }),
      isActive: input.isActive,
      isFeatured: input.isFeatured,
      updatedAt: now(),
    };
    if (input.id === null) tx.create(ref, { ...fields, images: [], createdAt: now() });
    else tx.update(ref, fields);
    for (const v of variants) {
      if (v.productName !== input.name || v.productActive !== input.isActive) {
        tx.update(variantRef(v.id), { productName: input.name, productActive: input.isActive, updatedAt: now() });
      }
    }
  });
  audit(input.id === null ? "catalog.createProduct" : "catalog.saveProduct", actorUid, id);
  await refreshIndex([id]);
  return { id };
}

/** Creates or edits a variant. The SKU is unique across the shop; stock goes through applyStockChange. */
export async function saveVariantAs(input: In<"saveVariant">, actorUid: string): Promise<{ id: string }> {
  const ref = input.id === null ? db().collection("variants").doc() : variantRef(input.id);
  await db().runTransaction(async (tx) => {
    const product = await tx.get(productRef(input.productId));
    if (!product.exists) fail("NOT_FOUND");
    const sameSku = await tx.get(db().collection("variants").where("sku", "==", input.sku).limit(2));
    if (sameSku.docs.some((d) => d.id !== ref.id)) fail("CODE_TAKEN", "sku");
    const current = input.id === null ? null : await tx.get(ref);
    if (current !== null && (!current.exists || current.get("productId") !== input.productId)) fail("NOT_FOUND");
    const p = product.data() as ProductDoc;
    const fields = {
      sku: input.sku,
      name: input.name,
      attributes: input.attributes,
      pricePaise: input.pricePaise,
      mrpPaise: input.mrpPaise,
      isActive: input.isActive,
      ...(input.sort === undefined ? {} : { sort: input.sort }),
    };
    if (current === null) {
      const doc: Omit<VariantDoc, "createdAt" | "updatedAt"> & Record<string, unknown> = {
        ...fields, productId: input.productId, productName: p.name, productActive: p.isActive, sort: input.sort ?? 0,
        stock: input.stock, restockSeq: 0, lastStockChange: "staff", createdAt: now(), updatedAt: now(),
      };
      tx.create(ref, doc);
    } else {
      applyStockChange(tx, ref, current.data() as VariantDoc, { set: input.stock }, "staff", now(), fields);
    }
  });
  audit(input.id === null ? "catalog.createVariant" : "catalog.saveVariant", actorUid, ref.id);
  await refreshIndex([input.productId]);
  return { id: ref.id };
}

/** The product's whole photo list, renumbered in the order given. */
export async function setProductImagesAs(input: In<"setProductImages">, actorUid: string): Promise<Record<string, never>> {
  const paths = input.images.map((i) => i.path);
  if (new Set(paths).size !== paths.length) fail("BAD_REQUEST", ["images"]);
  const images = [...input.images].sort((a, b) => a.sort - b.sort).map((i, sort) => ({ path: i.path, ...(i.color === undefined ? {} : { color: i.color }), sort }));
  await db().runTransaction(async (tx) => {
    const ref = productRef(input.productId);
    if (!(await tx.get(ref)).exists) fail("NOT_FOUND");
    tx.update(ref, { images, updatedAt: now() });
  });
  audit("catalog.setProductImages", actorUid, input.productId, { count: images.length });
  await refreshIndex([input.productId]);
  return {};
}

/**
 * The catalogue's inline and bulk edits, in one transaction. An edit whose row no longer shows the value in
 * `expect` (an order sold one, another phone edited it), or whose variant is gone, is skipped and returned in `stale`.
 */
export async function updateVariantsAs(input: In<"updateVariants">, actorUid: string): Promise<{ stale: string[] }> {
  const ids = input.edits.map((e) => e.variantId);
  if (new Set(ids).size !== ids.length) fail("BAD_REQUEST", ["edits"]);
  const stale: string[] = [];
  const touched = new Set<string>();
  await db().runTransaction(async (tx) => {
    stale.length = 0;
    touched.clear();
    const snaps = await tx.getAll(...ids.map(variantRef));
    for (const [i, e] of input.edits.entries()) {
      const snap = snaps[i];
      const v = snap?.exists ? (snap.data() as VariantDoc) : null;
      if (v === null || (e.expect.stock !== undefined && v.stock !== e.expect.stock) ||
        (e.expect.pricePaise !== undefined && v.pricePaise !== e.expect.pricePaise)) {
        stale.push(e.variantId);
        continue;
      }
      const price = e.pricePaise ?? v.pricePaise;
      const mrp = e.mrpPaise ?? v.mrpPaise;
      if (mrp < price) fail("BAD_REQUEST", [`edits.${i}.mrpPaise`]);
      const fields = {
        ...(e.pricePaise === undefined ? {} : { pricePaise: e.pricePaise }),
        ...(e.mrpPaise === undefined ? {} : { mrpPaise: e.mrpPaise }),
        ...(e.isActive === undefined ? {} : { isActive: e.isActive }),
      };
      if (e.stock !== undefined) applyStockChange(tx, variantRef(e.variantId), v, { set: e.stock }, "staff", now(), fields);
      else tx.update(variantRef(e.variantId), { ...fields, updatedAt: now() });
      touched.add(v.productId);
    }
  });
  audit("catalog.updateVariants", actorUid, null, { edits: ids.length, stale: stale.length });
  await refreshIndex(touched);
  return { stale };
}

export async function setFeaturedAs(input: In<"setFeatured">, actorUid: string): Promise<Record<string, never>> {
  const ids = [...new Set(input.productIds)];
  await db().runTransaction(async (tx) => {
    const snaps = await tx.getAll(...ids.map(productRef));
    if (snaps.some((s) => !s.exists)) fail("NOT_FOUND");
    for (const id of ids) tx.update(productRef(id), { isFeatured: input.featured, updatedAt: now() });
  });
  audit("catalog.setFeatured", actorUid, null, { products: ids.length, featured: input.featured });
  await refreshIndex(ids);
  return {};
}

/** Only a product with no variants: orders point at variants, so one that never had any was never sold. Anything else
 * is hidden instead (isActive false), which keeps past orders and their photos intact. */
export async function deleteProductAs(input: In<"deleteProduct">, actorUid: string): Promise<Record<string, never>> {
  await db().runTransaction(async (tx) => {
    const ref = productRef(input.id);
    if (!(await tx.get(ref)).exists) fail("NOT_FOUND");
    if ((await readVariants(tx, input.id)).length > 0) fail("BAD_REQUEST", ["variants"]);
    tx.delete(ref);
  });
  audit("catalog.deleteProduct", actorUid, input.id);
  await refreshIndex([input.id]);
  return {};
}

const staff = <I, O>(body: (input: I, uid: string) => Promise<O>) =>
  async (input: I, req: Parameters<typeof requireStaff>[0]) => body(input, (await requireStaff(req)).uid);

export const saveProduct = callable(c.saveProduct, staff(saveProductAs));
export const saveVariant = callable(c.saveVariant, staff(saveVariantAs));
export const setProductImages = callable(c.setProductImages, staff(setProductImagesAs));
export const updateVariants = callable(c.updateVariants, staff(updateVariantsAs));
export const setFeatured = callable(c.setFeatured, staff(setFeaturedAs));
export const deleteProduct = callable(c.deleteProduct, staff(deleteProductAs));
