-- Trader strategies (articles published by certified traders)
CREATE TABLE IF NOT EXISTS trader_strategies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id TEXT NOT NULL REFERENCES users(uid),
    title TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    content_html TEXT NOT NULL DEFAULT '',
    cover_image TEXT DEFAULT '',
    category TEXT DEFAULT '',
    tags TEXT[] DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'published'
           CHECK (status IN ('draft','published','archived')),
    views INT NOT NULL DEFAULT 0,
    likes INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_trader_strategies_author ON trader_strategies(author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_trader_strategies_status ON trader_strategies(status, created_at DESC);

-- Likes junction table
CREATE TABLE IF NOT EXISTS trader_strategy_likes (
    strategy_id UUID NOT NULL REFERENCES trader_strategies(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(uid),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (strategy_id, user_id)
);
