-- ═══════════════════════════════════════════════════════════
-- 036: notifications — 站内通知中心
-- ═══════════════════════════════════════════════════════════
-- 背景：
--   代理商后台 v2 的「通知 Bell」+「实时推送」需要持久化每条通知。
--   实时推送复用现有 ChatHub.BroadcastToUser；持久化保证用户离线后
--   再上线仍能看到未读消息。
--
-- 设计：
--   - 一行 = 一条通知。kind 区分场景，payload 存 jsonb 关联 ID。
--   - read_at 为 NULL 表示未读；前端 unread badge 计数依赖
--     idx_notifications_user_unread 部分索引快速 COUNT(*)。
--   - 不分表，预期数据量级：5 用户 × 10 条/天 × 90 天 ≈ 4500 行，
--     足够用直查 + 单列索引。
-- ═══════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uid    varchar NOT NULL REFERENCES users(uid),
  kind        varchar NOT NULL,            -- 'risk_alert' | 'commission_settled' | 'weekly_report' | ...
  title       varchar NOT NULL,
  body        text NOT NULL,
  payload     jsonb,                       -- 关联 invitee_uid / event_id / png_url / threshold_id 等
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 列出用户的通知（按时间倒序）
CREATE INDEX IF NOT EXISTS idx_notifications_user_created_at
  ON notifications(user_uid, created_at DESC);

-- 未读计数 / 未读列表的部分索引
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON notifications(user_uid, created_at DESC)
  WHERE read_at IS NULL;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考）
-- ─────────────────────────────────────────────
-- BEGIN;
-- DROP INDEX IF EXISTS idx_notifications_user_unread;
-- DROP INDEX IF EXISTS idx_notifications_user_created_at;
-- DROP TABLE IF EXISTS notifications;
-- COMMIT;
-- ═══════════════════════════════════════════════════════════
