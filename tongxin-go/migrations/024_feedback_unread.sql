-- 投诉建议：加"用户未读回复"标记，用于 App 端红点/角标
ALTER TABLE feedbacks ADD COLUMN IF NOT EXISTS user_unread BOOLEAN NOT NULL DEFAULT FALSE;

-- partial index: 只对未读条目建索引，避免全表扫
CREATE INDEX IF NOT EXISTS idx_feedbacks_user_unread
    ON feedbacks(user_id) WHERE user_unread = TRUE;

-- Rollback:
--   ALTER TABLE feedbacks DROP COLUMN IF EXISTS user_unread;
