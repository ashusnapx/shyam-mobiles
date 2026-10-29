import { Webhook } from "npm:standardwebhooks@1.0.0";

/** Delivers one code to an Indian mobile in 91XXXXXXXXXX form; throws when the provider refuses it. */
export type Sender = (mobile: string, otp: string) => Promise<void>;

// Auth shows `message` to the user and treats any non-200 as "the code wasn't sent".
const hookError = (status: number, message: string) =>
  Response.json({ error: { http_code: status, message } }, { status });

/** Supabase Auth's Send SMS hook: check the Standard Webhooks signature, then hand the code to the provider. */
export async function handleSendSms(req: Request, secret: string, send: Sender): Promise<Response> {
  if (req.method !== "POST") return hookError(405, "Use POST.");
  const payload = await req.text();
  let body: { user?: { phone?: string }; sms?: { otp?: string } };
  try {
    body = new Webhook(secret.replace(/^v1,whsec_/, "")).verify(payload, Object.fromEntries(req.headers)) as typeof body;
  } catch {
    return hookError(401, "Invalid signature.");
  }
  const mobile = (body.user?.phone ?? "").replace(/\D/g, "");
  const otp = body.sms?.otp ?? "";
  // Indian mobiles only, like the app's phone field: no paying for SMS to premium-rate numbers abroad.
  if (!/^91[6-9]\d{9}$/.test(mobile)) return hookError(400, "Use a 10-digit Indian mobile number.");
  if (!/^\d{6}$/.test(otp)) return hookError(400, "Bad code.");
  try {
    await send(mobile, otp);
  } catch (e) {
    console.error(e);
    return hookError(502, "Couldn’t send the code. Try again in a minute.");
  }
  return Response.json({});
}
