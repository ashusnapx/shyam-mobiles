import { HttpError, json } from "../_shared/http.ts";
import { callRpc, type Rpc } from "../_shared/supabase.ts";

export type Account = { user_id: string; full_name: string | null; staff: boolean; created_at: string };

export interface Accounts {
  rpc: Rpc;
  /** Auth's admin update of one user; throws when Auth refuses. */
  update(userId: string, attrs: { password?: string; app_metadata?: Record<string, unknown> }): Promise<void>;
}

const PHONE = /^\+91[6-9][0-9]{9}$/;

// Short everyday words, so a temporary password is easy to read out on a call and type on a phone keyboard. The app's
// "Suggest a password" uses the same list (app/lib/features/auth/data/passwords.dart).
export const WORDS = [
  "Apple", "Mango", "Lemon", "Grape", "Melon", "Peach", "Berry", "Honey", "Sugar", "Bread",
  "Ginger", "Pepper", "Coffee", "Cherry", "Banana", "Orange", "Guava", "Papaya", "Kiwi", "Plum",
  "River", "Cloud", "Ocean", "Lake", "Hill", "Stone", "Leaf", "Tree", "Lotus", "Rose",
  "Lily", "Tulip", "Grass", "Rain", "Storm", "Snow", "Star", "Moon", "Comet", "Sunny",
  "Tiger", "Lion", "Horse", "Camel", "Zebra", "Panda", "Eagle", "Parrot", "Rabbit", "Koala",
  "Whale", "Otter", "Swan", "Deer", "Bear", "Puppy", "Kitten", "Robin", "Crane", "Goat",
  "Kite", "Drum", "Bell", "Lamp", "Chair", "Table", "Clock", "Train", "Plane", "Boat",
  "Truck", "Bike", "Ball", "Book", "Pencil", "Card", "Gift", "Rocket", "Robot", "Piano",
  "Flute", "Guitar", "Candle", "Button", "Basket", "Window", "Garden", "Bridge", "Castle", "Island",
  "Blue", "Green", "Gold", "Silver", "Pink", "Amber", "Coral", "Ruby", "Pearl", "Jade",
];

/** A uniform integer in [0, n) from the platform's CSPRNG (rejection sampling, no modulo bias). */
export function randomInt(n: number): number {
  const limit = Math.floor(0x100000000 / n) * n;
  const buf = new Uint32Array(1);
  do crypto.getRandomValues(buf); while (buf[0] >= limit);
  return buf[0] % n;
}

/** "Mango-River-4827": two different words and 4 digits. */
export function temporaryPassword(random: (n: number) => number = randomInt): string {
  const first = random(WORDS.length);
  const second = (first + 1 + random(WORDS.length - 1)) % WORDS.length;
  return `${WORDS[first]}-${WORDS[second]}-${String(random(10000)).padStart(4, "0")}`;
}

// {phone} -> {user_id, full_name, phone, created_at}: whose account the number signs in to, for staff to check.
// {phone, reset: true} -> the same plus {password}: a new temporary password for the customer, with
// app_metadata.must_change_password so the app asks them to choose their own right after signing in. Staff only.
export async function resetPassword(body: Record<string, unknown>, staffId: string, accounts: Accounts): Promise<Response> {
  const { phone, reset = false } = body;
  if (typeof phone !== "string" || !PHONE.test(phone) || typeof reset !== "boolean") {
    throw new HttpError(400, "BAD_REQUEST", "Enter the customer's 10-digit mobile number.");
  }
  const account = await callRpc<Account | null>(accounts.rpc, "account_by_phone", { p_phone: phone }, {});
  if (!account) {
    throw new HttpError(404, "NO_ACCOUNT", "No account uses this number. The customer can create one in the app with it.");
  }
  if (account.staff) {
    throw new HttpError(403, "STAFF_ACCOUNT", "This is a staff account. Staff change their own password in Account > Profile.");
  }
  const who = { user_id: account.user_id, full_name: account.full_name, phone, created_at: account.created_at };
  if (!reset) return json(who);

  const password = temporaryPassword();
  // Two updates, in this order: 20261103000000_phone_password.sql clears the flag on any password change that leaves
  // app_metadata alone, so the flag must come after the password.
  await accounts.update(account.user_id, { password });
  await accounts.update(account.user_id, { app_metadata: { must_change_password: true } });
  console.log(`reset-password: staff ${staffId} reset the password of ${account.user_id}`);
  return json({ ...who, password });
}
