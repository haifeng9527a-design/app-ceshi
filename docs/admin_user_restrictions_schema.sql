-- 后台用户管理：user_profiles 扩展邮箱与限制字段
-- 在 Supabase SQL Editor 中执行

-- 1) 确保 user_profiles 有 email 列（与 SupabaseUserSync 同步）
alter table public.user_profiles
  add column if not exists email text;

-- 2) 用户限制与封禁（后台可编辑，业务侧按此字段判断）
alter table public.user_profiles
  add column if not exists updated_at timestamp with time zone default now(),
  add column if not exists banned_until timestamp with time zone,
  add column if not exists frozen_until timestamp with time zone,
  add column if not exists restrict_login boolean not null default false,
  add column if not exists restrict_send_message boolean not null default false,
  add column if not exists restrict_add_friend boolean not null default false,
  add column if not exists restrict_join_group boolean not null default false,
  add column if not exists restrict_create_group boolean not null default false;

-- 说明：
-- banned_until: 非空表示封禁至该时间，过期后自动解除
-- frozen_until: 非空表示冻结至该时间
-- restrict_*: 为 true 时禁止对应用户行为（登录/发消息/加好友/加群/建群）
