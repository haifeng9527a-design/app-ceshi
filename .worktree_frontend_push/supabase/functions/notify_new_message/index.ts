/**
 * 由 Database Webhook 在 chat_messages 插入时触发，自动给会话中除发送者外的所有人发系统推送。
 * 不依赖发送方客户端是否成功调用 send_push，确保对方一定能触发推送。
 */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";

const supabaseUrl = Deno.env.get("SB_URL") ?? "";
const supabaseKey = Deno.env.get("SB_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(supabaseUrl, supabaseKey);

type WebhookPayload = {
  type: string;
  table?: string;
  record?: {
    id?: string;
    conversation_id?: string;
    sender_id?: string;
    sender_name?: string;
    content?: string;
    message_type?: string;
  };
};

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  if (payload.type !== "INSERT" || payload.table !== "chat_messages" || !payload.record) {
    return new Response(JSON.stringify({ ok: true, skipped: "not chat_messages INSERT" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const record = payload.record;
  const conversationId = record.conversation_id;
  const senderId = record.sender_id;
  const senderName = (record.sender_name ?? "有人").toString().trim() || "新消息";
  const content = (record.content ?? "").toString().trim();
  const messageType = (record.message_type ?? "text").toString();
  const body = content.length > 100 ? `${content.slice(0, 100)}…` : content || "发来一条消息";

  if (!conversationId || !senderId) {
    return new Response(JSON.stringify({ ok: false, error: "missing conversation_id or sender_id" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: members, error: membersError } = await supabase
    .from("chat_members")
    .select("user_id, role")
    .eq("conversation_id", conversationId)
    .neq("user_id", senderId);

  if (membersError || !members || members.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, pushed: 0, reason: membersError?.message ?? "no receivers" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  let receiverIds: string[] = members.map((m) => m.user_id).filter((id): id is string => !!id && id !== senderId);
  if (messageType === "system_leave") {
    receiverIds = members
      .filter((m) => m.role === "owner" || m.role === "admin")
      .map((m) => m.user_id)
      .filter((id): id is string => !!id && id !== senderId);
  }
  const pushBody = {
    senderId: String(senderId),
    title: senderName,
    body,
    conversationId: String(conversationId),
    messageType,
  };

  const sendPushUrl = `${supabaseUrl}/functions/v1/send_push`;
  const headers = {
    Authorization: `Bearer ${supabaseKey}`,
    "Content-Type": "application/json",
  };

  let pushed = 0;
  for (const receiverId of receiverIds) {
    try {
      const res = await fetch(sendPushUrl, {
        method: "POST",
        headers,
        body: JSON.stringify({ ...pushBody, receiverId }),
      });
      if (res.ok) pushed += 1;
    } catch (_) {
      // continue to next receiver
    }
  }

  return new Response(
    JSON.stringify({ ok: true, pushed, receivers: receiverIds.length }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
