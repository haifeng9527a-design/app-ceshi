-- Friend requests
CREATE TABLE IF NOT EXISTS friend_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id TEXT NOT NULL REFERENCES users(uid),
    to_user_id TEXT NOT NULL REFERENCES users(uid),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    message TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_friend_req_to ON friend_requests(to_user_id, status);
CREATE INDEX IF NOT EXISTS idx_friend_req_from ON friend_requests(from_user_id, status);

-- Friends (accepted relationships)
CREATE TABLE IF NOT EXISTS friends (
    user_id TEXT NOT NULL REFERENCES users(uid),
    friend_id TEXT NOT NULL REFERENCES users(uid),
    status TEXT NOT NULL DEFAULT 'accepted' CHECK (status IN ('accepted', 'blocked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, friend_id)
);
