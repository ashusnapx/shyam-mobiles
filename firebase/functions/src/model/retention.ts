// How long each collection's documents live (docs/SECURITY.md §4.1, §4.5). Every model file exports
// `retention: Record<collectionPath, Retention>`; test/unit/retention.test.ts fails if a collection has none.

export type Retention =
  /** A Firestore TTL policy deletes the doc [days] after it is written (the field holds the deadline). */
  | { kind: "ttl"; field: "expireAt" | "purgeAt"; days: number }
  /** Personal data with no deadline of its own: deleted (or anonymised) by deleteAccount. */
  | { kind: "account" }
  /** Shop data with no personal data in it (catalogue, settings, counters): kept until staff remove it. */
  | { kind: "shop" };

export const DAY_MS = 86_400_000;
