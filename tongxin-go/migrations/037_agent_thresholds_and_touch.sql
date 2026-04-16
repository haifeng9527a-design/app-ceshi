-- ═══════════════════════════════════════════════════════════
-- 037: agent_thresholds + touch_history
--      —— 智能阈值告警 + 一键触达历史
-- ═══════════════════════════════════════════════════════════
-- 背景：
--   Sprint 2 要做：
--     M5 智能阈值告警：代理自定义规则 → cron 每 10 分钟扫描 → 触发
--                    notification.Create({kind:'risk_alert'})
--     M3 一键触达：    选下级 + 模板 + 渠道 → 写一条触达历史，状态用于回执查询
--
--   两张表同期建：
--     - 共用 agent_uid → users(uid) 外键
--     - touch_history.invitee_uids 用 text[] 数组，避免 N:M 中间表
--     - touch_history.channels 同理
--
-- 兼容性 / 回滚：
--   - 全新表，不影响任何现有 SELECT/INSERT
--   - 回滚 SQL 在文件末尾
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ── 1. agent_thresholds：代理自定义阈值规则 ──
-- metric 枚举（应用层校验，不在 DB 加 CHECK，便于未来扩展）：
--   'active_invitees_7d'    7 天活跃下级人数
--   'pending_commission'    pending 状态的待结算返佣总额
--   'month_volume_drop_pct' 本月交易量环比下跌百分比
--   'lifetime_commission'   累计返佣到达里程碑
CREATE TABLE IF NOT EXISTS agent_thresholds (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_uid         varchar NOT NULL REFERENCES users(uid),
  metric            varchar NOT NULL,
  op                varchar NOT NULL,          -- 'lt' | 'gt'
  threshold_value   numeric NOT NULL,
  is_enabled        boolean NOT NULL DEFAULT true,
  last_triggered_at timestamptz,               -- 防抖：cron 同一阈值 24h 内不重复推送
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_agent_thresholds_op CHECK (op IN ('lt', 'gt')),
  CONSTRAINT uq_agent_thresholds_agent_metric UNIQUE (agent_uid, metric)
);

CREATE INDEX IF NOT EXISTS idx_agent_thresholds_enabled
  ON agent_thresholds(is_enabled)
  WHERE is_enabled = true;

-- ── 2. touch_history：一键触达历史 ──
-- template 枚举（应用层）：
--   'reactivate'           召回未活跃下级
--   'thank_you'            感谢活跃下级
--   'commission_arrived'   通知返佣到账
--
-- channels：'internal' | 'email' | 'sms' | 'wechat' 任意组合
-- status:    'pending' | 'success' | 'partial' | 'failed'
CREATE TABLE IF NOT EXISTS touch_history (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_uid     varchar NOT NULL REFERENCES users(uid),
  invitee_uids  text[]  NOT NULL,
  template      varchar NOT NULL,
  channels      text[]  NOT NULL,
  payload       jsonb,                          -- {custom_body, channel_results: [...] }
  status        varchar NOT NULL DEFAULT 'pending',
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_touch_history_status
    CHECK (status IN ('pending', 'success', 'partial', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_touch_history_agent_created_at
  ON touch_history(agent_uid, created_at DESC);

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考）
-- ─────────────────────────────────────────────
-- BEGIN;
-- DROP INDEX IF EXISTS idx_touch_history_agent_created_at;
-- DROP TABLE IF EXISTS touch_history;
-- DROP INDEX IF EXISTS idx_agent_thresholds_enabled;
-- DROP TABLE IF EXISTS agent_thresholds;
-- COMMIT;
-- ═══════════════════════════════════════════════════════════
