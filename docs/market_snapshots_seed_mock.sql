-- 行情快照表：初始数据种子（相当于“先插入一批数据到表里”）
-- 若表尚未创建，请先执行 docs/market_snapshots_schema.sql，或直接执行 docs/market_snapshots_setup_and_seed.sql（建表+种子一步完成）
-- 之后 App 会：有最新接口数据时自动更新并写入此表，无最新数据时从表里读缓存展示

-- 指数快照（type = indices）
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

-- 外汇快照（type = forex）
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

-- 加密货币快照（type = crypto）
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

-- 美股领涨（格式与 Polygon snapshot 一致）
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
