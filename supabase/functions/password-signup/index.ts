// TEMPORARY patient sign-up with email + password, for use until the
// WhatsApp Business number is set up and patients can log in with a code.
//
// Only works while app_settings.password_signup_enabled is true. Switch it
// off (or delete this function) once WhatsApp login is live:
//   update public.app_settings set password_signup_enabled = false;
//
// POST { email, password, full_name, locale? }
// Accounts are created already confirmed, so no confirmation email is sent
// (Supabase's built-in email sender only allows a few per hour).
import { adminClient, corsHeaders, json } from "../_shared/common.ts";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const db = adminClient();
  const { data: settings } = await db.from("app_settings").select("password_signup_enabled").single();
  if (!settings?.password_signup_enabled) return json({ error: "disabled" }, 403);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const fullName = String(body.full_name ?? "").trim();
  const locale = body.locale === "en" ? "en" : "ar";

  if (!EMAIL_RE.test(email)) return json({ error: "invalid_email" }, 400);
  if (password.length < 8) return json({ error: "password_too_short" }, 400);
  if (fullName.length < 2) return json({ error: "name_required" }, 400);

  // Always a plain patient account: role is set by the database, never here.
  const { error } = await db.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, locale },
  });
  if (error) {
    if (/already|registered|exists/i.test(error.message)) return json({ error: "account_exists" }, 409);
    return json({ error: "could_not_create_account" }, 500);
  }
  return json({ ok: true });
});
