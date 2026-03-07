-- Patch: teacher_trading_accounts compatibility for multi-asset engine

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

alter table public.teacher_trading_accounts
  add column if not exists currency text not null default 'USD',
  add column if not exists account_type text not null default 'spot',
  add column if not exists margin_mode text not null default 'cross',
  add column if not exists leverage numeric not null default 1,
  add column if not exists initial_cash numeric not null default 1000000,
  add column if not exists cash_balance numeric not null default 1000000,
  add column if not exists cash_available numeric not null default 1000000,
  add column if not exists cash_frozen numeric not null default 0,
  add column if not exists market_value numeric not null default 0,
  add column if not exists used_margin numeric not null default 0,
  add column if not exists maintenance_margin numeric not null default 0,
  add column if not exists margin_balance numeric not null default 1000000,
  add column if not exists realized_pnl numeric not null default 0,
  add column if not exists unrealized_pnl numeric not null default 0,
  add column if not exists equity numeric not null default 1000000,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create index if not exists teacher_trading_accounts_updated_idx
  on public.teacher_trading_accounts(updated_at desc);
