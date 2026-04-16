-- ═══════════════════════════════════════════════════════════
-- 035: users.last_login_at — 用于风险雷达识别 7 天无活跃下级
-- ═══════════════════════════════════════════════════════════
-- 背景：
--   代理商后台 v2「风险雷达」模块需要识别「7 天无活跃下级」信号，
--   原 users 表无登录时间字段。
--
-- 改动：
--   1) 新增 users.last_login_at timestamptz （nullable）
--   2) 部分索引加速「未活跃用户扫描」（WHERE last_login_at IS NOT NULL
--      允许尚未登录的旧用户不进索引，节省空间）
--
-- 兼容性 / 回滚：
--   - 字段 nullable，不影响任何现有 SELECT
--   - 老数据 last_login_at = NULL，登录后才会被填充
--   - 回滚 SQL 在文件末尾
-- ═══════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS last_login_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_users_last_login_at
  ON users(last_login_at)
  WHERE last_login_at IS NOT NULL;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考）
-- ─────────────────────────────────────────────
-- BEGIN;
-- DROP INDEX IF EXISTS idx_users_last_login_at;
-- ALTER TABLE users DROP COLUMN IF EXISTS last_login_at;
-- COMMIT;
-- ═══════════════════════════════════════════════════════════
