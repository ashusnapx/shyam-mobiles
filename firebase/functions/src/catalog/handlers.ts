import { callable, notImplemented } from "../shared/callable.js";
import * as c from "./contract.js";

// Owner: engineer B. Phase 0 stubs: each body becomes parse → guard → transaction (docs/FIREBASE.md D6).

export const saveProduct = callable(c.saveProduct, () => notImplemented());
export const saveVariant = callable(c.saveVariant, () => notImplemented());
export const setProductImages = callable(c.setProductImages, () => notImplemented());
export const updateVariants = callable(c.updateVariants, () => notImplemented());
export const setFeatured = callable(c.setFeatured, () => notImplemented());
export const deleteProduct = callable(c.deleteProduct, () => notImplemented());
