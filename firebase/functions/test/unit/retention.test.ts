import { readdirSync } from "node:fs";
import { expect, test } from "vitest";
import type { Retention } from "../../src/model/retention.js";

// docs/SECURITY.md §4.5: every collection in the data model says how long its documents live.
const dir = new URL("../../src/model/", import.meta.url);
const files = readdirSync(dir).filter((f) => f.endsWith(".ts") && f !== "retention.ts");

/** Every collection in docs/FIREBASE.md §3. */
const COLLECTIONS = [
  "users", "users/*/addresses", "users/*/notifications", "users/*/coupons", "carts", "users/*/wishlist", "devices",
  "categories", "brands", "products", "variants", "collections", "catalogIndex", "banners", "settings",
  "promotions", "promoCodes", "publicOffers", "redemptions", "rateLimits", "referralCodes", "referrals",
  "orders", "orders/*/payments", "orders/*/refunds", "repairs", "feedback", "counters",
];

test("every model file declares a retention for each of its collections", async () => {
  const all: Record<string, Retention> = {};
  for (const f of files) {
    const mod = (await import(new URL(f.replace(/\.ts$/, ".js"), dir).href)) as { retention?: Record<string, Retention> };
    expect(mod.retention, f).toBeDefined();
    Object.assign(all, mod.retention);
  }
  expect(Object.keys(all).sort()).toEqual([...COLLECTIONS].sort());
  for (const [path, r] of Object.entries(all)) if (r.kind === "ttl") expect(r.days, path).toBeGreaterThan(0);
});
