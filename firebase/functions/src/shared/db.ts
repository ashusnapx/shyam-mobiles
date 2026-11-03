import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

/** The Admin SDK's Firestore, initialised on first use (one app per instance). Repositories and handlers only. */
export function db(): Firestore {
  if (getApps().length === 0) initializeApp();
  return getFirestore();
}
