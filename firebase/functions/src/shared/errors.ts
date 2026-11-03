import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

/**
 * Every business reason a callable can fail with, and its transport code. The keys are the app's
 * app/lib/core/errors.dart `_codes` keys (the app shows copy by reason, never server text); test/unit/errors.test.ts
 * keeps both lists in step. New reasons need app copy in errors.dart first.
 */
export const REASONS = {
  // checkout and orders
  CART_EMPTY: "failed-precondition",
  CART_LIMIT: "failed-precondition",
  ADDRESS_NOT_FOUND: "not-found",
  ADDRESS_LIMIT: "failed-precondition",
  OUT_OF_STOCK: "failed-precondition",
  COD_UNAVAILABLE: "failed-precondition",
  PENDING_LIMIT: "resource-exhausted",
  ORDER_TOO_LARGE: "invalid-argument",
  INVALID_TRANSITION: "failed-precondition",
  INVALID_IMEIS: "invalid-argument",
  ACTIVE_ORDERS: "failed-precondition",
  // payments and refunds
  ORDER_NOT_PAYABLE: "failed-precondition",
  ORDER_EXPIRED: "failed-precondition",
  PAYMENT_MISMATCH: "failed-precondition",
  BAD_SIGNATURE: "permission-denied",
  GATEWAY_ERROR: "unavailable",
  REFUND_IN_PROGRESS: "failed-precondition",
  REFUND_UNCONFIRMED: "unavailable",
  REFUND_NOT_ALLOWED: "failed-precondition",
  REFUND_REFUSED: "failed-precondition",
  // coupons, offers and referrals
  COUPON_NOT_FOUND: "not-found",
  COUPON_NOT_STARTED: "failed-precondition",
  COUPON_EXPIRED: "failed-precondition",
  COUPON_USED_UP: "failed-precondition",
  COUPON_LIMIT_REACHED: "failed-precondition",
  COUPON_MIN_ORDER: "failed-precondition",
  COUPON_NOT_APPLICABLE: "failed-precondition",
  COUPON_FIRST_ORDER: "failed-precondition",
  COUPON_ONLINE_ONLY: "failed-precondition",
  COUPON_RATE_LIMIT: "resource-exhausted",
  COUPON_BETTER_OFFER: "failed-precondition",
  CODE_TAKEN: "already-exists",
  INVALID_PROMOTION: "invalid-argument",
  REFERRAL_OFF: "failed-precondition",
  REFERRAL_INVALID: "not-found",
  REFERRAL_SELF: "invalid-argument",
  REFERRAL_USED: "already-exists",
  REFERRAL_TOO_LATE: "failed-precondition",
  // repairs and feedback
  REPAIR_LIMIT: "resource-exhausted",
  QUOTE_CHANGED: "aborted",
  QUOTE_NOT_APPROVED: "failed-precondition",
  FEEDBACK_LIMIT: "resource-exhausted",
  // generic
  BAD_REQUEST: "invalid-argument",
  NOT_FOUND: "not-found",
  FORBIDDEN: "permission-denied",
  UNAUTHORIZED: "unauthenticated",
  REAUTH_REQUIRED: "unauthenticated",
  RATE_LIMITED: "resource-exhausted",
  INTERNAL: "internal",
} as const satisfies Record<string, FunctionsErrorCode>;

export type Reason = keyof typeof REASONS;

/** JSON the app gets as `details.detail` (a minimum in paise, variant ids, a rule name). Never personal data. */
export type Detail = string | number | boolean | null | readonly Detail[] | { readonly [k: string]: Detail };

/** Throws the one error shape callables use: `HttpsError(code, reason, {reason, detail?})`. */
export function fail(reason: Reason, detail?: Detail): never {
  throw new HttpsError(REASONS[reason], reason, detail === undefined ? { reason } : { reason, detail });
}

/** The reason of an error thrown by [fail], else null. */
export function reasonOf(e: unknown): Reason | null {
  if (!(e instanceof HttpsError)) return null;
  const reason: unknown = (e.details as { reason?: unknown } | undefined)?.reason;
  return typeof reason === "string" && reason in REASONS ? (reason as Reason) : null;
}
