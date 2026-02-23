-- 引用回复：支持“回复某条消息”
-- 在 Supabase SQL Editor 执行

alter table public.chat_messages
  add column if not exists reply_to_message_id uuid references public.chat_messages(id) on delete set null,
  add column if not exists reply_to_sender_name text,
  add column if not exists reply_to_content text;

create index if not exists chat_messages_reply_to_idx
  on public.chat_messages (reply_to_message_id);

