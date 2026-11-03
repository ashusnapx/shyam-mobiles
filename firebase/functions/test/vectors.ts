import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { z } from "zod";

// Loader for firebase/test-vectors/*.json (format: firebase/README.md "Test vectors"). Shared by unit tests (pure
// pricing/state modules build their inputs from `world` + `given`) and emulator integration tests (they write the docs,
// sign in as `as`, call `call`, then read the docs back).

export const VECTORS_DIR = fileURLToPath(new URL("../../test-vectors/", import.meta.url));

const docs = z.record(z.string(), z.record(z.string(), z.unknown()).nullable());

export const vectorCase = z.strictObject({
  id: z.string().regex(/^[a-z0-9][a-z0-9-]*$/),
  source: z.string().min(1),
  about: z.string().optional(),
  as: z.string(), // a users/{uid} id in world, "anon" or "system"
  given: docs.optional(),
  call: z.string(),
  input: z.record(z.string(), z.unknown()),
  expect: z.record(z.string(), z.unknown()).optional(),
  error: z.string().optional(),
  errorDetail: z.unknown().optional(),
  then: docs.optional(),
}).refine((c) => !(c.error !== undefined && c.expect !== undefined), { message: "a case expects a result or an error, not both" });

export const vectorFile = z.strictObject({
  about: z.string(),
  now: z.iso.datetime({ offset: true }),
  world: docs,
  cases: z.array(vectorCase).min(1),
  notExpressed: z.array(z.strictObject({ source: z.string(), why: z.string() })).default([]),
});

export type VectorCase = z.infer<typeof vectorCase>;
export type VectorFile = z.infer<typeof vectorFile>;

/** The call files (everything but input.json). */
export const callFiles = (): string[] =>
  readdirSync(VECTORS_DIR).filter((f) => f.endsWith(".json") && f !== "input.json").map((f) => f.replace(/\.json$/, ""));

export function loadVectors(name: string): VectorFile {
  return vectorFile.parse(JSON.parse(readFileSync(`${VECTORS_DIR}${name}.json`, "utf8")));
}

const UNIT_MS = { s: 1_000, m: 60_000, h: 3_600_000, d: 86_400_000 } as const;

/** "@now", "@now+15m", "@now-2d" → a Date relative to [now]; other values unchanged. */
export function resolveTime(value: unknown, now: Date): unknown {
  if (typeof value !== "string" || !value.startsWith("@now")) return value;
  const m = /^@now(?:([+-])(\d+)([smhd]))?$/.exec(value);
  if (!m) throw new Error(`bad time: ${value}`);
  const [, sign, n, unit] = m;
  if (sign === undefined || n === undefined || unit === undefined) return now;
  return new Date(now.getTime() + (sign === "-" ? -1 : 1) * Number(n) * UNIT_MS[unit as keyof typeof UNIT_MS]);
}

/** [value] with every "@now…" string replaced by its Date, deeply. */
export function resolveTimes<T>(value: T, now: Date): T {
  if (Array.isArray(value)) return value.map((v: unknown) => resolveTimes(v, now)) as T;
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, resolveTimes(v, now)])) as T;
  }
  return resolveTime(value, now) as T;
}

/** The docs a case starts from: world, then `given` on top (a given doc replaces the world doc; null removes it). */
export function startingDocs(file: VectorFile, c: VectorCase): Record<string, Record<string, unknown>> {
  const merged: Record<string, Record<string, unknown> | null> = { ...file.world, ...c.given };
  const now = new Date(file.now);
  return Object.fromEntries(
    Object.entries(merged).flatMap(([path, doc]) => (doc === null ? [] : [[path, resolveTimes(doc, now)]])),
  );
}
