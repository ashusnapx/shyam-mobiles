import { z } from "zod";
import { v } from "../shared/validation.js";

// Owner: engineer D. No callables: notifications are written by triggers and read by the app under Rules. The wire
// contract is the FCM data payload, which lib/core/push.dart reads (same keys as Supabase's send-push).

export const pushData = z.strictObject({
  id: z.string(),
  kind: z.string(),
  title: z.string().max(80),
  body: z.string().max(300),
  link: v.appRoute,
  image_path: z.string().optional(),
});
export type PushData = z.infer<typeof pushData>;

/** What notices.ts returns for one source change: who gets which copy. */
export interface Notice {
  recipient: string; // a uid, or "staff" for every staff member
  except?: string; // with "staff": the staff member who did it, who isn't told
  key: string; // with the source id, kind and recipient, the notification's id: the same write never notifies twice
  kind: string;
  title: string;
  body: string;
  link: string;
  orderId?: string;
  repairId?: string;
  imagePath?: string;
}
