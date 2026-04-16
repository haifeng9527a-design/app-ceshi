-- ═══════════════════════════════════════════════════════════
-- 038: users.dashboard_prefs
--      —— 代理商自定义看板偏好（M9：可拖拽模块顺序 / 隐藏）
-- ═══════════════════════════════════════════════════════════
-- 背景：
--   Sprint 4 要做 M9 自定义看板：dashboard 上多个模块可以拖拽排序、隐藏。
--   为了不新增一张表（5 条用户数据，表开销反而更大），直接在 users 上挂一个 jsonb。
--
-- 结构约定（前端演进不破坏）：
--   {
--     "modules": [
--       { "id": "risk-radar",    "hidden": false },
--       { "id": "kpi-lifetime",  "hidden": false },
--       { "id": "team-treemap",  "hidden": false },
--       ...
--     ]
--   }
--
-- 兼容性：
--   - DEFAULT '{}'::jsonb，已有 5 条用户数据无需 backfill
--   - 前端读不到 modules key 时 fallback 默认顺序，所以老数据也能渲染
-- ═══════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS dashboard_prefs jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚
-- ─────────────────────────────────────────────
-- BEGIN;
-- ALTER TABLE users DROP COLUMN IF EXISTS dashboard_prefs;
-- COMMIT;
-- ═══════════════════════════════════════════════════════════
