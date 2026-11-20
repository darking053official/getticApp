// ============================================================
// supabase/functions/message-push/index.ts
// Yeni mesajda alıcılara OneSignal push gönderir.
// - Sessize alınmış üyelere gönderilmez.
// - Önizlemeyi gizleyen (profiles.hide_message_preview) alıcılara genel metin ("Yeni mesaj") gider.
// Secret'lar: ONESIGNAL_APP_ID, ONESIGNAL_REST_KEY
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sendPush(
  appId: string,
  restKey: string,
  recipients: string[],
  heading: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; out: unknown }> {
  const payload = {
    app_id: appId,
    target_channel: "push",
    include_aliases: { external_id: recipients },
    headings: { tr: heading, en: heading },
    contents: { tr: body, en: body },
    priority: 10,
    ttl: 86400,
    android_sound: "notification",
    data,
  };
  const res = await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Key ${restKey}`,
    },
    body: JSON.stringify(payload),
  });
  const out = await res.json().catch(() => ({}));
  return { ok: res.ok, out };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;

  let body: { conversationId?: string; messageId?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  if (!body.conversationId || !body.messageId) {
    return json({ error: "conversationId and messageId required" }, 400);
  }

  const { data: msg } = await supabase
    .from("messages")
    .select("id, sender_id, conversation_id, content, type, is_deleted")
    .eq("id", body.messageId)
    .maybeSingle();
  if (!msg || msg.sender_id !== userId || msg.conversation_id !== body.conversationId) {
    return json({ error: "invalid message" }, 403);
  }

  // Sessize alınmamış alıcılar
  const { data: members } = await supabase
    .from("conversation_members")
    .select("user_id, muted")
    .eq("conversation_id", body.conversationId)
    .neq("user_id", userId);
  const recipients = (members ?? [])
    .filter((m) => m.muted !== true)
    .map((m) => m.user_id as string);
  if (recipients.length === 0) return json({ ok: true, sent: 0 });

  // Önizlemeyi gizleyenler ve diğerleri
  const { data: prefs } = await supabase
    .from("profiles")
    .select("id, hide_message_preview")
    .in("id", recipients);
  const hidden = new Set(
    (prefs ?? []).filter((p) => p.hide_message_preview === true).map((p) => p.id as string),
  );
  const hiddenRecipients = recipients.filter((r) => hidden.has(r));
  const visibleRecipients = recipients.filter((r) => !hidden.has(r));

  const { data: sender } = await supabase
    .from("profiles")
    .select("username")
    .eq("id", userId)
    .maybeSingle();
  const senderName = (sender?.username ?? "Gettic").toString();

  const previewByType: Record<string, string> = {
    image: "📷 Fotoğraf",
    video: "🎥 Video",
    audio: "🎤 Sesli mesaj",
    voice: "🎤 Sesli mesaj",
    file: "📎 Dosya",
    gif: "GIF",
  };
  const text = msg.is_deleted
    ? "Bu mesaj silindi"
    : (previewByType[msg.type as string] ?? (msg.content ?? "").toString());

  const appId = Deno.env.get("ONESIGNAL_APP_ID");
  const restKey = Deno.env.get("ONESIGNAL_REST_KEY");
  if (!appId || !restKey) return json({ error: "onesignal not configured" }, 500);

  const data = {
    type: "chat_message",
    conversationId: body.conversationId,
    messageId: body.messageId,
  };

  const results: unknown[] = [];
  if (visibleRecipients.length > 0) {
    results.push(await sendPush(appId, restKey, visibleRecipients, senderName, text, data));
  }
  if (hiddenRecipients.length > 0) {
    // Gizlilik açık: gönderen adı ve içerik yerine genel metin
    results.push(await sendPush(appId, restKey, hiddenRecipients, "Gettic", "Yeni mesaj", data));
  }

  const ok = results.every((r) => (r as { ok: boolean }).ok);
  return json({ ok, sent: recipients.length, results }, ok ? 200 : 502);
});
