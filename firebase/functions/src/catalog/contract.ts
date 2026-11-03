import { z } from "zod";
import { contract } from "../shared/callable.js";
import { cleanMultiline, cleanText, v } from "../shared/validation.js";

// Owner: engineer B. Every product and variant write is a callable (clients never write products/variants), staff
// only. Brands, categories, collections and banners are plain staff writes under Rules.
const ok = z.object({});
const id = z.object({ id: z.string() });

export const saveProduct = contract(
  "saveProduct",
  z.strictObject({
    id: v.slug.nullable(), // null creates
    slug: v.slug, // on create the doc id; immutable after
    name: cleanText(120, { min: 2, mustHave: "letterOrDigit" }),
    brandId: v.slug,
    categoryId: v.slug,
    description: cleanMultiline(5000),
    specs: z.array(z.strictObject({ label: cleanText(40, { min: 1 }), value: cleanText(200, { min: 1 }) })).max(40),
    gstRateBp: v.gstRateBp.default(1800),
    hsnCode: z.string().regex(/^[0-9]{4,8}$/).optional(),
    isActive: z.boolean(),
    isFeatured: z.boolean(),
  }),
  id,
);

export const saveVariant = contract(
  "saveVariant",
  z.strictObject({
    productId: v.slug,
    id: v.docId.nullable(),
    sku: v.sku,
    name: cleanText(80, { min: 1 }),
    attributes: z.strictObject({
      ram: cleanText(20).optional(),
      storage: cleanText(20).optional(),
      color: cleanText(40).optional(),
      colorHex: v.hexColor.optional(),
    }),
    pricePaise: v.pricePaise,
    mrpPaise: v.pricePaise,
    stock: v.stock,
    isActive: z.boolean(),
    sort: z.number().int().min(0).max(1000),
  }).refine((x) => x.mrpPaise >= x.pricePaise, { message: "mrp", path: ["mrpPaise"] }),
  id,
);

/** The product's whole photo list, in order (uploads go to Storage first, under staff Storage Rules). */
export const setProductImages = contract(
  "setProductImages",
  z.strictObject({
    productId: v.slug,
    images: z.array(z.strictObject({ path: v.imagePath, color: cleanText(40, { min: 1 }).optional(), sort: z.number().int().min(0) })).max(12),
  }),
  ok,
);

/**
 * The staff catalogue's inline and bulk edits. Each edit names the value the screen showed in `expect`; an edit whose
 * row changed since (an order sold one, another phone edited it) is skipped and returned in `stale`.
 */
export const updateVariants = contract(
  "updateVariants",
  z.strictObject({
    edits: z.array(z.strictObject({
      variantId: v.docId,
      expect: z.strictObject({ stock: v.stock.optional(), pricePaise: v.pricePaise.optional() }),
      stock: v.stock.optional(),
      pricePaise: v.pricePaise.optional(),
      mrpPaise: v.pricePaise.optional(),
      isActive: z.boolean().optional(),
    })).min(1).max(500),
  }),
  z.object({ stale: z.array(z.string()) }),
);

export const setFeatured = contract("setFeatured", z.strictObject({ productIds: z.array(v.slug).min(1).max(500), featured: z.boolean() }), ok);

/** Refused once any order references the product: hide it instead. */
export const deleteProduct = contract("deleteProduct", z.strictObject({ id: v.slug }), ok);
