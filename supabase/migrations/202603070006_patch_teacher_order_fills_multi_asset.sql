-- Patch: teacher_order_fills compatibility for multi-asset trading

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

alter table public.teacher_order_fills
  add column if not exists asset_class text not null default 'stock',
  add column if not exists product_type text not null default 'spot',
  add column if not exists position_side text not null default 'long',
  add column if not exists margin_mode text not null default 'cross',
  add column if not exists leverage numeric not null default 1,
  add column if not exists fill_notional numeric default 0,
  add column if not exists created_at timestamptz not null default now();

create index if not exists teacher_order_fills_teacher_time_idx
  on public.teacher_order_fills(teacher_id, fill_time desc);

create index if not exists teacher_order_fills_order_idx
  on public.teacher_order_fills(order_id);
