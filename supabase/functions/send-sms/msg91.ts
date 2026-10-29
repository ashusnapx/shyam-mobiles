import type { Sender } from "./handler.ts";

/**
 * MSG91 SendOTP (v5) with Supabase's own code: MSG91 only delivers it, Supabase checks it. The template is the
 * DLT-approved OTP template set up in MSG91 (it must contain ##OTP##). The authkey goes in a header, not the URL.
 * shortcut: endpoint and fields per MSG91's v5 OTP API as of Oct 2026; confirm with one real send to your own
 * number after the first deploy (Supabase > Auth > Logs show the error text if MSG91 refuses).
 */
export function msg91Sender(authKey: string, templateId: string, fetchFn: typeof fetch = fetch): Sender {
  return async (mobile, otp) => {
    const url = new URL("https://control.msg91.com/api/v5/otp");
    url.search = new URLSearchParams({ template_id: templateId, mobile, otp, otp_expiry: "10" }).toString();
    const res = await fetchFn(url, {
      method: "POST",
      headers: { authkey: authKey, "content-type": "application/json" },
      body: "{}",
      signal: AbortSignal.timeout(10_000),
    });
    const out = await res.json().catch(() => ({})) as { type?: string; message?: string };
    if (!res.ok || out.type !== "success") throw new Error(`MSG91 ${res.status}: ${out.message ?? "no message"}`);
  };
}
