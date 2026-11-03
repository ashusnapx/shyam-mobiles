import type { Timestamp } from "firebase-admin/firestore";
import type { Retention } from "./retention.js";

// Owner: engineer A. docs/FIREBASE.md §3. C = the client writes under Rules, S = server only.

export type StaffRole = "owner" | "staff";
export type AddressId = "a0" | "a1" | "a2" | "a3" | "a4" | "a5" | "a6" | "a7" | "a8" | "a9";
export type AddressLabel = "home" | "work" | "other";

/** users/{uid} */
export interface UserDoc {
  fullName: string | null; // C, personName rule
  photoUrl?: string; // C
  phone?: string; // C on create only, must equal the token's phone_number
  role?: StaffRole; // S, mirrors the custom claim
  defaultAddressId?: AddressId; // C
  referralCode?: string; // S
  referralRewards?: Record<string, number>; // S, { [yyyymm IST]: rewards paid that month }
  consent?: { noticeVersion: number; acceptedAt: Timestamp; analytics: boolean }; // C, SECURITY §4.2
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** users/{uid}/addresses/{a0..a9} (C). stateCode: the GST state code ('23' = Madhya Pradesh). */
export interface AddressDoc {
  name: string;
  phone: string;
  line1: string;
  line2?: string;
  landmark?: string;
  city: string;
  district?: string;
  state: string;
  stateCode: string;
  pincode: string;
  label: AddressLabel;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/** devices/{fcmToken} (C, uid == auth.uid) */
export interface DeviceDoc {
  uid: string;
  platform: "android" | "ios";
  updatedAt: Timestamp;
  expireAt: Timestamp;
}

/** rateLimits/{uid} (S): rolling windows per key (shared/rateLimit.ts). */
export interface RateLimitDoc {
  [key: string]: Timestamp[] | Timestamp;
  expireAt: Timestamp;
}

export const retention: Record<string, Retention> = {
  users: { kind: "account" },
  "users/*/addresses": { kind: "account" },
  devices: { kind: "ttl", field: "expireAt", days: 270 },
  rateLimits: { kind: "ttl", field: "expireAt", days: 1 },
};
