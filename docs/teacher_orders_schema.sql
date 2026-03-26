-- teacher_orders：委托表（买入/卖出订单）
-- 在 Supabase SQL Editor 中执行

create table if not exists public.teacher_orders (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  symbol text not null,
  symbol_name text,
  side text not null check (side in ('buy', 'sell')),
  order_type text not null default 'limit' check (order_type in ('limit', 'market')),
  price numeric not null default 0,
  quantity numeric not null,
  filled_quantity numeric not null default 0,
  status text not null default 'pending' check (status in ('pending', 'partial', 'filled', 'cancelled', 'rejected')),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone
);

create index if not exists teacher_orders_teacher_idx on public.teacher_orders (teacher_id);
create index if not exists teacher_orders_created_idx on public.teacher_orders (created_at desc);

alter table public.teacher_orders enable row level security;

drop policy if exists teacher_orders_select_owner on public.teacher_orders;
create policy teacher_orders_select_owner on public.teacher_orders
  for select using ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_orders_insert_owner on public.teacher_orders;
create policy teacher_orders_insert_owner on public.teacher_orders
  for insert with check ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_orders_update_owner on public.teacher_orders;
create policy teacher_orders_update_owner on public.teacher_orders
  for update using ((auth.jwt()->>'sub') = teacher_id);

drop policy if exists teacher_orders_delete_owner on public.teacher_orders;
create policy teacher_orders_delete_owner on public.teacher_orders
  for delete using ((auth.jwt()->>'sub') = teacher_id);
