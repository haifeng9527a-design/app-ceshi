-- ═══════════════════════════════════════════════════════════
-- 032: Spot Trading — 数字货币 + 股票现货交易
-- ═══════════════════════════════════════════════════════════
-- 背景：平台已有合约 + 跟单，缺现货交易能力。本 migration 引入：
--   - spot_orders        : 现货订单（市价/限价、买/卖、待成交/已成交/已取消）
--   - spot_fee_schedule  : 现货费率表（按 VIP 等级，独立于合约费率）
--   - asset_ledger_entries.entry_type 扩展：spot_buy / spot_sell / spot_fee
--   - wallet_transactions.type 扩展：spot_buy / spot_sell / spot_fee
--
-- 资金链路：
--   买入：USDT.available -= cost+fee, BTC.available += qty   （市价）
--         USDT.available -= cost+fee → frozen += cost+fee     （限价挂单）
--   卖出：BTC.available -= qty, USDT.available += proceeds-fee（市价）
--         BTC.available -= qty → frozen += qty                （限价挂单）
--
-- 复用现有 asset_balances（main 账户下），无新建持仓表。
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ── 1. spot_orders 现货订单表 ──
CREATE TABLE IF NOT EXISTS spot_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    symbol          TEXT NOT NULL,                            -- 'BTC/USDT', 'AAPL/USD'
    base_asset      TEXT NOT NULL,                            -- 'BTC', 'AAPL'
    quote_asset     TEXT NOT NULL,                            -- 'USDT', 'USD'
    side            TEXT NOT NULL CHECK (side IN ('buy', 'sell')),
    order_type      TEXT NOT NULL CHECK (order_type IN ('market', 'limit')),
    qty             NUMERIC(20,8) NOT NULL CHECK (qty > 0),   -- 下单数量（基础资产）
    price           NUMERIC(20,8),                            -- 限价价格（市价为 NULL）
    filled_price    NUMERIC(20,8),                            -- 实际成交价
    filled_qty      NUMERIC(20,8) NOT NULL DEFAULT 0,         -- 实际成交量
    quote_qty       NUMERIC(20,8) NOT NULL DEFAULT 0,         -- 成交金额（quote）= filled_qty × filled_price
    frozen_amount   NUMERIC(20,8) NOT NULL DEFAULT 0,         -- 限价单冻结金额（buy=quote, sell=base）
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'filled', 'cancelled', 'rejected')),
    fee             NUMERIC(20,8) NOT NULL DEFAULT 0,
    fee_asset       TEXT NOT NULL DEFAULT 'USDT',
    fee_rate        NUMERIC(8,6) NOT NULL DEFAULT 0,          -- 实际收取的费率（snapshot）
    is_maker        BOOLEAN NOT NULL DEFAULT false,           -- 限价单成交时为 true
    reject_reason   TEXT,
    client_order_id TEXT,                                     -- 客户端幂等 ID（可选）
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    filled_at       TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_spot_orders_user_status
    ON spot_orders(user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_spot_orders_user_time
    ON spot_orders(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_spot_orders_symbol
    ON spot_orders(symbol);

-- 限价单挂单专用索引（用于价格触发扫描）
CREATE INDEX IF NOT EXISTS idx_spot_orders_pending
    ON spot_orders(symbol, side, price)
    WHERE status = 'pending';

-- 客户端幂等
CREATE UNIQUE INDEX IF NOT EXISTS uq_spot_orders_client_oid
    ON spot_orders(user_id, client_order_id)
    WHERE client_order_id IS NOT NULL;


-- ── 2. spot_fee_schedule 现货费率表 ──
CREATE TABLE IF NOT EXISTS spot_fee_schedule (
    vip_level    INT PRIMARY KEY,
    maker_fee    NUMERIC(8,6) NOT NULL CHECK (maker_fee >= 0 AND maker_fee <= 0.01),
    taker_fee    NUMERIC(8,6) NOT NULL CHECK (taker_fee >= 0 AND taker_fee <= 0.01),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO spot_fee_schedule (vip_level, maker_fee, taker_fee) VALUES
    (0, 0.001000, 0.001000),
    (1, 0.000800, 0.001000),
    (2, 0.000600, 0.000800),
    (3, 0.000400, 0.000600),
    (4, 0.000200, 0.000400)
ON CONFLICT (vip_level) DO NOTHING;


-- ── 3. asset_ledger_entries.entry_type 扩展 ──
ALTER TABLE asset_ledger_entries DROP CONSTRAINT IF EXISTS asset_ledger_entries_entry_type_check;
ALTER TABLE asset_ledger_entries
  ADD CONSTRAINT asset_ledger_entries_entry_type_check CHECK (
    entry_type IN (
        'deposit',
        'withdraw',
        'withdraw_fee',
        'system_adjustment',
        'reward',
        'spot_buy',     -- 现货买入：base 加，quote 减
        'spot_sell',    -- 现货卖出：base 减，quote 加
        'spot_fee',     -- 现货手续费扣除
        'spot_freeze',  -- 限价单冻结
        'spot_unfreeze' -- 限价单解冻（取消或成交）
    )
  );


-- ── 4. wallet_transactions.type 扩展 ──
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
    'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
    'copy_allocate','copy_withdraw','copy_pnl_settle',
    'copy_profit_share_out','copy_profit_share_in',
    'referral_commission_in','agent_override_in',
    'spot_buy','spot_sell','spot_fee'
  ));


-- ── 5. spot_supported_symbols 支持的交易对（轻量配置表） ──
-- 用 DB 表而非硬编码，方便 admin 随时增删
CREATE TABLE IF NOT EXISTS spot_supported_symbols (
    symbol         TEXT PRIMARY KEY,                          -- 'BTC/USDT'
    base_asset     TEXT NOT NULL,                             -- 'BTC'
    quote_asset    TEXT NOT NULL,                             -- 'USDT'
    category       TEXT NOT NULL CHECK (category IN ('crypto', 'stocks')),
    display_name   TEXT NOT NULL,                             -- '比特币/USDT'
    min_qty        NUMERIC(20,8) NOT NULL DEFAULT 0.00000001,
    qty_precision  INT NOT NULL DEFAULT 8,                    -- 数量小数位
    price_precision INT NOT NULL DEFAULT 2,                   -- 价格小数位
    is_active      BOOLEAN NOT NULL DEFAULT true,
    sort_order     INT NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spot_symbols_category_active
    ON spot_supported_symbols(category, is_active, sort_order);

-- 初始 seed：50 个加密 + 20 个美股
INSERT INTO spot_supported_symbols (symbol, base_asset, quote_asset, category, display_name, qty_precision, price_precision, sort_order) VALUES
    ('BTC/USDT', 'BTC', 'USDT', 'crypto', '比特币',     6, 2, 1),
    ('ETH/USDT', 'ETH', 'USDT', 'crypto', '以太坊',     5, 2, 2),
    ('BNB/USDT', 'BNB', 'USDT', 'crypto', '币安币',     4, 2, 3),
    ('SOL/USDT', 'SOL', 'USDT', 'crypto', 'Solana',     3, 2, 4),
    ('XRP/USDT', 'XRP', 'USDT', 'crypto', 'Ripple',     2, 4, 5),
    ('DOGE/USDT', 'DOGE', 'USDT', 'crypto', '狗狗币',   1, 5, 6),
    ('ADA/USDT', 'ADA', 'USDT', 'crypto', 'Cardano',    1, 4, 7),
    ('AVAX/USDT', 'AVAX', 'USDT', 'crypto', 'Avalanche', 2, 2, 8),
    ('DOT/USDT', 'DOT', 'USDT', 'crypto', 'Polkadot',   2, 3, 9),
    ('MATIC/USDT', 'MATIC', 'USDT', 'crypto', 'Polygon', 1, 4, 10),
    ('LINK/USDT', 'LINK', 'USDT', 'crypto', 'Chainlink', 2, 3, 11),
    ('UNI/USDT', 'UNI', 'USDT', 'crypto', 'Uniswap',    2, 3, 12),
    ('LTC/USDT', 'LTC', 'USDT', 'crypto', '莱特币',     3, 2, 13),
    ('TRX/USDT', 'TRX', 'USDT', 'crypto', 'Tron',       0, 5, 14),
    ('ATOM/USDT', 'ATOM', 'USDT', 'crypto', 'Cosmos',   2, 3, 15),
    ('NEAR/USDT', 'NEAR', 'USDT', 'crypto', 'NEAR',     2, 3, 16),
    ('APT/USDT', 'APT', 'USDT', 'crypto', 'Aptos',      2, 3, 17),
    ('ARB/USDT', 'ARB', 'USDT', 'crypto', 'Arbitrum',   1, 4, 18),
    ('OP/USDT', 'OP', 'USDT', 'crypto', 'Optimism',     1, 4, 19),
    ('SHIB/USDT', 'SHIB', 'USDT', 'crypto', 'Shiba Inu', 0, 8, 20),
    -- 股票（CFD/Token 化）
    ('AAPL/USD', 'AAPL', 'USD', 'stocks', '苹果',       2, 2, 101),
    ('TSLA/USD', 'TSLA', 'USD', 'stocks', '特斯拉',     2, 2, 102),
    ('NVDA/USD', 'NVDA', 'USD', 'stocks', '英伟达',     2, 2, 103),
    ('MSFT/USD', 'MSFT', 'USD', 'stocks', '微软',       2, 2, 104),
    ('AMZN/USD', 'AMZN', 'USD', 'stocks', '亚马逊',     2, 2, 105),
    ('GOOGL/USD', 'GOOGL', 'USD', 'stocks', '谷歌',     2, 2, 106),
    ('META/USD', 'META', 'USD', 'stocks', 'Meta',       2, 2, 107),
    ('AMD/USD', 'AMD', 'USD', 'stocks', 'AMD',          2, 2, 108),
    ('NFLX/USD', 'NFLX', 'USD', 'stocks', 'Netflix',    2, 2, 109),
    ('COIN/USD', 'COIN', 'USD', 'stocks', 'Coinbase',   2, 2, 110),
    ('PLTR/USD', 'PLTR', 'USD', 'stocks', 'Palantir',   2, 2, 111),
    ('UBER/USD', 'UBER', 'USD', 'stocks', 'Uber',       2, 2, 112),
    ('SHOP/USD', 'SHOP', 'USD', 'stocks', 'Shopify',    2, 2, 113),
    ('SPOT/USD', 'SPOT', 'USD', 'stocks', 'Spotify',    2, 2, 114),
    ('MSTR/USD', 'MSTR', 'USD', 'stocks', 'MicroStrategy', 2, 2, 115),
    ('GME/USD', 'GME', 'USD', 'stocks', 'GameStop',     2, 2, 116),
    ('AMC/USD', 'AMC', 'USD', 'stocks', 'AMC',          2, 2, 117),
    ('SNAP/USD', 'SNAP', 'USD', 'stocks', 'Snap',       2, 2, 118),
    ('SQ/USD', 'SQ', 'USD', 'stocks', 'Block',          2, 2, 119),
    ('RBLX/USD', 'RBLX', 'USD', 'stocks', 'Roblox',     2, 2, 120)
ON CONFLICT (symbol) DO NOTHING;


COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考，正常不执行）
-- ─────────────────────────────────────────────
-- BEGIN;
-- ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
-- ALTER TABLE wallet_transactions
--   ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
--     'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
--     'copy_allocate','copy_withdraw','copy_pnl_settle',
--     'copy_profit_share_out','copy_profit_share_in',
--     'referral_commission_in','agent_override_in'));
--
-- ALTER TABLE asset_ledger_entries DROP CONSTRAINT IF EXISTS asset_ledger_entries_entry_type_check;
-- ALTER TABLE asset_ledger_entries
--   ADD CONSTRAINT asset_ledger_entries_entry_type_check CHECK (
--     entry_type IN ('deposit','withdraw','withdraw_fee','system_adjustment','reward'));
--
-- DROP TABLE IF EXISTS spot_supported_symbols;
-- DROP INDEX IF EXISTS uq_spot_orders_client_oid;
-- DROP INDEX IF EXISTS idx_spot_orders_pending;
-- DROP INDEX IF EXISTS idx_spot_orders_symbol;
-- DROP INDEX IF EXISTS idx_spot_orders_user_time;
-- DROP INDEX IF EXISTS idx_spot_orders_user_status;
-- DROP TABLE IF EXISTS spot_orders;
-- DROP TABLE IF EXISTS spot_fee_schedule;
-- COMMIT;
