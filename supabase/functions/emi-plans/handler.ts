import { json } from "../_shared/http.ts";
import { razorpay } from "../_shared/razorpay.ts";

/** One bank and tenure. `rate`: the bank's yearly interest in percent; `no_cost`: the shop pays it (subvention). */
export type EmiPlan = { bank: string; name: string; months: number; rate: number; min_paise: number; no_cost: boolean };

// Card EMI issuers that the methods reply doesn't name (its netbanking list names the rest).
const NAMES: Record<string, string> = {
  HDFC: "HDFC Bank", ICIC: "ICICI Bank", UTIB: "Axis Bank", SBIN: "SBI Card", KKBK: "Kotak Mahindra Bank",
  AMEX: "American Express", CITI: "Citibank", HSBC: "HSBC", SCBL: "Standard Chartered", RATN: "RBL Bank",
  INDB: "IndusInd Bank", YESB: "Yes Bank", IDFB: "IDFC FIRST Bank", BARB: "Bank of Baroda", FDRL: "Federal Bank",
  AUBL: "AU Small Finance Bank", ONECARD: "OneCard", BAJAJ: "Bajaj Finserv",
};

type Option = { duration?: unknown; interest?: unknown; min_amount?: unknown; subvention?: unknown };
type Methods = {
  emi?: unknown;
  emi_subvention?: unknown;
  emi_options?: Record<string, Option[]>;
  emi_plans?: Record<string, { min_amount?: unknown; plans?: Record<string, unknown> }>;
  netbanking?: Record<string, unknown>;
};

// Razorpay's methods reply -> one plan per bank and tenure (the cheapest when a bank lists one twice), by bank, then
// months. `emi_options` carries who pays the interest; older accounts send only `emi_plans`. No EMI on: [].
export function plansFrom(m: Methods): EmiPlan[] {
  if (m?.emi !== true) return [];
  const name = (bank: string) => NAMES[bank] ?? (typeof m.netbanking?.[bank] === "string" ? m.netbanking[bank] as string : bank);
  const raw: [string, Option][] = [];
  for (const [bank, list] of Object.entries(m.emi_options ?? {})) {
    for (const o of Array.isArray(list) ? list : []) raw.push([bank, o]);
  }
  if (!raw.length) {
    for (const [bank, p] of Object.entries(m.emi_plans ?? {})) {
      for (const [months, rate] of Object.entries(p?.plans ?? {})) {
        raw.push([bank, { duration: Number(months), interest: rate, min_amount: p.min_amount, subvention: m.emi_subvention }]);
      }
    }
  }
  const best = new Map<string, EmiPlan>();
  for (const [bank, o] of raw) {
    const months = Number(o.duration), rate = Number(o.interest), min = Number(o.min_amount);
    if (!/^[A-Z0-9_]{2,20}$/.test(bank) || !Number.isInteger(months) || months < 2 || months > 60) continue;
    if (!(rate >= 0 && rate < 60) || !Number.isInteger(min) || min < 0) continue;
    const plan = { bank, name: name(bank), months, rate, min_paise: min, no_cost: o.subvention === "merchant" };
    const key = `${bank}/${months}`, seen = best.get(key);
    if (!seen || (plan.no_cost && !seen.no_cost) || (plan.no_cost === seen.no_cost && plan.rate < seen.rate)) best.set(key, plan);
  }
  return [...best.values()].sort((a, b) => a.name.localeCompare(b.name) || a.months - b.months);
}

const DAY = 86_400_000;
let cache: { at: number; plans: EmiPlan[] } | null = null;
export const forgetCache = () => (cache = null);

// {} -> {plans}. The same for every caller and slow to change, so one Razorpay call a day per instance.
export async function emiPlans(now = Date.now()): Promise<Response> {
  if (!cache || now - cache.at > DAY) {
    cache = { at: now, plans: plansFrom(await razorpay<Methods>("/methods", undefined, { keyOnly: true })) };
  }
  return json({ plans: cache.plans });
}
