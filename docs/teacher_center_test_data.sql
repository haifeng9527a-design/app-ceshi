-- 为真实用户 tufei (OFxSf3otmqaEJo7vvDwgJNORfbG2) 插入交易员中心/关注页测试数据
-- 在 Supabase SQL Editor 中执行后，该用户登录并进入「关注」tab 将看到自己的数据。
-- 注意：重复执行会多出重复的策略、持仓与交易记录；如需重跑可先删除该 user_id 在相关表中的数据。

-- 目标用户（与 user_profiles 中一致）
-- user_id: OFxSf3otmqaEJo7vvDwgJNORfbG2  display_name: tufei

-- ========== 1) 交易员档案（关注页显示该用户自己的名字 + 测试用盈亏/策略） ==========
insert into public.teacher_profiles (
  user_id,
  display_name,
  real_name,
  title,
  bio,
  status,
  wins,
  losses,
  rating,
  today_strategy,
  pnl_current,
  pnl_month,
  pnl_year,
  pnl_total,
  tags,
  updated_at
) values (
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  'tufei',
  'tufei',
  '财富管理导师',
  '10 年投研与实战培训经验，擅长资产配置与风控。',
  'approved',
  28,
  6,
  96,
  '稳健型配置：核心仓位控制 60%，分散至低波动资产。',
  18600,
  35600,
  128400,
  356900,
  array['财富管理', '资产配置', '风控'],
  now()
) on conflict (user_id) do update set
  display_name = excluded.display_name,
  real_name = excluded.real_name,
  title = excluded.title,
  bio = excluded.bio,
  status = excluded.status,
  wins = excluded.wins,
  losses = excluded.losses,
  rating = excluded.rating,
  today_strategy = excluded.today_strategy,
  pnl_current = excluded.pnl_current,
  pnl_month = excluded.pnl_month,
  pnl_year = excluded.pnl_year,
  pnl_total = excluded.pnl_total,
  tags = excluded.tags,
  updated_at = excluded.updated_at;

-- ========== 2) 发布交易策略 ==========
insert into public.trade_strategies (
  teacher_id,
  title,
  summary,
  status,
  updated_at
) values (
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '核心策略',
  '稳健型配置：核心仓位控制 60%，分散至低波动资产。',
  'published',
  now()
);

insert into public.trade_strategies (
  teacher_id,
  title,
  summary,
  status,
  updated_at
) values
  ('OFxSf3otmqaEJo7vvDwgJNORfbG2', '防御型组合调整', '适度降低权益仓位，提升流动性。', 'published', now() - interval '2 days'),
  ('OFxSf3otmqaEJo7vvDwgJNORfbG2', '均衡型配置思路', '保持中性仓位，关注估值修复机会。', 'published', now() - interval '4 days');

-- ========== 3) 目前持仓与历史持仓 ==========
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
  is_history
) values (
  'OFxSf3otmqaEJo7vvDwgJNORfbG2',
  '稳健债券',
  '2026-01-20',
  2000,
  98.50,
  98.10,
  101.20,
  3400,
  3.2,
  3200,
  false
);

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
  is_history
) values
  ('OFxSf3otmqaEJo7vvDwgJNORfbG2', '红利指数', '2026-01-12', 1500, 102.30, 101.80, 106.90, 6900, 4.5, 6800, true),
  ('OFxSf3otmqaEJo7vvDwgJNORfbG2', '国债ETF', '2025-12-10', 1200, 101.40, 101.10, 100.20, -1100, -0.9, -1100, true);

-- ========== 4) 历史交易记录 ==========
insert into public.trade_records (
  teacher_id,
  symbol,
  side,
  pnl,
  trade_time,
  asset,
  buy_time,
  buy_shares,
  buy_price,
  sell_time,
  sell_shares,
  sell_price,
  pnl_ratio,
  pnl_amount
) values
  ('OFxSf3otmqaEJo7vvDwgJNORfbG2', '中证红利ETF', 'sell', 9600, '2026-02-07', '中证红利ETF', '2026-02-05', 2000, 98.50, '2026-02-07', 2000, 103.20, 4.8, 9600),
  ('OFxSf3otmqaEJo7vvDwgJNORfbG2', '国债ETF', 'sell', -1800, '2026-02-04', '国债ETF', '2026-02-01', 1500, 102.10, '2026-02-04', 1500, 100.90, -1.2, -1800),
  ('OFxSf3otmqaEJo7vvDwgJNORfbG2', '稳健债券', 'hold', 3200, '2026-01-20', '稳健债券', '2026-01-20', 2000, 98.50, null, null, null, 3.2, 3200);
