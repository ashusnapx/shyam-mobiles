// FROZEN after Phase 0 (docs/FIREBASE.md §7): one line per domain, in this order. Add a function by exporting it from
// its domain's index.ts; never edit this file. shared/options.js comes first so its global options apply to all.
import "./shared/options.js";

export * from "./health/index.js";
export * from "./account/index.js";
export * from "./catalog/index.js";
export * from "./orders/index.js";
export * from "./offers/index.js";
export * from "./referrals/index.js";
export * from "./repairs/index.js";
export * from "./feedback/index.js";
export * from "./notifications/index.js";
export * from "./payments/index.js";
