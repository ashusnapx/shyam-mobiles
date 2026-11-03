import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import type { z } from "zod";
import { cleanMultiline, cleanText, v } from "../../src/shared/validation.js";
import { VECTORS_DIR } from "../vectors.js";

// test-vectors/input.json is shared with firestore.rules and the app's core/input.dart: every sample must land on
// the side its rule says.
const rules = (JSON.parse(readFileSync(`${VECTORS_DIR}input.json`, "utf8")) as {
  rules: Record<string, { valid: unknown[]; invalid: unknown[] }>;
}).rules;

const schemas: Record<string, z.ZodType> = {
  ...v,
  cleanText: cleanText(1_000_000),
  cleanTextMultiline: cleanMultiline(1_000_000),
};
/** Rules zod doesn't own: mapsUrl needs the app's place-link parser (B, Dart only). */
const NOT_IN_ZOD = new Set(["mapsUrl"]);

describe.each(Object.keys(rules))("%s", (name) => {
  const rule = rules[name]!;
  const schema = schemas[name];
  test.runIf(!NOT_IN_ZOD.has(name))("has a schema", () => {
    expect(schema).toBeDefined();
  });
  test.runIf(schema !== undefined).each(rule.valid.map((s) => [JSON.stringify(s), s]))("valid %s", (_, s) => {
    expect(schema!.safeParse(s).success).toBe(true);
  });
  test.runIf(schema !== undefined).each(rule.invalid.map((s) => [JSON.stringify(s), s]))("invalid %s", (_, s) => {
    expect(schema!.safeParse(s).success).toBe(false);
  });
});

test("typed codes are uppercased with whitespace removed", () => {
  expect(v.typedCode.parse(" diwali 10 ")).toBe("DIWALI10");
});
