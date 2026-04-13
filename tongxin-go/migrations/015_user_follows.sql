-- 015: Independent user follow system (separate from copy trading)
CREATE TABLE IF NOT EXISTS user_follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(uid),
    trader_id TEXT NOT NULL REFERENCES users(uid),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, trader_id)
);
CREATE INDEX IF NOT EXISTS idx_user_follows_user ON user_follows(user_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_trader ON user_follows(trader_id);
