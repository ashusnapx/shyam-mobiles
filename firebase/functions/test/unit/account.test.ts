import { Timestamp } from "firebase-admin/firestore";
import { expect, test } from "vitest";
import { blocksDeletion, mayClaimOwner, plain } from "../../src/account/policy.js";

// The account rules without an emulator (docs/SECURITY.md §4.6–4.7, docs/FIREBASE.md §4).

test("an open order or repair, or a paid cancelled order still owed its refund, blocks deletion", () => {
  const done = [{ status: "delivered", paymentStatus: "paid" }, { status: "refunded", paymentStatus: "refunded" }, { status: "cancelled", paymentStatus: "failed" }] as const;
  expect(blocksDeletion(done, [{ status: "completed" }, { status: "cancelled" }])).toBe(false);
  expect(blocksDeletion([], [])).toBe(false);
  for (const status of ["pending_payment", "confirmed", "packed", "shipped"] as const) {
    expect(blocksDeletion([...done, { status, paymentStatus: "pending" }], []), status).toBe(true);
  }
  expect(blocksDeletion([{ status: "cancelled", paymentStatus: "paid" }], [])).toBe(true);
  for (const status of ["requested", "confirmed", "in_progress", "ready"] as const) {
    expect(blocksDeletion(done, [{ status }]), status).toBe(true);
  }
});

test("only the shop's verified phone claims the shop, and only while nobody else owns it", () => {
  const shop = "+917987559272";
  const me = { uid: "u1", phone: shop };
  expect(mayClaimOwner(me, shop, [])).toBe(true);
  expect(mayClaimOwner(me, shop, ["u1"])).toBe(true); // a retry after the claim half-finished
  expect(mayClaimOwner(me, shop, ["u2"])).toBe(false);
  expect(mayClaimOwner({ uid: "u1", phone: "+919876543210" }, shop, [])).toBe(false);
  expect(mayClaimOwner({ uid: "u1", phone: undefined }, shop, [])).toBe(false);
  expect(mayClaimOwner({ uid: "u1", phone: undefined }, undefined, [])).toBe(false); // settings/business missing
});

test("the export turns Timestamps into ISO strings and keeps everything else", () => {
  const at = Timestamp.fromMillis(Date.UTC(2026, 10, 3, 6, 30));
  expect(plain({ fullName: "Asha", consent: { acceptedAt: at, analytics: false }, events: [{ at }], n: 1, x: null }))
    .toEqual({ fullName: "Asha", consent: { acceptedAt: "2026-11-03T06:30:00.000Z", analytics: false }, events: [{ at: "2026-11-03T06:30:00.000Z" }], n: 1, x: null });
});
