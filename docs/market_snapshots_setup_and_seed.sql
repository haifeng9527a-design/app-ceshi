          -- 一步到位：先建表 + RLS，再插入初始数据
-- 在 Supabase SQL Editor 中一次性执行本文件即可

-- ========== 1. 建表 ==========
CREATE TABLE IF NOT EXISTS public.market_snapshots (
  type text PRIMARY KEY,
  payload jsonb NOT NULL DEFAULT '[]',
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.market_snapshots IS '领涨/领跌等行情快照，休市时 App 从此表读最近一次数据。type: gainers|losers|indices|forex|crypto';

ALTER TABLE public.market_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "market_snapshots_select" ON public.market_snapshots;
CREATE POLICY "market_snapshots_select"
  ON public.market_snapshots FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "market_snapshots_insert" ON public.market_snapshots;
CREATE POLICY "market_snapshots_insert"
  ON public.market_snapshots FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "market_snapshots_update" ON public.market_snapshots;
CREATE POLICY "market_snapshots_update"
  ON public.market_snapshots FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ========== 2. 插入初始数据（有则更新） ==========
INSERT INTO public.market_snapshots (type, payload, updated_at)
VALUES (
  'indices',
  '[
    {"symbol":"DJI","name":"道琼斯","close":38250,"change":120.5,"percent_change":0.32},
    {"symbol":"SPX","name":"标普500","close":4980,"change":15.2,"percent_change":0.31},
    {"symbol":"NDX","name":"纳斯达克","close":17680,"change":85,"percent_change":0.48},
    {"symbol":"HSI","name":"恒生指数","close":16520,"change":-120,"percent_change":-0.72},
    {"symbol":"N225","name":"日经225","close":38200,"change":200,"percent_change":0.53}
  ]'::jsonb,
  now()
)
ON CONFLICT (type) DO UPDATE SET payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at;

INSERT INTO public.market_snapshots (type, payload, updated_at)
VALUES (
  'forex',
  '[
    {"symbol":"EUR/USD","name":"欧元/美元","close":1.0856,"change":0.0012,"percent_change":0.11},
    {"symbol":"USD/JPY","name":"美元/日元","close":149.85,"change":-0.32,"percent_change":-0.21},
    {"symbol":"GBP/USD","name":"英镑/美元","close":1.268,"change":0.002,"percent_change":0.16},
    {"symbol":"AUD/USD","name":"澳元/美元","close":0.652,"change":-0.001,"percent_change":-0.15},
    {"symbol":"USD/CHF","name":"美元/瑞郎","close":0.878,"change":0.0005,"percent_change":0.06},
    {"symbol":"USD/CAD","name":"美元/加元","close":1.352,"change":-0.002,"percent_change":-0.15}
  ]'::jsonb,
  now()
)
ON CONFLICT (type) DO UPDATE SET payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at;

INSERT INTO public.market_snapshots (type, payload, updated_at)
VALUES (
  'crypto',
  '[
    {"symbol":"BTC/USD","name":"比特币","close":43250,"change":850,"percent_change":2.01},
    {"symbol":"ETH/USD","name":"以太坊","close":2280,"change":45,"percent_change":2.01},
    {"symbol":"SOL/USD","name":"Solana","close":98.5,"change":3.2,"percent_change":3.36},
    {"symbol":"XRP/USD","name":"瑞波币","close":0.525,"change":-0.012,"percent_change":-2.24},
    {"symbol":"DOGE/USD","name":"狗狗币","close":0.082,"change":0.0015,"percent_change":1.86},
    {"symbol":"AVAX/USD","name":"雪崩","close":36.8,"change":0.9,"percent_change":2.51}
  ]'::jsonb,
  now()
)
ON CONFLICT (type) DO UPDATE SET payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at;

-- 美股领涨（格式与 Polygon snapshot 一致，App 用 PolygonGainer.fromJson 解析）
INSERT INTO public.market_snapshots (type, payload, updated_at)
VALUES (
  'gainers',
  '[
    {"ticker":"NVDA","todaysChangePerc":4.2,"todaysChange":18.5,"day":{"c":458.2,"v":52000000}},
    {"ticker":"AAPL","todaysChangePerc":2.1,"todaysChange":4.2,"day":{"c":195.8,"v":48000000}},
    {"ticker":"TSLA","todaysChangePerc":5.8,"todaysChange":12.3,"day":{"c":224.5,"v":95000000}},
    {"ticker":"MSFT","todaysChangePerc":1.8,"todaysChange":6.8,"day":{"c":378.2,"v":22000000}},
    {"ticker":"META","todaysChangePerc":3.2,"todaysChange":15.2,"day":{"c":489.5,"v":18000000}},
    {"ticker":"GOOGL","todaysChangePerc":1.5,"todaysChange":2.4,"day":{"c":160.2,"v":25000000}},
    {"ticker":"AMZN","todaysChangePerc":2.4,"todaysChange":4.1,"day":{"c":178.5,"v":42000000}}
  ]'::jsonb,
  now()
)
ON CONFLICT (type) DO UPDATE SET payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at;

-- 美股领跌
INSERT INTO public.market_snapshots (type, payload, updated_at)
VALUES (
  'losers',
  '[
    {"ticker":"INTC","todaysChangePerc":-3.5,"todaysChange":-1.2,"day":{"c":33.2,"v":62000000}},
    {"ticker":"AMD","todaysChangePerc":-2.8,"todaysChange":-4.5,"day":{"c":156.8,"v":45000000}},
    {"ticker":"NFLX","todaysChangePerc":-1.9,"todaysChange":-8.2,"day":{"c":422.5,"v":5200000}},
    {"ticker":"PYPL","todaysChangePerc":-2.5,"todaysChange":-1.4,"day":{"c":56,"v":18000000}},
    {"ticker":"COIN","todaysChangePerc":-4.2,"todaysChange":-8.8,"day":{"c":200.5,"v":12000000}},
    {"ticker":"BA","todaysChangePerc":-1.8,"todaysChange":-3.2,"day":{"c":178,"v":8500000}},
    {"ticker":"DIS","todaysChangePerc":-2.1,"todaysChange":-1.9,"day":{"c":90.5,"v":12000000}}
  ]'::jsonb,
  now()
)
ON CONFLICT (type) DO UPDATE SET payload = EXCLUDED.payload, updated_at = EXCLUDED.updated_at;
