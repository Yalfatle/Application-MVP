// Minimal WhatsApp Cloud API client (Meta Graph API).
// Configure with secrets: WA_PHONE_NUMBER_ID, WA_ACCESS_TOKEN.
import { env } from "./common.ts";

const GRAPH_VERSION = Deno.env.get("WA_GRAPH_VERSION") ?? "v21.0";

// WhatsApp language codes for approved templates.
export function templateLanguage(locale: string): string {
  return locale === "en" ? "en" : "ar";
}

/** Phone digits only, as the Cloud API expects ("9647701234567"). */
export function toWaNumber(phone: string): string {
  return phone.replace(/[^0-9]/g, "");
}

async function send(payload: Record<string, unknown>): Promise<string> {
  const res = await fetch(
    `https://graph.facebook.com/${GRAPH_VERSION}/${env("WA_PHONE_NUMBER_ID")}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env("WA_ACCESS_TOKEN")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ messaging_product: "whatsapp", ...payload }),
    },
  );
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`WhatsApp ${res.status}: ${JSON.stringify(data?.error ?? data)}`);
  }
  return data?.messages?.[0]?.id ?? "";
}

export function sendText(to: string, body: string): Promise<string> {
  return send({ to: toWaNumber(to), type: "text", text: { body, preview_url: false } });
}

export function sendTemplate(
  to: string,
  name: string,
  locale: string,
  params: string[],
): Promise<string> {
  return send({
    to: toWaNumber(to),
    type: "template",
    template: {
      name,
      language: { code: templateLanguage(locale) },
      components: params.length
        ? [{ type: "body", parameters: params.map((text) => ({ type: "text", text })) }]
        : [],
    },
  });
}

/** Authentication template: code in the body plus a "copy code" button. */
export function sendLoginCode(to: string, name: string, locale: string, code: string) {
  return send({
    to: toWaNumber(to),
    type: "template",
    template: {
      name,
      language: { code: templateLanguage(locale) },
      components: [
        { type: "body", parameters: [{ type: "text", text: code }] },
        { type: "button", sub_type: "url", index: "0", parameters: [{ type: "text", text: code }] },
      ],
    },
  });
}
