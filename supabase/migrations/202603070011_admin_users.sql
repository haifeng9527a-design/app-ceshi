-- 后台管理员账号表：用于登录校验、密码错误限制、管理员管理
-- 密码使用 bcrypt 哈希存储，不存明文

create table if not exists public.admin_users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  password_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists admin_users_username_idx on public.admin_users(username);
create index if not exists admin_users_locked_idx on public.admin_users(locked_until) where locked_until is not null;

comment on table public.admin_users is '后台管理员账号，用于 tongxin-admin 登录';
comment on column public.admin_users.password_hash is 'bcrypt 哈希';
comment on column public.admin_users.failed_attempts is '连续密码错误次数';
comment on column public.admin_users.locked_until is '锁定截止时间，null 表示未锁定';
