import { initializeApp } from "firebase/app";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { expect, test } from "vitest";

// Runs under `npm run test:int` (the full emulator suite). The api_e2e.py port grows here, one file per domain.
const app = initializeApp({ projectId: "demo-shyam-mobiles", apiKey: "demo" });
const functions = getFunctions(app, "asia-south1");
connectFunctionsEmulator(functions, "127.0.0.1", 5001);

test("health answers from asia-south1", async () => {
  const res = await httpsCallable(functions, "health")({});
  expect(res.data).toMatchObject({ ok: true, region: "asia-south1" });
});

test("a stub callable says unimplemented, and bad input is BAD_REQUEST", async () => {
  await expect(httpsCallable(functions, "quoteOrder")({ paymentMethod: "upi" })).rejects.toMatchObject({
    code: "functions/invalid-argument",
    details: { reason: "BAD_REQUEST", detail: ["paymentMethod"] },
  });
});
