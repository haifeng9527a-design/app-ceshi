-- Teachers (traders)
CREATE TABLE IF NOT EXISTS teachers (
    user_id TEXT PRIMARY KEY REFERENCES users(uid),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    bio TEXT DEFAULT '',
    specialties TEXT[] DEFAULT '{}',
    rating DOUBLE PRECISION NOT NULL DEFAULT 0,
    follower_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Teacher strategies
CREATE TABLE IF NOT EXISTS teacher_strategies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id TEXT NOT NULL REFERENCES teachers(user_id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    images TEXT[] DEFAULT '{}',
    category TEXT DEFAULT '',
    likes INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_strategies_teacher ON teacher_strategies(teacher_id, created_at DESC);

-- Teacher followers
CREATE TABLE IF NOT EXISTS teacher_followers (
    teacher_id TEXT NOT NULL REFERENCES teachers(user_id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(uid),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (teacher_id, user_id)
);

-- Strategy likes
CREATE TABLE IF NOT EXISTS strategy_likes (
    strategy_id UUID NOT NULL REFERENCES teacher_strategies(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(uid),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (strategy_id, user_id)
);
