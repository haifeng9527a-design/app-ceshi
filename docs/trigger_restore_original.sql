-- 恢复为原始触发器：所有新消息（含退群系统消息）都更新会话摘要与未读数。
-- 在 Supabase SQL Editor 执行即可覆盖之前的 chat_on_message_insert。

create or replace function chat_on_message_insert()
returns trigger as $$
begin
  update chat_conversations
    set last_message = case
      when new.message_type = 'image' then '[图片]'
      when new.message_type = 'video' then '[视频]'
      when new.message_type = 'audio' then '[语音]'
      else new.content
    end,
        last_time = new.created_at,
        last_sender_id = new.sender_id
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
