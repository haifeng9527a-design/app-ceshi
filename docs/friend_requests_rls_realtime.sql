-- 好友申请表 RLS 与 Realtime 配置
-- 用途：让「系统通知」能实时收到好友申请，且仅能读/改自己的数据。
-- 使用前请确认：friend_requests 表已存在（见 supabase_chat_setup.md）。

-- ========== 1) RLS 策略 ==========
-- 说明：本应用用 Firebase 登录，Supabase 侧若用 anon key 且未传 JWT，
-- 则 auth.uid() 为空，下面策略会拒绝所有访问。
-- 若如此，有两种做法：
--   - 不启用 friend_requests 的 RLS（开发/内测可接受）；
--   - 或用 Edge Function / 后端用 service_role 代查「我的申请」，前端不直连 friend_requests。
-- 若已用自定义 JWT 把 Firebase UID 写入 sub（或 custom claim），则可启用下面策略。

alter table public.friend_requests enable row level security;

-- 谁可以读：仅能读「自己是申请者」或「自己是接收者」的申请
create policy "Users can read own requests as requester or receiver"
  on public.friend_requests
  for select
  using (
    auth.uid()::text = requester_id
    or auth.uid()::text = receiver_id
  );

-- 谁可以插入：任意已认证用户可发起申请（requester_id = 自己）
create policy "Users can insert as requester"
  on public.friend_requests
  for insert
  with check (auth.uid()::text = requester_id);

-- 谁可以更新：仅接收者可以更新（用于「通过/拒绝」）
create policy "Receiver can update request"
  on public.friend_requests
  for update
  using (auth.uid()::text = receiver_id)
  with check (auth.uid()::text = receiver_id);

-- 不开放 delete，避免误删记录（需要可再加 policy）


-- ========== 2) Realtime 发布 ==========
-- 说明：Supabase Realtime 依赖 publication。默认的 supabase_realtime 只包含部分表。
-- 要让「系统通知」页的 watchIncomingRequests 在别人发申请后自动刷新，需要把 friend_requests 加入发布。

-- 方式一：在 Supabase Dashboard 操作（推荐）
-- 1. 打开 Project → Database → Replication
-- 2. 找到 publication（如 supabase_realtime），Edit
-- 3. 在 Tables 里勾选 public.friend_requests，保存

-- 方式二：用 SQL 把表加入默认的 realtime publication（若存在）
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    execute 'alter publication supabase_realtime add table public.friend_requests';
  end if;
exception
  when duplicate_object then
    null; -- 已加入则忽略
end
$$;


-- ========== 3) 若不使用 JWT（仅 anon key） ==========
-- 若当前未配置「Firebase UID → Supabase JWT」，RLS 会拦掉所有请求。
-- 临时方案：不启用 RLS，仅依赖前端只请求 receiver_id = 当前用户 的数据。
-- （仅适合内测/封闭环境，正式环境建议配 JWT + 上面 RLS）

-- alter table public.friend_requests disable row level security;
