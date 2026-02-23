-- 为已有的历史持仓补全卖出时间、卖出价格（无则用现价和创建时间填充，便于界面显示）
-- 在 Supabase SQL Editor 中执行。执行前可先查： select id, asset, sell_time, sell_price from public.teacher_positions where is_history = true;

update public.teacher_positions
set
  sell_time = coalesce(sell_time, created_at),
  sell_price = coalesce(sell_price, current_price)
where is_history = true
  and (sell_time is null or sell_price is null);
