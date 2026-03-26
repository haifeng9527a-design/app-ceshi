-- 模拟盘交易闭环（Phase 1）数据库结构
-- 来源：docs/trading_engine_phase1_schema.sql

-- 1) 账户表：每位交易员 1 个模拟交易账户（USD）
create table if not exists public.teacher_trading_accounts (
  teacher_id text primary key,
  currency text not null default 'USD',
  account_type text not null default 'spot',
  margin_mode text not null default 'cross',
  leverage numeric not null default 1,
  initial_cash numeric not null default 1000000,
  cash_balance numeric not null default 1000000,
  cash_available numeric not null default 1000000,
  cash_frozen numeric not null default 0,
  market_value numeric not null default 0,
  used_margin numeric not null default 0,
  maintenance_margin numeric not null default 0,
  margin_balance numeric not null default 1000000,
  realized_pnl numeric not null default 0,
  unrealized_pnl numeric not null default 0,
  equity numeric not null default 1000000,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists teacher_trading_accounts_updated_idx
  on public.teacher_trading_accounts(updated_at desc);

-- 2) teacher_orders 扩展字段（兼容旧表）
alter table public.teacher_orders
  add column if not exists asset_type text default 'stock',
  add column if not exists asset_class text default 'stock',
  add column if not exists product_type text default 'spot',
  add column if not exists position_side text default 'long',
  add column if not exists position_action text default 'open',
  add column if not exists margin_mode text default 'cross',
  add column if not exists leverage numeric default 1,
  add column if not exists contract_size numeric default 1,
  add column if not exists multiplier numeric default 1,
  add column if not exists settlement_asset text default 'USD',
  add column if not exists mark_price numeric,
  add column if not exists index_price numeric,
  add column if not exists limit_price numeric,
  add column if not exists remaining_quantity numeric,
  add column if not exists avg_fill_price numeric,
  add column if not exists frozen_cash numeric default 0,
  add column if not exists reserved_quantity numeric default 0,
  add column if not exists error_reason text;

-- 老字段 price 作为 limit_price 兜底
update public.teacher_orders
set limit_price = coalesce(limit_price, price)
where limit_price is null and price is not null;

update public.teacher_orders
set remaining_quantity = coalesce(remaining_quantity, quantity - coalesce(filled_quantity, 0))
where remaining_quantity is null;

create index if not exists teacher_orders_teacher_status_idx
  on public.teacher_orders(teacher_id, status, created_at desc);
create index if not exists teacher_orders_teacher_symbol_idx
  on public.teacher_orders(teacher_id, symbol);

-- 3) 成交明细
create table if not exists public.teacher_order_fills (
  id uuid primary key default gen_random_uuid(),
  order_id uuid,
  teacher_id text not null,
  symbol text not null,
  asset_class text not null default 'stock',
  product_type text not null default 'spot',
  side text not null check (side in ('buy','sell')),
  position_side text not null default 'long',
  margin_mode text not null default 'cross',
  leverage numeric not null default 1,
  fill_price numeric not null,
  fill_quantity numeric not null,
  fill_notional numeric default 0,
  fill_time timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists teacher_order_fills_teacher_time_idx
  on public.teacher_order_fills(teacher_id, fill_time desc);
create index if not exists teacher_order_fills_order_idx
  on public.teacher_order_fills(order_id);

-- 4) 账户流水
create table if not exists public.teacher_account_ledger (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  entry_type text not null,
  amount numeric not null,
  balance_after numeric not null,
  order_id uuid,
  symbol text,
  asset_class text,
  product_type text,
  side text,
  position_side text,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists teacher_account_ledger_teacher_time_idx
  on public.teacher_account_ledger(teacher_id, created_at desc);

-- 5) 默认初始资金（后台可改）
insert into public.app_config(key, value)
values ('trading_default_initial_cash_usd', '1000000')
on conflict (key) do nothing;

-- 6) RLS（管理端走服务端，教师端只可见自己数据）
alter table public.teacher_trading_accounts enable row level security;
alter table public.teacher_order_fills enable row level security;
alter table public.teacher_account_ledger enable row level security;

drop policy if exists teacher_trading_accounts_select_owner on public.teacher_trading_accounts;
create policy teacher_trading_accounts_select_owner on public.teacher_trading_accounts
for select using ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_trading_accounts_insert_owner on public.teacher_trading_accounts;
create policy teacher_trading_accounts_insert_owner on public.teacher_trading_accounts
for insert with check ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_trading_accounts_update_owner on public.teacher_trading_accounts;
create policy teacher_trading_accounts_update_owner on public.teacher_trading_accounts
for update using ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_order_fills_select_owner on public.teacher_order_fills;
create policy teacher_order_fills_select_owner on public.teacher_order_fills
for select using ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_order_fills_insert_owner on public.teacher_order_fills;
create policy teacher_order_fills_insert_owner on public.teacher_order_fills
for insert with check ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_account_ledger_select_owner on public.teacher_account_ledger;
create policy teacher_account_ledger_select_owner on public.teacher_account_ledger
for select using ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_account_ledger_insert_owner on public.teacher_account_ledger;
create policy teacher_account_ledger_insert_owner on public.teacher_account_ledger
for insert with check ((auth.jwt()->>'sub') = teacher_id);
