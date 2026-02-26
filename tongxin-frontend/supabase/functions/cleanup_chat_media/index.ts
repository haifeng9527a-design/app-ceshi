/**
 * 定时清理聊天媒体：删除 24 小时前的图片/视频/语音/文件在 Storage 中的对象，节省空间。
 * 仅删除 chat_messages 中 message_type 为 image/video/audio/file 的 media_url、media_url_transcoded 对应文件。
 * 应由 Cron 定时调用（如每日一次），调用时需在 Header 中携带 CRON_SECRET。
 */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";

const supabaseUrl = Deno.env.get("SB_URL") ?? "";
const supabaseKey = Deno.env.get("SB_SERVICE_ROLE_KEY") ?? "";
const cronSecret = Deno.env.get("CRON_SECRET") ?? "";

const BUCKET = "chat-media";
const MEDIA_TYPES = ["image", "video", "audio", "file"];

/** 从公开 URL 解析出 storage 对象路径（bucket 后的部分） */
function parseStoragePath(publicUrl: string): string | null {
  try {
    const u = new URL(publicUrl);
    // 格式: /storage/v1/object/public/chat-media/chat/convId/userId/xxx
    const match = u.pathname.match(new RegExp(`/object/public/${BUCKET}/(.+)`));
    return match ? decodeURIComponent(match[1]) : null;
  } catch {
    return null;
  }
}

serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  const auth = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? req.headers.get("x-cron-secret") ?? "";
  if (cronSecret && auth !== cronSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { "Content-Type": "application/json" } });
  }

  // 默认 24 小时；测试时可传 ?expireMinutes=5 表示 5 分钟后过期
  const url = new URL(req.url);
  const expireMinutes = Math.max(1, parseInt(url.searchParams.get("expireMinutes") ?? "1440", 10) || 1440);
  const cutoff = new Date(Date.now() - expireMinutes * 60 * 1000).toISOString();

  const supabase = createClient(supabaseUrl, supabaseKey);

  // 查询早于 cutoff、类型为媒体且带 media_url 的消息
  const { data: rows, error: queryError } = await supabase
    .from("chat_messages")
    .select("id, media_url, media_url_transcoded")
    .in("message_type", MEDIA_TYPES)
    .lt("created_at", cutoff);

  if (queryError) {
    return new Response(
      JSON.stringify({ ok: false, error: queryError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const paths = new Set<string>();
  for (const row of rows ?? []) {
    const url = row.media_url as string | null;
    const urlTranscoded = row.media_url_transcoded as string | null;
    if (url) {
      const p = parseStoragePath(url);
      if (p) paths.add(p);
    }
    if (urlTranscoded) {
      const p = parseStoragePath(urlTranscoded);
      if (p) paths.add(p);
    }
  }

  const pathList = Array.from(paths);
  if (pathList.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, deleted: 0, message: "no expired media" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Storage remove 单次建议不超过 1000；分批
  const batchSize = 500;
  let deleted = 0;
  for (let i = 0; i < pathList.length; i += batchSize) {
    const batch = pathList.slice(i, i + batchSize);
    const { error: removeError } = await supabase.storage.from(BUCKET).remove(batch);
    if (removeError) {
      return new Response(
        JSON.stringify({ ok: false, error: removeError.message, deleted }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
    deleted += batch.length;
  }

  return new Response(
    JSON.stringify({ ok: true, deleted, totalMessages: rows?.length ?? 0, expireMinutes }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
