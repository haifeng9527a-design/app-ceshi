-- 备用触发器：不更新 last_sender_id（适用于未加 last_sender_id 列的老表）。
-- 若你执行 trigger_system_leave_only_admin.sql 后发消息全部失败，可先执行本文件恢复发消息，
-- 再在 Supabase 执行: alter table chat_conversations add column if not exists last_sender_id text;
-- 最后再执行 trigger_system_leave_only_admin.sql 完整版。

create or replace function chat_on_message_insert()
returns trigger as $$
begin
  if coalesce(new.message_type, 'text') = 'system_leave' then
    return new;
  end if;

  update chat_conversations
    set last_message = case
      when new.message_type = 'image' then '[图片]'
      when new.message_type = 'video' then '[视频]'
      when new.message_type = 'audio' then '[语音]'
      else new.content
    end,
        last_time = new.created_at
  where id = new.conversation_id;

  update chat_members
    set unread_count = unread_count + 1
  where conversation_id = new.conversation_id
    and user_id <> new.sender_id;

  update chat_members
    set updated_at = now()
  where conversation_id = new.conversation_id;

  return new;
end;
$$ language plpgsql;
