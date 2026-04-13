-- ═══════════════════════════════════════════════════════════
-- 014: Copy Trading V2 — 跟单引擎完整设置 + 溯源 + 日志
-- ═══════════════════════════════════════════════════════════

-- ── 扩展 copy_trading 设置 ──
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS copy_mode TEXT NOT NULL DEFAULT 'fixed'
    CHECK (copy_mode IN ('fixed', 'ratio'));
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS fixed_amount NUMERIC(20,8) DEFAULT 100;
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS max_single_margin NUMERIC(20,8) DEFAULT 500;
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS follow_symbols TEXT[] DEFAULT '{}';
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS leverage_mode TEXT NOT NULL DEFAULT 'trader'
    CHECK (leverage_mode IN ('trader', 'custom'));
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS custom_leverage INT;
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS tp_sl_mode TEXT NOT NULL DEFAULT 'trader'
    CHECK (tp_sl_mode IN ('trader', 'custom'));
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS custom_tp_ratio NUMERIC(10,4);
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS custom_sl_ratio NUMERIC(10,4);
ALTER TABLE copy_trading ADD COLUMN IF NOT EXISTS follow_direction TEXT NOT NULL DEFAULT 'both'
    CHECK (follow_direction IN ('both', 'long', 'short'));

-- ── 订单跟单溯源 ──
ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_copy_trade BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS source_order_id UUID;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS source_trader_id TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS copy_trading_id UUID;
CREATE INDEX IF NOT EXISTS idx_orders_source ON orders(source_order_id) WHERE is_copy_trade = true;

-- ── 仓位跟单溯源 ──
ALTER TABLE positions ADD COLUMN IF NOT EXISTS is_copy_trade BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE positions ADD COLUMN IF NOT EXISTS source_position_id UUID;
ALTER TABLE positions ADD COLUMN IF NOT EXISTS source_trader_id TEXT;
ALTER TABLE positions ADD COLUMN IF NOT EXISTS copy_trading_id UUID;
CREATE INDEX IF NOT EXISTS idx_positions_source ON positions(source_position_id) WHERE is_copy_trade = true;

-- ── 修改仓位唯一索引：允许不同 copy_trading_id 各一条 ──
DROP INDEX IF EXISTS idx_positions_user_symbol_side_open;
CREATE UNIQUE INDEX idx_positions_user_symbol_side_open
    ON positions(user_id, symbol, side, COALESCE(copy_trading_id::text, ''))
    WHERE status = 'open';

-- ── 跟单日志表 ──
CREATE TABLE IF NOT EXISTS copy_trade_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    copy_trading_id UUID NOT NULL,
    follower_id TEXT NOT NULL,
    trader_id TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('open','close','partial_close','skip')),
    source_order_id UUID,
    source_position_id UUID,
    follower_order_id UUID,
    follower_position_id UUID,
    symbol TEXT NOT NULL,
    side TEXT NOT NULL,
    trader_qty NUMERIC(20,8),
    follower_qty NUMERIC(20,8),
    trader_margin NUMERIC(20,8),
    follower_margin NUMERIC(20,8),
    follower_leverage INT,
    realized_pnl NUMERIC(20,8),
    skip_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_copy_logs_follower ON copy_trade_logs(follower_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_copy_logs_trader ON copy_trade_logs(trader_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_copy_logs_ct ON copy_trade_logs(copy_trading_id, created_at DESC);
