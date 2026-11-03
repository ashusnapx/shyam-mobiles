import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Owner: engineer B. docs/FIREBASE.md §3. St = staff write under Rules, S = server only (saveProduct, triggers).

export type CategoryKind = "phone" | "accessory";

/** categories/{slug} (St) */
export interface CategoryDoc {
  name: string;
  kind: CategoryKind;
  sort: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** brands/{slug} (St) */
export interface BrandDoc {
  name: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface ProductImage {
  path: string; // Storage key under product-images/
  color?: string;
  sort: number;
}

/** products/{slug} (S). The slug never changes after create. */
export interface ProductDoc {
  name: string;
  brandId: string;
  brandName: string;
  categoryId: string;
  categoryKind: CategoryKind;
  description: string; // ≤ 5000
  specs: { label: string; value: string }[];
  gstRateBp: number; // 0..2800, default 1800
  hsnCode?: string; // Phase 2, ^[0-9]{4,8}$
  isActive: boolean;
  isFeatured: boolean;
  images: ProductImage[]; // ≤ 12
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** variants/{autoId} (S) */
export interface VariantDoc {
  productId: string;
  productName: string;
  productActive: boolean;
  sku: string; // unique, checked in the saveProduct transaction
  name: string;
  attributes: { ram?: string; storage?: string; color?: string; colorHex?: string };
  pricePaise: number; // > 0
  mrpPaise: number; // ≥ pricePaise
  stock: number; // 0..1e6
  isActive: boolean;
  sort: number;
  lastStockChange: "order" | "staff" | "refund";
  /** +1 whenever stock goes 0 → > 0 (back-in-stock alerts key on it). Only catalog/stock.ts applyStockChange sets it. */
  restockSeq: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** collections/{slug} (St) */
export interface CollectionDoc {
  name: string;
  productIds: string[]; // ≤ 500
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** One product in catalogIndex/public, short keys to keep the doc small (D3). */
export interface CatalogCard {
  n: string; // name
  s: string; // slug
  b: string; // brandId
  bn: string; // brandName
  c: string; // categoryId
  k: CategoryKind;
  v: string; // variant names joined
  p: number; // min pricePaise of active variants
  m: number; // mrpPaise of that variant
  i: boolean; // in stock
  f: boolean; // featured
  cv: string | null; // cover image path
  col: string[]; // collection ids
  t: number; // createdAt millis
  ft?: string[]; // the "Fits" spec values (accessories: "Fits this phone"); absent when none
}

/** One variant in catalogIndex/staff, short keys (Firestore allows no arrays inside arrays, so not a tuple). */
export interface StaffVariantRow {
  id: string;
  sku: string;
  n: string; // name
  p: number; // pricePaise
  m: number; // mrpPaise
  st: number; // stock
  a: boolean; // isActive
  u: number; // updatedAt millis
}

/** catalogIndex/public (S, trigger): active products only. */
export interface PublicCatalogIndexDoc {
  cards: Record<string, CatalogCard>;
  updatedAt: Timestamp;
}

export type StaffCatalogCard = CatalogCard & { active: boolean; u: number; variants: StaffVariantRow[] };

/** catalogIndex/staff (S, trigger): every product, with its variants. */
export interface StaffCatalogIndexDoc {
  /** [active]: the product is shown; [u]: its updatedAt millis. Every variant, hidden ones too, in sort order. */
  cards: Record<string, StaffCatalogCard>;
  updatedAt: Timestamp;
}

/** users/{uid}/wishlist/{productId} (C). [waitVariant]: the back-in-stock mark (docs/FIREBASE.md §6). */
export interface WishlistDoc {
  productId: string; // = the doc id
  addedAt: Timestamp;
  waitVariant: string | null; // a variant id, '*' (any variant), or null (no alert)
}

/** banners/{id} (St; promotion banners S via savePromotion) */
export interface BannerDoc {
  title: string;
  subtitle: string;
  ctaLabel: string;
  link: string; // an app route (bannerLink rule)
  imagePath?: string;
  tone: number; // 0..5
  startsAt: Timestamp;
  endsAt?: Timestamp | null;
  sort: number;
  isActive: boolean;
  promotionId?: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export const retention: Record<string, Retention> = {
  categories: { kind: "shop" },
  brands: { kind: "shop" },
  products: { kind: "shop" },
  variants: { kind: "shop" },
  collections: { kind: "shop" },
  catalogIndex: { kind: "shop" },
  banners: { kind: "shop" },
  "users/*/wishlist": { kind: "account" },
};
