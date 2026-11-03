import { HttpsError, onCall, type CallableOptions, type CallableRequest } from "firebase-functions/v2/https";
import type { z } from "zod";
import { CALLABLE, IS_DEMO_PROJECT } from "./options.js";
import { fail, type Reason } from "./errors.js";
import { log } from "./log.js";
import { parse } from "./validation.js";

/** A callable's wire contract: what the app sends and what it gets back (src/<domain>/contract.ts). */
export interface Contract<I extends z.ZodType, O extends z.ZodType> {
  name: string;
  input: I;
  output: O;
  /** The reason input that fails [input] gets: BAD_REQUEST, or one with app copy (INVALID_IMEIS). */
  invalid: Reason;
}

export function contract<I extends z.ZodType, O extends z.ZodType>(name: string, input: I, output: O, invalid: Reason = "BAD_REQUEST"): Contract<I, O> {
  return { name, input, output, invalid };
}

type Handler<I extends z.ZodType, O extends z.ZodType> = (input: z.output<I>, req: CallableRequest) => Promise<z.input<O>>;

/**
 * The one way to make a callable: shared options (region, App Check, limits), input parsed with the contract (bad
 * input fails with the contract's `invalid` reason), output checked against it, and any error that isn't a `fail(reason)` logged and returned as
 * INTERNAL, so no stack or server text reaches the app. The handler does guard → transaction.
 */
export function callable<I extends z.ZodType, O extends z.ZodType>(
  c: Contract<I, O>,
  handler: Handler<I, O>,
  options: Omit<CallableOptions, "region"> = {},
){
  return onCall({ ...CALLABLE, ...options }, async (req: CallableRequest) => {
    // Monitor mode (ENFORCE_APP_CHECK false): the count of these lines is the watch before enforcing.
    if (req.app === undefined && !IS_DEMO_PROJECT) log.warn("app check missing", { fn: c.name });
    const input = parse(c.input, req.data, c.invalid);
    try {
      return c.output.parse(await handler(input, req));
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      log.error(`${c.name} failed`, { uid: req.auth?.uid ?? null, error: e });
      fail("INTERNAL");
    }
  });
}

/** Phase 0 body: the contract exists, the code doesn't yet. */
export function notImplemented(): never {
  throw new HttpsError("unimplemented", "UNIMPLEMENTED", { reason: "INTERNAL" });
}
