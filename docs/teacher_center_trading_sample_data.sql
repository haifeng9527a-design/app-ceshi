-- 为指定用户（tufei / OFxSf3otmqaEJo7vvDwgJNORfbG2）创建持仓数据与历史交易数据
-- 执行后会在「交易员中心」-「交易记录」中显示
-- 依赖：teacher_roles_schema.sql + teacher_ui_schema.sql（trade_records 扩展列、teacher_positions 表）

-- ========== 1) 历史交易记录（trade_records，含买入/卖出明细） ==========
-- 需已执行 teacher_ui_schema 的 alter，使 trade_records 有 buy_time, buy_price, sell_time, sell_price 等列

insert into public.trade_records (
  teacher_id,
  symbol,
  side,
  buy_time,
  buy_price,
  buy_shares,
  sell_time,
  sell_price,
  sell_shares,
  pnl,
  pnl_amount,
  trade_time,
  created_at
) values
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '600519',
  'buy',
  '2026-01-15 10:30:00+08',
  1680.00,
  100,
  '2026-01-20 14:00:00+08',
  1720.00,
  100,
  4000,
  4000,
  '2026-01-20 14:00:00+08',
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '000858',
  'buy',
  '2026-01-18 09:45:00+08',
  158.50,
  500,
  '2026-01-22 11:20:00+08',
  162.00,
  500,
  1750,
  1750,
  '2026-01-22 11:20:00+08',
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '601318',
  'buy',
  '2026-01-10 13:00:00+08',
  42.80,
  1000,
  '2026-01-25 10:15:00+08',
  41.20,
  1000,
  -1600,
  -1600,
  '2026-01-25 10:15:00+08',
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '300750',
  'buy',
  '2026-02-01 10:00:00+08',
  185.00,
  200,
  '2026-02-08 15:30:00+08',
  192.50,
  200,
  1500,
  1500,
  '2026-02-08 15:30:00+08',
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '000333',
  'buy',
  '2025-12-05 11:00:00+08',
  58.20,
  800,
  '2025-12-18 14:30:00+08',
  61.50,
  800,
  2640,
  2640,
  '2025-12-18 14:30:00+08',
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '002594',
  'buy',
  '2025-12-12 09:50:00+08',
  228.00,
  150,
  '2025-12-28 10:00:00+08',
  235.00,
  150,
  1050,
  1050,
  '2025-12-28 10:00:00+08',
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '601012',
  'buy',
  '2026-01-05 10:15:00+08',
  18.50,
  2000,
  '2026-01-28 11:00:00+08',
  17.80,
  2000,
  -1400,
  -1400,
  '2026-01-28 11:00:00+08',
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '稳健债券',
  'buy',
  '2026-01-20 09:00:00+08',
  98.10,
  2000,
  '2026-02-05 15:00:00+08',
  99.80,
  2000,
  3400,
  3400,
  '2026-02-05 15:00:00+08',
  now()
);

-- ========== 2) 持仓数据（teacher_positions，当前持仓） ==========

insert into public.teacher_positions (
  teacher_id,
  asset,
  buy_time,
  buy_shares,
  buy_price,
  cost_price,
  current_price,
  floating_pnl,
  pnl_ratio,
  pnl_amount,
  is_history,
  created_at
) values
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '600519',
  '2026-02-10 09:35:00+08',
  50,
  1710.00,
  1710.00,
  1725.00,
  750,
  0.88,
  750,
  false,
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '000858',
  '2026-02-11 10:20:00+08',
  300,
  161.00,
  161.00,
  159.50,
  -450,
  -0.93,
  -450,
  false,
  now()
);

-- ========== 3) 历史持仓（teacher_positions，is_history = true，需填 sell_time、sell_price） ==========

insert into public.teacher_positions (
  teacher_id,
  asset,
  buy_time,
  buy_shares,
  buy_price,
  cost_price,
  sell_time,
  sell_price,
  pnl_ratio,
  pnl_amount,
  is_history,
  created_at
) values
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '000333',
  '2025-12-05 11:00:00+08',
  800,
  58.20,
  58.20,
  '2025-12-20 14:30:00+08',
  61.50,
  5.67,
  2640,
  true,
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '002594',
  '2025-12-12 09:50:00+08',
  150,
  228.00,
  228.00,
  '2025-12-28 10:00:00+08',
  235.00,
  3.07,
  1050,
  true,
  now()
),
(
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '601318',
  '2026-01-10 13:00:00+08',
  1000,
  42.80,
  42.80,
  '2026-01-15 09:35:00+08',
  41.20,
  -3.74,
  -1600,
  true,
  now()
);
