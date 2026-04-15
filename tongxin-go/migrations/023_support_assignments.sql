-- Support assignments
CREATE TABLE IF NOT EXISTS support_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    agent_uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    assigned_by TEXT REFERENCES users(uid) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'transferred', 'closed')),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_support_assignments_active_customer
    ON support_assignments(customer_uid)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_support_assignments_agent
    ON support_assignments(agent_uid, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_assignments_conversation
    ON support_assignments(conversation_id);
