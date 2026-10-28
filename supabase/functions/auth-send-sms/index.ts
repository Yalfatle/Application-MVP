// Supabase Auth "Send SMS" hook: delivers login codes over WhatsApp
// instead of SMS. Enable it in Dashboard → Authentication → Hooks,
// pointing at this function, and store the hook secret as
// SEND_SMS_HOOK_SECRET (the "v1,whsec_..." value).
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { env } from "../_shared/common.ts";
import { sendLoginCode } from "../_shared/whatsapp.ts";

function hookError(message: string, status = 500) {
  return new Response(
    JSON.stringify({ error: { http_code: status, message } }),
    { status, headers: { "Content-Type": "application/json" } },
  );
}

Deno.serve(async (req) => {
  const payload = await req.text();
  const secret = env("SEND_SMS_HOOK_SECRET").replace("v1,whsec_", "");
  const headers = Object.fromEntries(req.headers);

  let data: { user: { phone: string; user_metadata?: Record<string, unknown> }; sms: { otp: string } };
  try {
    data = new Webhook(secret).verify(payload, headers) as typeof data;
  } catch {
    return hookError("invalid signature", 401);
  }

  const locale = data.user.user_metadata?.locale === "en" ? "en" : "ar";
  const template = Deno.env.get("WA_OTP_TEMPLATE") ?? "login_code";

  try {
    await sendLoginCode(data.user.phone, template, locale, data.sms.otp);
  } catch (e) {
    console.error("WhatsApp login code failed", e);
    return hookError("Could not send the code on WhatsApp. Please try again.");
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
