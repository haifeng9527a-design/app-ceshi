-- 自选股独立表（替代 app_config 中的 market_watchlist_user_<uid>）
-- 执行位置：Supabase SQL Editor

CREATE TABLE IF NOT EXISTS public.user_watchlists (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL,
  symbol TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, symbol)
);

CREATE INDEX IF NOT EXISTS idx_user_watchlists_user_id
  ON public.user_watchlists (user_id);

CREATE INDEX IF NOT EXISTS idx_user_watchlists_user_sort
  ON public.user_watchlists (user_id, sort_order);

COMMENT ON TABLE public.user_watchlists IS '用户自选股列表（每行一个 symbol）';
COMMENT ON COLUMN public.user_watchlists.user_id IS 'Firebase UID';
COMMENT ON COLUMN public.user_watchlists.symbol IS '标的代码（如 AAPL, EUR/USD）';
COMMENT ON COLUMN public.user_watchlists.sort_order IS '用户自定义排序，越小越靠前';

-- 可选：从旧 app_config key 迁移历史数据（已迁移过可跳过）
-- 旧 key 格式：market_watchlist_user_<uid>
INSERT INTO public.user_watchlists (user_id, symbol, sort_order)
SELECT
  REPLACE(ac.key, 'market_watchlist_user_', '') AS user_id,
  UPPER(TRIM(e.value)) AS symbol,
  e.ordinality::INTEGER AS sort_order
FROM public.app_config ac
CROSS JOIN LATERAL jsonb_array_elements_text(ac.value::jsonb) WITH ORDINALITY AS e(value, ordinality)
WHERE ac.key LIKE 'market_watchlist_user_%'
ON CONFLICT (user_id, symbol)
DO UPDATE SET
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();

