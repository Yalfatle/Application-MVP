// Creates a staff account from an invite link.
//
// POST { token, full_name, password, email?, phone? }
//   - at least one of email / phone
//   - phone in international form, e.g. +9647701234567
//
// The invite is burned atomically in the database (claim_staff_invite), so
// only one account can ever be made from a link, and only within 1 hour.
import { adminClient, corsHeaders, json } from "../_shared/common.ts";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_RE = /^\+[1-9][0-9]{7,14}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const token = String(body.token ?? "").trim();
  const fullName = String(body.full_name ?? "").trim();
  const password = String(body.password ?? "");
  const email = body.email ? String(body.email).trim().toLowerCase() : undefined;
  const phone = body.phone ? String(body.phone).replace(/[\s-]/g, "") : undefined;

  if (!token) return json({ error: "missing_token" }, 400);
  if (fullName.length < 2) return json({ error: "name_required" }, 400);
  if (password.length < 8) return json({ error: "password_too_short" }, 400);
  if (!email && !phone) return json({ error: "email_or_phone_required" }, 400);
  if (email && !EMAIL_RE.test(email)) return json({ error: "invalid_email" }, 400);
  if (phone && !PHONE_RE.test(phone)) return json({ error: "invalid_phone" }, 400);

  const db = adminClient();

  // Cheap check first so we don't create accounts for dead links.
  const { data: peek, error: peekErr } = await db.rpc("peek_staff_invite", { p_token: token });
  if (peekErr) return json({ error: "server_error" }, 500);
  if (!peek || peek.length === 0) return json({ error: "invite_invalid" }, 410);

  const { data: created, error: createErr } = await db.auth.admin.createUser({
    email,
    phone,
    password,
    email_confirm: !!email,
    phone_confirm: !!phone,
    user_metadata: { full_name: fullName },
  });
  if (createErr || !created?.user) {
    const msg = createErr?.message ?? "";
    if (/already|registered|exists/i.test(msg)) return json({ error: "account_exists" }, 409);
    return json({ error: "could_not_create_account" }, 500);
  }

  const { error: claimErr } = await db.rpc("claim_staff_invite", {
    p_token: token,
    p_user_id: created.user.id,
    p_full_name: fullName,
  });
  if (claimErr) {
    // Someone else used the link a moment earlier, or it just expired.
    await db.auth.admin.deleteUser(created.user.id);
    return json({ error: "invite_invalid" }, 410);
  }

  return json({ ok: true, role: peek[0].role });
});
