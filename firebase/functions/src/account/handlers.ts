import { callable, notImplemented } from "../shared/callable.js";
import { REPLAY_PROTECTED } from "../shared/options.js";
import * as c from "./contract.js";

// Owner: engineer A. Phase 0 stubs: each body becomes parse → guard → transaction (docs/FIREBASE.md D6).

export const claimOwner = callable(c.claimOwner, () => notImplemented());
export const setRole = callable(c.setRole, () => notImplemented(), REPLAY_PROTECTED);
export const deleteAccount = callable(c.deleteAccount, () => notImplemented(), REPLAY_PROTECTED);
export const adminDeleteAccount = callable(c.adminDeleteAccount, () => notImplemented(), REPLAY_PROTECTED);
export const exportMyData = callable(c.exportMyData, () => notImplemented());
export const signOutEverywhere = callable(c.signOutEverywhere, () => notImplemented());
