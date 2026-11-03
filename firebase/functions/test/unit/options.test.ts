import { afterEach, expect, test, vi } from "vitest";

// App Check starts in monitor mode (docs/SECURITY.md §2.1): ENFORCE_APP_CHECK flips it on every real project at once.
// The emulator's demo project never enforces (no App Check backend), and replay protection is on from the start.
afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

test("callables follow the one switch outside the emulator; replay protection is on regardless", async () => {
  vi.stubEnv("GCLOUD_PROJECT", "shyam-mobiles");
  const o = await import("../../src/shared/options.js");
  expect(o.CALLABLE.enforceAppCheck).toBe(o.ENFORCE_APP_CHECK);
  expect(o.REPLAY_PROTECTED.consumeAppCheckToken).toBe(true);
  expect(o.REGION).toBe("asia-south1");
});

test("monitor mode until the owner flips it after the 7-day watch", async () => {
  vi.stubEnv("GCLOUD_PROJECT", "shyam-mobiles");
  expect((await import("../../src/shared/options.js")).ENFORCE_APP_CHECK).toBe(false);
});

test("an unknown project is treated as production", async () => {
  vi.stubEnv("GCLOUD_PROJECT", "");
  const o = await import("../../src/shared/options.js");
  expect(o.IS_DEMO_PROJECT).toBe(false);
  expect(o.REPLAY_PROTECTED.consumeAppCheckToken).toBe(true);
});

test("the demo project (emulators) never enforces or consumes", async () => {
  vi.stubEnv("GCLOUD_PROJECT", "demo-shyam-mobiles");
  const o = await import("../../src/shared/options.js");
  expect(o.CALLABLE.enforceAppCheck).toBe(false);
  expect(o.REPLAY_PROTECTED.consumeAppCheckToken).toBe(false);
});

test("the dev logins' password sessions count as staff sessions on the demo project only", async () => {
  const password = { firebase: { sign_in_provider: "password" } } as never;
  vi.stubEnv("GCLOUD_PROJECT", "demo-shyam-mobiles");
  expect((await import("../../src/shared/auth.js")).isStaffSession(password)).toBe(true);
  vi.resetModules();
  vi.stubEnv("GCLOUD_PROJECT", "shyam-mobiles");
  const real = await import("../../src/shared/auth.js");
  expect(real.isStaffSession(password)).toBe(false);
  expect(real.isStaffSession({ firebase: { sign_in_provider: "phone" } } as never)).toBe(false);
  expect(real.isStaffSession({ firebase: { sign_in_provider: "google.com", sign_in_second_factor: "totp" } } as never)).toBe(true);
});
