/**
 * 创建通话邀请：插入 call_invitations 并调用 send_push，确保被叫在后台也能收到来电推送。
 * 由客户端携带 Firebase Token 调用，网关可关闭 JWT 校验。
 */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";

const supabaseUrl = Deno.env.get("SB_URL") ?? "";
const supabaseKey = Deno.env.get("SB_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(supabaseUrl, supabaseKey);

type Body = {
  from_user_id: string;
  from_user_name: string;
  to_user_id: string;
  channel_id: string;
  call_type: string;
};

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { from_user_id, from_user_name, to_user_id, channel_id, call_type } = body;
  if (!from_user_id || !from_user_name || !to_user_id || !channel_id || !call_type) {
    return new Response(
      JSON.stringify({ error: "Missing from_user_id, from_user_name, to_user_id, channel_id or call_type" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const callType = call_type === "video" ? "video" : "voice";

  const { data: row, error: insertError } = await supabase
    .from("call_invitations")
    .insert({
      from_user_id,
      from_user_name,
      to_user_id,
      channel_id,
      call_type: callType,
      status: "ringing",
    })
    .select("id")
    .single();

  if (insertError) {
    console.error("create_call_invitation insert failed:", insertError);
    return new Response(
      JSON.stringify({ error: insertError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const invitationId = row?.id;
  if (!invitationId) {
    return new Response(
      JSON.stringify({ error: "Insert did not return id" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const sendPushUrl = `${supabaseUrl}/functions/v1/send_push`;
  try {
    await fetch(sendPushUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${supabaseKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        receiverId: to_user_id,
        title: callType === "video" ? "视频通话" : "语音通话",
        body: `${from_user_name} 邀请你${callType === "video" ? "视频" : "语音"}通话`,
        messageType: "call_invitation",
        invitationId: String(invitationId),
        channelId: channel_id,
        callType,
        fromUserName: from_user_name,
      }),
    });
  } catch (e) {
    console.error("create_call_invitation send_push failed:", e);
    // 邀请已写入，仍返回成功
  }

  return new Response(JSON.stringify({ id: invitationId }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
