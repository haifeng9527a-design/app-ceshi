-- 允许用户通过邀请链接自行加入群聊（扫码或打开 teacherhub://group/join?id=xxx）
-- 仅允许向 type='group' 的会话插入自己为 member。
-- 统一转成 text 再比较，兼容 user_id/conversation_id 与 auth.uid()/id 分别为 text 或 uuid 的任意组合。
drop policy if exists "chat_members_insert_self_join_group" on public.chat_members;

create policy "chat_members_insert_self_join_group"
on public.chat_members
for insert
to authenticated
with check (
  (user_id)::text = (auth.uid())::text
  and (conversation_id)::text in (
    select (id)::text from public.chat_conversations where type = 'group'
  )
);


