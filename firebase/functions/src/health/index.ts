import { callable } from "../shared/callable.js";
import { REGION } from "../shared/options.js";
import * as c from "./contract.js";

/** The smallest callable: proves the pipeline (options, App Check, contract parsing) end to end. */
export const health = callable(c.health, () => Promise.resolve({ ok: true as const, region: REGION, at: new Date().toISOString() }));
