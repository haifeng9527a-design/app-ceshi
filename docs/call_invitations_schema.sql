-- 通话邀请表：用于语音/视频通话信令（Agora 频道名、呼叫方、被叫方、状态）
-- 执行前请确保已启用 Realtime；RLS 需允许：被叫可读自己的邀请，主叫可插入/更新自己的邀请

create table if not exists public.call_invitations (
  id uuid primary key default gen_random_uuid(),
  from_user_id text not null,
  from_user_name text not null,
  to_user_id text not null,
  channel_id text not null,
  call_type text not null check (call_type in ('voice', 'video')),
  status text not null default 'ringing' check (status in ('ringing', 'accepted', 'rejected', 'cancelled')),
  created_at timestamptz not null default now()
);

create index if not exists idx_call_invitations_to_user_id
  on public.call_invitations (to_user_id);
create index if not exists idx_call_invitations_created_at
  on public.call_invitations (created_at desc);

alter table public.call_invitations enable row level security;

-- 被叫：只能查 to_user_id = 自己的记录
create policy "call_invitations_select_own"
  on public.call_invitations for select
  using (auth.jwt() ->> 'sub' = to_user_id);

-- 主叫：只能插入 from_user_id = 自己的记录
create policy "call_invitations_insert_own"
  on public.call_invitations for insert
  with check (auth.jwt() ->> 'sub' = from_user_id);

-- 主叫/被叫：可更新自己相关的记录（主叫取消、被叫接听/拒绝）
create policy "call_invitations_update_own"
  on public.call_invitations for update
  using (auth.jwt() ->> 'sub' = from_user_id or auth.jwt() ->> 'sub' = to_user_id);

-- Realtime：允许订阅 to_user_id = 自己的新记录（需在 Supabase Dashboard 为 call_invitations 表启用 Realtime）
-- 表需在 Realtime 发布列表中勾选

comment on table public.call_invitations is '语音/视频通话邀请，用于 Agora 通话信令';
