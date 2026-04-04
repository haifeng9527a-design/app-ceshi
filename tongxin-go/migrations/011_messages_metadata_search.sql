-- Structured payloads for cards / AI (Postgres remains source of truth)
ALTER TABLE messages ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Full-text search helper (simple config works for mixed symbols + Latin/CJK when content stored as text)
CREATE INDEX IF NOT EXISTS idx_messages_conv_fts ON messages
USING gin (to_tsvector('simple', coalesce(content, '')));
