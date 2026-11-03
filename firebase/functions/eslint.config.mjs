import js from "@eslint/js";
import { defineConfig } from "eslint/config";
import tseslint from "typescript-eslint";

const firebaseRuntime = ["firebase-admin", "firebase-admin/*", "firebase-functions", "firebase-functions/*"];

export default defineConfig(
  { ignores: ["lib/**", "node_modules/**"] },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: { parserOptions: { projectService: { allowDefaultProject: ["eslint.config.mjs"] }, tsconfigRootDir: import.meta.dirname } },
    rules: {
      "@typescript-eslint/restrict-template-expressions": ["error", { allowNumber: true }],
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "no-console": "error", // shared/log.ts strips personal data; console doesn't
    },
  },
  {
    // Layering (docs/FIREBASE.md §2): only handlers, repositories, triggers and shared/ touch the Firebase runtime.
    // Pure modules (pricing.ts, state.ts, notices.ts, contract.ts, model/…) stay testable without an emulator.
    files: ["src/**/*.ts"],
    ignores: ["src/index.ts", "src/shared/**", "src/payments/**", "src/*/index.ts", "src/*/handlers.ts", "src/*/repository.ts", "src/*/triggers.ts", "src/*/settlement.ts"],
    rules: {
      "no-restricted-imports": ["error", {
        patterns: [{ group: firebaseRuntime, allowTypeImports: true, message: "Pure module: move Firebase calls to handlers.ts or repository.ts (docs/FIREBASE.md §2 layering)." }],
      }],
    },
  },
  {
    files: ["test/**/*.ts", "src/**/*.test.ts", "vitest.config.ts"],
    rules: { "@typescript-eslint/no-non-null-assertion": "off", "@typescript-eslint/no-floating-promises": "off" },
  },
  {
    // TODO(D): payments predates these rules. Fix its findings (`npx eslint src/payments` with this block removed),
    // move console.* to shared/log.ts (it strips personal data), then delete this block.
    files: ["src/payments/**"],
    rules: {
      "@typescript-eslint/no-unsafe-member-access": "off",
      "@typescript-eslint/require-await": "off",
      "@typescript-eslint/no-unsafe-assignment": "off",
      "@typescript-eslint/use-unknown-in-catch-callback-variable": "off",
      "@typescript-eslint/no-unsafe-return": "off",
      "@typescript-eslint/no-confusing-void-expression": "off",
      "@typescript-eslint/no-unnecessary-condition": "off",
      "@typescript-eslint/no-non-null-assertion": "off",
      "@typescript-eslint/no-base-to-string": "off",
      "@typescript-eslint/no-unnecessary-type-parameters": "off",
      "no-console": "off",
    },
  },
);
