// The offers domain's exports. Owner: engineer C. src/index.ts re-exports this file; add functions here, never there.
export * from "./handlers.js";
// Social auto-posts offers (banners); its functions ship through this index because src/index.ts is frozen.
export * from "../social/index.js";
