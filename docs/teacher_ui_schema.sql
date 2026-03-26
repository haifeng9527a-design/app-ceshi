-- Schema aligned with Featured Teacher UI

-- Extend teacher_profiles with UI fields
alter table public.teacher_profiles
  add column if not exists display_name text,
  add column if not exists tags text[],
  add column if not exists wins integer default 0,
  add column if not exists losses integer default 0,
  add column if not exists rating integer default 0,
  add column if not exists today_strategy text,
  add column if not exists pnl_current numeric default 0,
  add column if not exists pnl_month numeric default 0,
  add column if not exists pnl_year numeric default 0,
  add column if not exists pnl_total numeric default 0;

-- Strategy history (reuse trade_strategies)
-- already exists: trade_strategies

-- Trades (extend trade_records for UI fields)
alter table public.trade_records
  add column if not exists asset text,
  add column if not exists buy_time timestamp with time zone,
  add column if not exists buy_shares numeric,
  add column if not exists buy_price numeric,
  add column if not exists sell_time timestamp with time zone,
  add column if not exists sell_shares numeric,
  add column if not exists sell_price numeric,
  add column if not exists pnl_ratio numeric,
  add column if not exists pnl_amount numeric;

-- Positions (current + history)
create table if not exists public.teacher_positions (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  asset text not null,
  asset_class text default 'stock',
  product_type text default 'spot',
  position_side text default 'long',
  position_action text default 'open',
  margin_mode text default 'cross',
  leverage numeric default 1,
  contract_size numeric default 1,
  multiplier numeric default 1,
  settlement_asset text default 'USD',
  buy_time timestamp with time zone,
  buy_shares numeric,
  buy_price numeric,
  cost_price numeric,
  current_price numeric,
  mark_price numeric,
  index_price numeric,
  liquidation_price numeric,
  used_margin numeric,
  maintenance_margin numeric,
  floating_pnl numeric,
  pnl_ratio numeric,
  pnl_amount numeric,
  sell_time timestamp with time zone,
  sell_price numeric,
  is_history boolean not null default false,
  created_at timestamp with time zone not null default now()
);

alter table public.teacher_positions
  add column if not exists asset_class text default 'stock',
  add column if not exists product_type text default 'spot',
  add column if not exists position_side text default 'long',
  add column if not exists position_action text default 'open',
  add column if not exists margin_mode text default 'cross',
  add column if not exists leverage numeric default 1,
  add column if not exists contract_size numeric default 1,
  add column if not exists multiplier numeric default 1,
  add column if not exists settlement_asset text default 'USD',
  add column if not exists cost_price numeric,
  add column if not exists mark_price numeric,
  add column if not exists index_price numeric,
  add column if not exists liquidation_price numeric,
  add column if not exists used_margin numeric,
  add column if not exists maintenance_margin numeric,
  add column if not exists floating_pnl numeric,
  add column if not exists pnl_ratio numeric,
  add column if not exists pnl_amount numeric,
  add column if not exists is_history boolean not null default false,
  add column if not exists created_at timestamp with time zone not null default now();

create index if not exists teacher_positions_teacher_idx
  on public.teacher_positions (teacher_id);

-- Comments
create table if not exists public.teacher_comments (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  user_name text not null,
  content text not null,
  comment_time timestamp with time zone,
  created_at timestamp with time zone not null default now()
);

create index if not exists teacher_comments_teacher_idx
  on public.teacher_comments (teacher_id);

-- Articles
create table if not exists public.teacher_articles (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  title text not null,
  summary text,
  article_time timestamp with time zone,
  created_at timestamp with time zone not null default now()
);

create index if not exists teacher_articles_teacher_idx
  on public.teacher_articles (teacher_id);

-- Schedules
create table if not exists public.teacher_schedules (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  title text not null,
  schedule_time timestamp with time zone,
  location text,
  created_at timestamp with time zone not null default now()
);

create index if not exists teacher_schedules_teacher_idx
  on public.teacher_schedules (teacher_id);
