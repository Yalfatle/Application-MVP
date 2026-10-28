// Receives messages patients send to the platform's WhatsApp number and
// puts them in the right conversation, so lab staff see the reply in the
// dashboard without ever seeing the patient's number.
//
// Meta setup: callback URL = this function's URL,
// verify token = WA_VERIFY_TOKEN, app secret = WA_APP_SECRET.
// Deploy with --no-verify-jwt (Meta can't send a Supabase token).
import { adminClient, env, safeEqual } from "../_shared/common.ts";

async function validSignature(raw: string, header: string | null): Promise<boolean> {
  if (!header?.startsWith("sha256=")) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env("WA_APP_SECRET")),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw));
  const hex = Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return safeEqual(hex, header.slice("sha256=".length));
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Meta's one-time verification handshake.
  if (req.method === "GET") {
    const ok = url.searchParams.get("hub.mode") === "subscribe" &&
      safeEqual(url.searchParams.get("hub.verify_token") ?? "", env("WA_VERIFY_TOKEN"));
    return ok
      ? new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 })
      : new Response("forbidden", { status: 403 });
  }

  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const raw = await req.text();
  if (!(await validSignature(raw, req.headers.get("x-hub-signature-256")))) {
    return new Response("bad signature", { status: 401 });
  }

  // deno-lint-ignore no-explicit-any
  let payload: any;
  try {
    payload = JSON.parse(raw);
  } catch {
    return new Response("ok", { status: 200 });
  }

  const db = adminClient();
  for (const entry of payload?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      for (const msg of change?.value?.messages ?? []) {
        const text: string | undefined =
          msg.type === "text" ? msg.text?.body
          : msg.type === "button" ? msg.button?.text
          : msg.type === "interactive" ? (msg.interactive?.button_reply?.title ?? msg.interactive?.list_reply?.title)
          : undefined;
        const body = text ?? "[Patient sent a file or media. Ask them to send it through the app.]";

        const { error } = await db.rpc("record_whatsapp_inbound", {
          p_phone: String(msg.from ?? ""),
          p_body: body,
          p_wa_message_id: String(msg.id ?? ""),
        });
        if (error) console.error("record_whatsapp_inbound failed", error);
      }
    }
  }

  // Always 200 so Meta doesn't keep retrying messages we've handled.
  return new Response("ok", { status: 200 });
});
