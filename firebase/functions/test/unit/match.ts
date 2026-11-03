import { expect } from "vitest";

/** The vectors' deep-partial match (firebase/README.md "Test vectors"): arrays element by element with the same
 * length, objects by the expected keys only, null = absent or null, Dates by instant. */
export function matches(actual: unknown, want: unknown, at = "$"): void {
  if (want === null) {
    expect(actual ?? null, at).toBeNull();
  } else if (Array.isArray(want)) {
    expect(Array.isArray(actual), at).toBe(true);
    expect((actual as unknown[]).length, `${at}.length`).toBe(want.length);
    want.forEach((w, i) => { matches((actual as unknown[])[i], w, `${at}[${String(i)}]`); });
  } else if (want instanceof Date) {
    expect(actual instanceof Date ? actual.getTime() : actual, at).toBe(want.getTime());
  } else if (typeof want === "object") {
    expect(actual, at).toBeTypeOf("object");
    for (const [k, w] of Object.entries(want)) matches((actual as Record<string, unknown> | undefined)?.[k], w, `${at}.${k}`);
  } else {
    expect(actual, at).toEqual(want);
  }
}
