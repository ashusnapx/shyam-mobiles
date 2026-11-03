import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Owner: engineer B. docs/FIREBASE.md §3. Public read, staff write under Rules (St).

/** settings/store: how the shop runs. The server enforces these (fees, COD, the payment kill switch). */
export interface StoreSettingsDoc {
  deliveryFeePaise: number;
  freeDeliveryMinPaise: number;
  codEnabled: boolean;
  codMaxPaise: number;
  onlinePaymentEnabled: boolean;
  storeHours: string;
  mapPin?: { lat: number; lng: number };
  mapsUrl?: string;
  storePhotos: string[]; // ≤ 8 Storage keys
  repairNote: string;
  returnsPolicy: string;
  referral: { enabled: boolean; friendPaise: number; rewardPaise: number; minOrderPaise: number; monthlyCap: number };
  updatedAt: Timestamp;
}

/** settings/business: the legal identity printed on invoices and the policy pages. Never the proprietor's PAN. */
export interface BusinessSettingsDoc {
  tradeName: string;
  brandName: string;
  legalName: string;
  gstin: string;
  stateCode: string; // = gstin.slice(0, 2)
  phone: string;
  email?: string;
  address: { line1: string; city: string; district: string; state: string; pincode: string };
  businessTypes: ("retailer" | "wholesaler" | "distributor" | "services")[];
  invoicePrefix: string;
  updatedAt: Timestamp;
}

export const retention: Record<string, Retention> = {
  settings: { kind: "shop" },
};
