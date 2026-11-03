import { randomUUID } from "node:crypto";
import { requireStaff } from "../shared/auth.js";
import { callable } from "../shared/callable.js";
import { db } from "../shared/db.js";
import { fail } from "../shared/errors.js";
import { audit } from "../shared/log.js";
import { doc, promotionOf } from "../orders/repository.js";
import * as c from "./contract.js";
import { bannerOf, brokenRule, mirrorOf, mirrorPath, newPromotion, type Promotion } from "./promotion.js";

// Owner: engineer C. Staff promotions (docs/FIREBASE.md §1): the promotion, its promoCodes entry, the customer mirror
// and the banner, written in one transaction. Ids are UUIDs, so /offers/{id} links keep their old format.

const TARGETS = { product: "products", category: "categories", brand: "brands", collection: "collections" } as const;

export const savePromotion = callable(c.savePromotion, async (input, req) => {
  const staff = await requireStaff(req);
  const { id: given, startsAt, endsAt, ...rest } = input;
  const id = given ?? randomUUID();
  await db().runTransaction(async (tx) => {
    const now = new Date();
    const ref = doc(`promotions/${id}`);
    let before: Promotion | null = null;
    if (given) {
      const snap = await tx.get(ref);
      if (!snap.exists) fail("NOT_FOUND");
      before = promotionOf(snap.data() ?? {});
    } else if (rest.title === undefined || rest.kind === undefined) {
      fail("INVALID_PROMOTION", rest.title === undefined ? "title" : "kind");
    }
    const sent = Object.fromEntries(Object.entries(rest).filter(([, x]) => (x as unknown) !== undefined));
    const p = {
      ...(before ?? newPromotion(now)), ...sent,
      ...(startsAt === undefined ? {} : { startsAt: new Date(startsAt) }),
      ...(endsAt === undefined ? {} : { endsAt: endsAt === null ? null : new Date(endsAt) }),
      updatedAt: now,
    } as Promotion;
    if (p.appliesTo === "order") p.targets = [];
    const rule = brokenRule(p);
    if (rule) fail("INVALID_PROMOTION", rule);
    const found = p.targets.length ? await tx.getAll(...p.targets.map((t) => doc(`${TARGETS[t.type]}/${t.id}`))) : [];
    if (found.some((s) => !s.exists)) fail("INVALID_PROMOTION", "unknown target");
    const newCode = p.code !== null && p.code !== before?.code ? p.code : null;
    if (newCode && (await tx.get(doc(`promoCodes/${newCode}`))).exists) fail("CODE_TAKEN");

    tx.set(ref, p);
    if (before?.code && before.code !== p.code) tx.delete(doc(`promoCodes/${before.code}`));
    if (newCode) tx.create(doc(`promoCodes/${newCode}`), { promotionId: id });
    const old = before && mirrorPath(id, before);
    const mirror = mirrorPath(id, p);
    if (old && old !== mirror) tx.delete(doc(old));
    if (mirror) tx.set(doc(mirror), mirrorOf(p));
    const banner = bannerOf(id, p);
    if (banner) tx.set(doc(`banners/${id}`), banner);
    else tx.delete(doc(`banners/${id}`));
  });
  audit(given ? "offers.savePromotion" : "offers.createPromotion", staff.uid, id);
  return { id };
});

/** Only a promotion no live order uses: one in use can be switched off instead (isActive false). */
export const deletePromotion = callable(c.deletePromotion, async ({ id }, req) => {
  const staff = await requireStaff(req);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(doc(`promotions/${id}`));
    if (!snap.exists) fail("NOT_FOUND");
    const p = promotionOf(snap.data() ?? {});
    if (p.usesActive > 0) fail("INVALID_PROMOTION", "in use");
    tx.delete(snap.ref);
    if (p.code) tx.delete(doc(`promoCodes/${p.code}`));
    const mirror = mirrorPath(id, p);
    if (mirror) tx.delete(doc(mirror));
    tx.delete(doc(`banners/${id}`));
  });
  audit("offers.deletePromotion", staff.uid, id);
  return {};
});
