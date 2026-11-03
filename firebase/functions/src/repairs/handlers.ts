import { callable, notImplemented } from "../shared/callable.js";
import * as c from "./contract.js";

// Owner: engineer D. Phase 0 stubs: each body becomes parse → guard → transaction (docs/FIREBASE.md D6).

export const bookRepair = callable(c.bookRepair, () => notImplemented());
export const cancelRepair = callable(c.cancelRepair, () => notImplemented());
export const approveRepairQuote = callable(c.approveRepairQuote, () => notImplemented());
export const declineRepairQuote = callable(c.declineRepairQuote, () => notImplemented());
export const adminUpdateRepair = callable(c.adminUpdateRepair, () => notImplemented());
export const adminSetRepairQuote = callable(c.adminSetRepairQuote, () => notImplemented());
