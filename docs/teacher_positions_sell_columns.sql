-- 历史持仓需有卖出时间、卖出价格，用于计算已实现盈亏与比例（Supabase SQL Editor 执行一次）
alter table public.teacher_positions
  add column if not exists sell_time timestamp with time zone,
  add column if not exists sell_price numeric;

comment on column public.teacher_positions.sell_time is '卖出时间（历史持仓必填）';
comment on column public.teacher_positions.sell_price is '卖出价格（历史持仓必填，用于计算已实现盈亏与比例）';
