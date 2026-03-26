-- 群发消息 RPC：以系统客服身份向所有已有会话的用户发送消息
-- 在 Supabase SQL Editor 中执行
-- 仅向已与系统客服建立会话的用户发送（未添加客服为好友的用户不会收到）

create or replace function public.broadcast_customer_service_message(msg text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cs_id text;
  cs_name text;
  conv_count int := 0;
  rec record;
begin
  if msg is null or trim(msg) = '' then
    return jsonb_build_object('ok', false, 'error', '消息不能为空', 'count', 0);
  end if;
  select value into cs_id from app_config where key = 'customer_service_user_id' limit 1;
  if cs_id is null or trim(cs_id) = '' then
    return jsonb_build_object('ok', false, 'error', '未配置系统客服', 'count', 0);
  end if;
  select coalesce(nullif(trim(display_name), ''), '客服') into cs_name
    from user_profiles where user_id = cs_id limit 1;
  if cs_name is null then
    cs_name := '客服';
  end if;
  for rec in
    select cm.conversation_id
    from chat_members cm
    join chat_conversations c on c.id = cm.conversation_id and c.type = 'direct'
    where cm.user_id = cs_id
  loop
    insert into chat_messages (conversation_id, sender_id, sender_name, content, message_type)
    values (rec.conversation_id, cs_id, cs_name, trim(msg), 'text');
    conv_count := conv_count + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', conv_count);
end;
$$;

grant execute on function public.broadcast_customer_service_message(text) to authenticated;
grant execute on function public.broadcast_customer_service_message(text) to anon;
