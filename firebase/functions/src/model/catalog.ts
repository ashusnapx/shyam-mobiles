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
}

/** One variant row in catalogIndex/staff: [id, sku, name, pricePaise, mrpPaise, stock, isActive]. */
export type StaffVariantRow = [string, string, string, number, number, number, boolean];

/** catalogIndex/public (S, trigger): active products only. */
export interface PublicCatalogIndexDoc {
  cards: Record<string, CatalogCard>;
  updatedAt: Timestamp;
}

/** catalogIndex/staff (S, trigger): every product, with its variants. */
export interface StaffCatalogIndexDoc {
  cards: Record<string, CatalogCard & { active: boolean; variants: StaffVariantRow[] }>;
  updatedAt: Timestamp;
}

/** wishlists/{uid} (C) */
export interface WishlistDoc {
  productIds: string[]; // ≤ 200, newest last
  updatedAt: Timestamp;
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
  wishlists: { kind: "account" },
};
