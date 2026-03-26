-- 退群系统消息（system_leave）仅群主/管理员可见：不更新会话列表摘要、不增加未读数。
-- 在 Supabase SQL Editor 执行。
-- 若执行后发消息全部失败，多半是缺少 last_sender_id 列，请先执行下面第一句再加触发器。

-- 1) 先确保会话表有「最后一条消息发送者」列（没有会报错导致发消息全失败）
alter table chat_conversations add column if not exists last_sender_id text;

-- 2) 触发器：system_leave 不更新摘要与未读
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
 