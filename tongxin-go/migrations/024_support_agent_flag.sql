ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_support_agent BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_users_support_agent
ON users(is_support_agent)
WHERE is_support_agent = true;

UPDATE users
SET is_support_agent = true,
    updated_at = NOW()
WHERE uid IN (
  SELECT agent_uid
  FROM support_assignments
  WHERE status = 'active'
);
