CREATE TABLE IF NOT EXISTS daily_revenue (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL UNIQUE,
    fee_income NUMERIC(20,8) NOT NULL DEFAULT 0,
    liquidation_income NUMERIC(20,8) NOT NULL DEFAULT 0,
    total_income NUMERIC(20,8) NOT NULL DEFAULT 0,
    trade_count INT NOT NULL DEFAULT 0,
    liquidation_count INT NOT NULL DEFAULT 0,
    active_users INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_daily_revenue_date ON daily_revenue(date);
