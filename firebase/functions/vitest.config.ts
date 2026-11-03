import { defineConfig } from "vitest/config";

// One fork, one file at a time: this suite shares an 8 GB laptop with Gradle and the emulators (docs/FIREBASE.md §8).
export default defineConfig({
  resolve: {
    // payments' tests are written for node:test; vitest runs them unchanged (they use only `test`).
    alias: { "node:test": "vitest" },
  },
  test: {
    include: ["test/**/*.test.ts", "src/**/*.test.ts"],
    pool: "forks",
    maxWorkers: 1,
    fileParallelism: false,
    testTimeout: 20_000,
  },
});
