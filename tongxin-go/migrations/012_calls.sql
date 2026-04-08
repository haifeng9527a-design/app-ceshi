CREATE TABLE IF NOT EXISTS calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    initiator_id TEXT NOT NULL REFERENCES users(uid),
    room_name TEXT NOT NULL,
    call_type TEXT NOT NULL DEFAULT 'voice',
    status TEXT NOT NULL DEFAULT 'ringing',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    answered_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    ended_by TEXT REFERENCES users(uid),
    end_reason TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_calls_conversation_created ON calls(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calls_status ON calls(status, started_at DESC);
