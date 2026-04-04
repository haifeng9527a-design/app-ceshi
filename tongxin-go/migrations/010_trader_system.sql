-- 交易员申请表
CREATE TABLE IF NOT EXISTS trader_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(uid),
    status TEXT NOT NULL DEFAULT 'pending'
           CHECK (status IN ('pending','approved','rejected')),
    -- 基础资料
    real_name TEXT NOT NULL,
    id_number TEXT NOT NULL,
    phone TEXT NOT NULL,
    nationality TEXT NOT NULL DEFAULT '',
    address TEXT NOT NULL DEFAULT '',
    -- 交易资质
    experience_years INT NOT NULL DEFAULT 0,
    markets TEXT[] NOT NULL DEFAULT '{}',
    capital_source TEXT NOT NULL DEFAULT '',
    estimated_volume TEXT NOT NULL DEFAULT '',
    -- 风险声明
    risk_agreed BOOLEAN NOT NULL DEFAULT false,
    terms_agreed BOOLEAN NOT NULL DEFAULT false,
    -- 审核
    reviewed_by TEXT REFERENCES users(uid),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_trader_apps_user ON trader_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_trader_apps_status ON trader_applications(status);

-- users 表扩展交易员字段
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_trader BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS trader_approved_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS allow_copy_trading BOOLEAN NOT NULL DEFAULT false;

-- 交易员统计数据（定期聚合，供排行榜和交易员中心使用）
CREATE TABLE IF NOT EXISTS trader_stats (
    user_id TEXT PRIMARY KEY REFERENCES users(uid),
    total_trades INT NOT NULL DEFAULT 0,
    win_trades INT NOT NULL DEFAULT 0,
    total_pnl NUMERIC NOT NULL DEFAULT 0,
    win_rate NUMERIC NOT NULL DEFAULT 0,
    avg_pnl NUMERIC NOT NULL DEFAULT 0,
    max_drawdown NUMERIC NOT NULL DEFAULT 0,
    followers_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 跟单关系表
CREATE TABLE IF NOT EXISTS copy_trading (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id TEXT NOT NULL REFERENCES users(uid),
    trader_id TEXT NOT NULL REFERENCES users(uid),
    status TEXT NOT NULL DEFAULT 'active'
           CHECK (status IN ('active','paused','stopped')),
    copy_ratio NUMERIC NOT NULL DEFAULT 1.0,
    max_position NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(follower_id, trader_id)
);
CREATE INDEX IF NOT EXISTS idx_copy_follower ON copy_trading(follower_id);
CREATE INDEX IF NOT EXISTS idx_copy_trader ON copy_trading(trader_id, status);
