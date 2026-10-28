// Sends everything waiting in whatsapp_outbox.
// Called by the database (pg_net) right after new rows arrive, and by a
// once-a-minute sweep for retries. Protected by DISPATCH_SECRET, which
// must match the `dispatch_secret` Vault secret in the database.
import { adminClient, env, json, safeEqual } from "../_shared/common.ts";
import { sendTemplate, sendText } from "../_shared/whatsapp.ts";

const WINDOW_MS = 24 * 60 * 60 * 1000; // WhatsApp free-form window

type OutboxRow = {
  id: number;
  user_id: string;
  kind: "order_update" | "lab_message";
  text_body: string | null;
  template: string;
  params: string[];
  locale: string;
  attempts: number;
};

Deno.serve(async (req) => {
  const given = req.headers.get("x-dispatch-secret") ?? "";
  if (!safeEqual(given, env("DISPATCH_SECRET"))) return json({ error: "unauthorized" }, 401);

  const db = adminClient();
  const { data: rows, error } = await db.rpc("claim_whatsapp_outbox", { p_limit: 50 });
  if (error) return json({ error: error.message }, 500);

  let sent = 0;
  let failed = 0;

  for (const row of (rows ?? []) as OutboxRow[]) {
    try {
      const { data: phone } = await db.rpc("user_phone", { p_user_id: row.user_id });
      if (!phone) {
        // Account has no phone (e.g. email-only staff). Nothing to send.
        await db.from("whatsapp_outbox")
          .update({ status: "failed", last_error: "no phone on account" })
          .eq("id", row.id);
        failed++;
        continue;
      }

      let windowOpen = false;
      if (row.kind === "lab_message" && row.text_body) {
        const { data: session } = await db.from("whatsapp_sessions")
          .select("last_inbound_at").eq("user_id", row.user_id).maybeSingle();
        windowOpen = !!session &&
          Date.now() - new Date(session.last_inbound_at).getTime() < WINDOW_MS;
      }

      if (windowOpen) {
        await sendText(phone, row.text_body!);
      } else {
        await sendTemplate(phone, row.template, row.locale, row.params ?? []);
      }

      await db.from("whatsapp_outbox")
        .update({ status: "sent", sent_at: new Date().toISOString(), last_error: null, locked_until: null })
        .eq("id", row.id);
      sent++;
    } catch (e) {
      // Leave it pending; the sweep retries (up to 5 attempts in total).
      await db.from("whatsapp_outbox")
        .update({ last_error: String(e).slice(0, 500), locked_until: null })
        .eq("id", row.id);
      failed++;
    }
  }

  return json({ sent, failed });
});
