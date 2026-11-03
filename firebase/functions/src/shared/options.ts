import { setGlobalOptions } from "firebase-functions/v2";

// Runtime options, set once (docs/FIREBASE.md D1, §2; docs/SECURITY.md §2.1, §2.6). Imported first by src/index.ts and
// by shared/callable.ts, so every function definition sees them.

export const REGION = "asia-south1";

/** `demo-*` projects exist only in the emulator suite. GCLOUD_PROJECT is reserved, so no .env file can fake it. */
export const IS_DEMO_PROJECT = (process.env.GCLOUD_PROJECT ?? "").startsWith("demo-");

setGlobalOptions({ region: REGION, memory: "256MiB", timeoutSeconds: 60, concurrency: 80, maxInstances: 10 });

/**
 * Every callable. App Check is enforced everywhere but the emulator, whose demo project has no App Check backend to
 * mint tokens for the app (tests cover the option itself).
 */
export const CALLABLE = { cors: false, enforceAppCheck: !IS_DEMO_PROJECT, maxInstances: 10, timeoutSeconds: 30 } as const;

/** placeOrder, createPayment, startRefund, setRole, deleteAccount, adminDeleteAccount: a token works once. */
export const REPLAY_PROTECTED = { ...CALLABLE, consumeAppCheckToken: !IS_DEMO_PROJECT } as const;

/** Payment callables and the webhook: fewer instances, so a flood can't run up the bill (SECURITY §2.6). */
export const PAYMENTS = { maxInstances: 5 } as const;

/** Firestore triggers and the schedule. */
export const BACKGROUND = { maxInstances: 5, timeoutSeconds: 120 } as const;
