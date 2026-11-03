import { callable, notImplemented } from "../shared/callable.js";
import { REPLAY_PROTECTED } from "../shared/options.js";
import * as c from "./contract.js";

// Owner: engineer C. Phase 0 stubs: each body becomes parse → guard → transaction (docs/FIREBASE.md D6).

export const quoteOrder = callable(c.quoteOrder, () => notImplemented());
export const placeOrder = callable(c.placeOrder, () => notImplemented(), REPLAY_PROTECTED);
export const cancelOrder = callable(c.cancelOrder, () => notImplemented());
export const adminUpdateOrder = callable(c.adminUpdateOrder, () => notImplemented());
export const adminSetImeis = callable(c.adminSetImeis, () => notImplemented());
