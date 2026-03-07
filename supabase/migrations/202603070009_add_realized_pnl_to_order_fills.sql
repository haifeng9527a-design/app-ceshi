-- Add realized_pnl to teacher_order_fills for closing fills
alter table public.teacher_order_fills
  add column if not exists realized_pnl numeric;

comment on column public.teacher_order_fills.realized_pnl is '已实现盈亏，仅平仓成交时有值';
