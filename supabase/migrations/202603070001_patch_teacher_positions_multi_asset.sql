-- Patch: teacher_positions multi-asset compatibility
-- Ensures old databases have the same columns expected by the
-- current trading engine and UI.

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
  buy_time timestamptz,
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
  sell_time timestamptz,
  sell_price numeric,
  is_history boolean not null default false,
  created_at timestamptz not null default now()
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
  add column if not exists created_at timestamptz not null default now();

create index if not exists teacher_positions_teacher_idx
  on public.teacher_positions (teacher_id);

create index if not exists teacher_positions_teacher_history_idx
  on public.teacher_positions (teacher_id, is_history, created_at desc);

create index if not exists teacher_positions_teacher_asset_idx
  on public.teacher_positions (teacher_id, asset, is_history);
