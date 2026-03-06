-- 外汇缓存表（供 tongxin-backend 写入）
-- 执行环境：Supabase SQL Editor

CREATE TABLE IF NOT EXISTS public.forex_pair_cache (
  symbol TEXT PRIMARY KEY,
  name TEXT,
  market TEXT DEFAULT 'forex',
  updated_at_ms BIGINT NOT NULL,
  last_quote_at_ms BIGINT
);

CREATE TABLE IF NOT EXISTS public.forex_quote_cache (
  symbol TEXT PRIMARY KEY,
  payload_json JSONB NOT NULL,
  updated_at_ms BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_forex_pair_cache_updated_at_ms
  ON public.forex_pair_cache(updated_at_ms DESC);

CREATE INDEX IF NOT EXISTS idx_forex_quote_cache_updated_at_ms
  ON public.forex_quote_cache(updated_at_ms DESC);

ALTER TABLE public.forex_pair_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forex_quote_cache ENABLE ROW LEVEL SECURITY;

-- 后端使用 service_role 写入，客户端只读可按需放开
DROP POLICY IF EXISTS "forex_pair_cache_select" ON public.forex_pair_cache;
CREATE POLICY "forex_pair_cache_select"
  ON public.forex_pair_cache FOR SELECT
  TO authenticated, anon
  USING (true);

DROP POLICY IF EXISTS "forex_pair_cache_insert" ON public.forex_pair_cache;
CREATE POLICY "forex_pair_cache_insert"
  ON public.forex_pair_cache FOR INSERT
  TO authenticated, anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "forex_pair_cache_update" ON public.forex_pair_cache;
CREATE POLICY "forex_pair_cache_update"
  ON public.forex_pair_cache FOR UPDATE
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "forex_quote_cache_select" ON public.forex_quote_cache;
CREATE POLICY "forex_quote_cache_select"
  ON public.forex_quote_cache FOR SELECT
  TO authenticated, anon
  USING (true);

DROP POLICY IF EXISTS "forex_quote_cache_insert" ON public.forex_quote_cache;
CREATE POLICY "forex_quote_cache_insert"
  ON public.forex_quote_cache FOR INSERT
  TO authenticated, anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "forex_quote_cache_update" ON public.forex_quote_cache;
CREATE POLICY "forex_quote_cache_update"
  ON public.forex_quote_cache FOR UPDATE
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);
