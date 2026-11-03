import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

const ensureApp = () => {
  if (!getApps().some((a) => a.name === "[DEFAULT]")) initializeApp(); // the functions emulator adds a named app of its own
};

/** The Admin SDK's Firestore, initialised on first use (one app per instance). Repositories and handlers only. */
export function db(): Firestore {
  ensureApp();
  return getFirestore();
}

/** The Admin SDK's Auth (claims, revocation, user lookup), initialised like [db]. */
export function adminAuth(): Auth {
  ensureApp();
  return getAuth();
}
