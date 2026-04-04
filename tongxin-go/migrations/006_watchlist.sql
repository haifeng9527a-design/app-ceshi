-- Watchlist
CREATE TABLE IF NOT EXISTS watchlist (
    user_id TEXT NOT NULL REFERENCES users(uid),
    symbol TEXT NOT NULL,
    symbol_type TEXT NOT NULL DEFAULT 'stock',
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, symbol)
);
