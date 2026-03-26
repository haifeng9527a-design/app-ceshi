-- 在 Supabase SQL Editor 执行，启用 chat_messages 的 Realtime
-- 否则后端 WebSocket 无法收到新消息推送（其他客户端发的消息）
-- 若表已在 publication 中会报错，可忽略
alter publication supabase_realtime add table public.chat_messages;
