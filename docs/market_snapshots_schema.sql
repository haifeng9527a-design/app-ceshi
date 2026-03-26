-- 行情快照表：存领涨/领跌等，供休市时新用户或未缓存用户读取
-- 执行：在 Supabase SQL Editor 中运行

-- 表：按 type 存一份最新快照（gainers / losers）
CREATE TABLE IF NOT EXISTS public.market_snapshots (
  type text PRIMARY KEY,
  payload jsonb NOT NULL DEFAULT '[]',
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.market_snapshots IS '领涨/领跌等行情快照，休市时 App 从此表读最近一次数据。type: gainers|losers|indices|forex|crypto';

-- RLS：所有人可读（含未登录）；仅登录用户可写（开市时任意用户拉取到数据会写入，大家共享）
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
