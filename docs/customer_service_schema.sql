-- 客服系统：系统客服账号、客服人员、用户分配
-- 在 Supabase SQL Editor 中执行

-- 1) user_profiles 增加 customer_service 角色
-- role 已有，支持 'user' | 'admin' | 'vip' | 'customer_service'

-- 2) 应用配置表（存储系统客服 ID、头像等）
-- 配置说明：
--   customer_service_user_id: 系统客服账号（用户添加的好友、消息接收方），需先在 Firebase 注册并同步到 user_profiles
--   customer_service_avatar_url: 客服固定头像 URL（可选，不填则用 user_profiles.avatar_url）
-- 客服人员（客服1、客服2...）：在 user_profiles 中设置 role='customer_service'，登录后可见「客服工作台」
create table if not exists public.app_config (
  key text primary key,
  value text,
  updated_at timestamptz default now()
);

-- 插入默认配置（需手动将 customer_service_user_id 改为实际客服账号）
insert into public.app_config (key, value) values
  ('customer_service_user_id', ''),
  ('customer_service_avatar_url', ''),
  ('customer_service_welcome_message', '')
on conflict (key) do nothing;

comment on table public.app_config is '应用配置，如系统客服 ID、头像';

-- 3) 用户与客服的分配关系（用于负载均衡与归属）
create table if not exists public.customer_service_assignments (
  user_id text not null,
  staff_id text not null,
  assigned_at timestamptz not null default now(),
  primary key (user_id)
);

create index if not exists idx_cs_assignments_staff on public.customer_service_assignments(staff_id);

comment on table public.customer_service_assignments is '用户与客服的分配关系';

-- RLS
alter table public.app_config enable row level security;
alter table public.customer_service_assignments enable row level security;

drop policy if exists app_config_select on public.app_config;
create policy app_config_select on public.app_config for select to authenticated, anon using (true);

drop policy if exists app_config_all on public.app_config;
-- 管理后台使用 anon 连接，需允许 anon 读写 app_config
create policy app_config_all on public.app_config for all to authenticated, anon using (true) with check (true);

drop policy if exists cs_assignments_select on public.customer_service_assignments;
create policy cs_assignments_select on public.customer_service_assignments for select to authenticated using (true);

drop policy if exists cs_assignments_insert on public.customer_service_assignments;
create policy cs_assignments_insert on public.customer_service_assignments for insert to authenticated with check (true);

drop policy if exists cs_assignments_update on public.customer_service_assignments;
create policy cs_assignments_update on public.customer_service_assignments for update to authenticated using (true) with check (true);
