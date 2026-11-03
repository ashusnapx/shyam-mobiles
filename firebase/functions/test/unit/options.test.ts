import { afterEach, expect, test, vi } from "vitest";

// App Check is enforced on every real project; only the emulator's demo project skips it (no App Check backend).
afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

test("callables enforce App Check outside the emulator", async () => {
  vi.stubEnv("GCLOUD_PROJECT", "shyam-mobiles");
  const o = await import("../../src/shared/options.js");
  expect(o.CALLABLE.enforceAppCheck).toBe(true);
  expect(o.REPLAY_PROTECTED.consumeAppCheckToken).toBe(true);
  expect(o.REGION).toBe("asia-south1");
});

test("an unknown project is treated as production", async () => {
  vi.stubEnv("GCLOUD_PROJECT", "");
  expect((await import("../../src/shared/options.js")).CALLABLE.enforceAppCheck).toBe(true);
});

test("the demo project (emulators) skips it", async () => {
  vi.stubEnv("GCLOUD_PROJECT", "demo-shyam-mobiles");
  expect((await import("../../src/shared/options.js")).CALLABLE.enforceAppCheck).toBe(false);
});
