-- User roles and teacher data schema

-- 1) Extend user_profiles with role fields
alter table public.user_profiles
  add column if not exists role text default 'user',
  add column if not exists level integer default 0,
  add column if not exists verified_at timestamp with time zone,
  add column if not exists teacher_status text default 'pending';

-- 2) Teacher profile
create table if not exists public.teacher_profiles (
  user_id text primary key,
  real_name text,
  title text,
  organization text,
  bio text,
  style text,
  risk_level text,
  specialties text[],
  avatar_url text,
  status text default 'pending',
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- 3) Teacher stats
create table if not exists public.teacher_stats (
  user_id text primary key,
  win_count integer not null default 0,
  loss_count integer not null default 0,
  win_rate numeric default 0,
  pnl_total numeric default 0,
  pnl_month numeric default 0,
  updated_at timestamp with time zone not null default now()
);

-- 4) Trade strategies
create table if not exists public.trade_strategies (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  title text not null,
  summary text,
  content text,
  tags text[],
  image_urls text[] default '{}',
  status text not null default 'draft',
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists trade_strategies_teacher_idx
  on public.trade_strategies (teacher_id);

-- 5) Trade records
create table if not exists public.trade_records (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  symbol text,
  side text,
  entry_price numeric,
  exit_price numeric,
  qty numeric,
  pnl numeric,
  trade_time timestamp with time zone,
  note text,
  attachment_url text,
  created_at timestamp with time zone not null default now()
);

create index if not exists trade_records_teacher_idx
  on public.trade_records (teacher_id);

-- 6) Trade record files
create table if not exists public.trade_record_files (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  file_url text not null,
  file_type text,
  created_at timestamp with time zone not null default now()
);

create index if not exists trade_record_files_teacher_idx
  on public.trade_record_files (teacher_id);
