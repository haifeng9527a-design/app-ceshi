-- 股票报价缓存表：字段平铺，便于在表编辑器里直接查看
-- 在 Supabase Dashboard -> SQL Editor 中执行整段

DROP TABLE IF EXISTS stock_quote_cache;

CREATE TABLE stock_quote_cache (
  id BIGSERIAL PRIMARY KEY,
  symbol TEXT NOT NULL UNIQUE,
  name TEXT,
  close NUMERIC,
  "change" NUMERIC,
  percent_change NUMERIC,
  open NUMERIC,
  high NUMERIC,
  low NUMERIC,
  volume BIGINT,
  prev_close NUMERIC,
  error_reason TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stock_quote_cache_symbol ON stock_quote_cache (symbol);
CREATE INDEX IF NOT EXISTS idx_stock_quote_cache_updated_at ON stock_quote_cache (updated_at DESC);

COMMENT ON TABLE stock_quote_cache IS '股票报价缓存：序列号 id，股票代码 symbol，名称 name，最新价 close，开盘 open，最高 high，最低 low，涨跌额 change，涨跌幅 percent_change，成交量 volume，昨收 prev_close，错误原因 error_reason，更新时间 updated_at';

ALTER TABLE stock_quote_cache ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow anon read write stock_quote_cache" ON stock_quote_cache;
CREATE POLICY "Allow anon read write stock_quote_cache"
  ON stock_quote_cache
  FOR ALL
  TO anon
  USING (true)
  WITH CHECK (true);
