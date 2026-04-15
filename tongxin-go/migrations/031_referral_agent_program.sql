-- ═══════════════════════════════════════════════════════════
-- 031: Referral & Agent Program — 邀请返佣 + 代理商体系
-- ═══════════════════════════════════════════════════════════
-- 背景：平台已有合约+现货+跟单主业，缺推广返佣机制。本 migration
--       引入「双轨」返佣：
--         - 普通用户（is_agent=false）：my_rebate_rate ≤ 20%，默认 10%
--         - 代理商（is_agent=true）   ：my_rebate_rate ≤ 100%
--       代理可发展子代理（给下级设 rate ≤ 自己）→ 天然级差。
--
-- 核心算法：多级级联返佣（见 referral_service.go）
--   direct:   invitee → invitee.inviter 拿 inviter.my_rebate_rate
--   override: 向上级代理链最多 10 层，每层取 delta = max(0, parent.rate - cursor_child_rate)
--   rate_snapshot 在事件产生时锁定，日结时读 event.rate_snapshot
--
-- 结算节奏：UTC 00:00 cron 日结，按 (inviter_uid, kind) 聚合，
--           commission 直接入主钱包。日上限 $10000 / inviter / 日。
--
-- 资金链路（日结阶段，单事务原子完成）：
--   wallets.balance += payout
--   wallet_transactions 写一条（type=referral_commission_in 或 agent_override_in）
--   commission_records 写一条审计（含 capped 标志）
--   commission_events.status → settled
--   users.lifetime_commission_earned += payout
--
-- Feature flag：REFERRAL_ENABLED 默认关。Flag off 时 RecordCommissionEvent
--               直接 return，scheduler 不启动，本 migration 对老用户零影响。
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ── 1. users 加 6 列 ──
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS inviter_uid                TEXT REFERENCES users(uid),
  ADD COLUMN IF NOT EXISTS my_rebate_rate             NUMERIC(5,4)  NOT NULL DEFAULT 0.10,
  ADD COLUMN IF NOT EXISTS is_agent                   BOOLEAN       NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS agent_approved_at          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS lifetime_commission_earned NUMERIC(20,8) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_frozen_referral         BOOLEAN       NOT NULL DEFAULT false;

-- CHECK：rate ∈ [0, 1.0]；自返佣禁止；lifetime 非负
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_my_rebate_rate') THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_my_rebate_rate
      CHECK (my_rebate_rate >= 0 AND my_rebate_rate <= 1.0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_no_self_invite') THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_no_self_invite
      CHECK (inviter_uid IS NULL OR inviter_uid <> uid);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_lifetime_commission_earned') THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_lifetime_commission_earned
      CHECK (lifetime_commission_earned >= 0);
  END IF;
END$$;

-- 触发器：rate > 20% 的用户必定是代理（自动升级 is_agent = true 且补 agent_approved_at）
-- 原因：
--   - 防御性不变量：普通用户上限 20%，超过这个值意味着是代理（admin 批过）
--   - 即使 service 层漏设 is_agent，DB 层也把关系拉齐
--   - admin 降 rate 到 ≤ 20% 不会自动取消代理身份（is_agent 只能显式清）
CREATE OR REPLACE FUNCTION enforce_agent_invariant() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.my_rebate_rate > 0.2000 AND NEW.is_agent = false THEN
    NEW.is_agent := true;
    IF NEW.agent_approved_at IS NULL THEN
      NEW.agent_approved_at := NOW();
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_agent_invariant ON users;
CREATE TRIGGER trg_users_agent_invariant
  BEFORE INSERT OR UPDATE OF my_rebate_rate, is_agent ON users
  FOR EACH ROW EXECUTE FUNCTION enforce_agent_invariant();

-- 查找子节点和按 inviter 拉链会很常见
CREATE INDEX IF NOT EXISTS idx_users_inviter_uid ON users(inviter_uid) WHERE inviter_uid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_is_agent    ON users(is_agent) WHERE is_agent = true;

-- ── 2. invite_links ──
CREATE TABLE IF NOT EXISTS invite_links (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_uid          TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    code               TEXT UNIQUE NOT NULL,
    landing_page       TEXT,
    name               TEXT NOT NULL DEFAULT 'Default',
    is_active          BOOLEAN NOT NULL DEFAULT true,
    registration_count INT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_invite_links_code_format
      CHECK (code ~ '^[a-zA-Z0-9_]{3,20}$'),
    CONSTRAINT chk_invite_links_reg_count
      CHECK (registration_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_invite_links_owner     ON invite_links(owner_uid);
-- code 已 UNIQUE，查询 active 链接常见
CREATE INDEX IF NOT EXISTS idx_invite_links_active    ON invite_links(code) WHERE is_active = true;

-- ── 3. commission_events ──
-- 每笔 fee 扣除 → 若干 pending events（direct + override 0..N）
CREATE TABLE IF NOT EXISTS commission_events (
    event_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invitee_uid           TEXT NOT NULL REFERENCES users(uid),
    inviter_uid           TEXT NOT NULL REFERENCES users(uid),
    -- override 场景：本级级差从哪个下级身上拿的（审计用）
    source_inviter_uid    TEXT REFERENCES users(uid),
    kind                  TEXT NOT NULL CHECK (kind IN ('direct', 'override')),
    product_type          TEXT NOT NULL CHECK (product_type IN (
                            'futures_open','futures_close','futures_partial','futures_tpsl',
                            'copy_open','copy_close','spot','funding'
                          )),
    fee_base              NUMERIC(20,8) NOT NULL,
    rate_snapshot         NUMERIC(5,4)  NOT NULL,
    commission_amount     NUMERIC(20,8) NOT NULL,
    source_transaction_id TEXT,
    status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'settled', 'skipped_risk', 'skipped_zero')),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settled_at            TIMESTAMPTZ,
    CONSTRAINT chk_ce_rate_snapshot CHECK (rate_snapshot >= 0 AND rate_snapshot <= 1.0),
    CONSTRAINT chk_ce_commission_amount CHECK (commission_amount >= 0),
    CONSTRAINT chk_ce_fee_base CHECK (fee_base >= 0),
    CONSTRAINT chk_ce_no_self_commission CHECK (invitee_uid <> inviter_uid)
);

-- 日结按 (inviter, status, date(created_at)) 扫；同一结算键一次捞全
CREATE INDEX IF NOT EXISTS idx_ce_settle_scan
    ON commission_events(inviter_uid, status, created_at)
    WHERE status = 'pending';
-- 用户反查"谁给我返佣"
CREATE INDEX IF NOT EXISTS idx_ce_invitee_time
    ON commission_events(invitee_uid, created_at DESC);
-- DLQ/监控扫描
CREATE INDEX IF NOT EXISTS idx_ce_status
    ON commission_events(status, created_at);
-- 审计：某笔 wallet_transactions 引发了多少 events
CREATE INDEX IF NOT EXISTS idx_ce_source_tx
    ON commission_events(source_transaction_id)
    WHERE source_transaction_id IS NOT NULL;

-- ── 4. commission_records（日结聚合审计）──
CREATE TABLE IF NOT EXISTS commission_records (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inviter_uid       TEXT NOT NULL REFERENCES users(uid),
    period_date       DATE NOT NULL,
    kind              TEXT NOT NULL CHECK (kind IN ('direct', 'override')),
    total_fee_base    NUMERIC(20,8) NOT NULL,
    commission_amount NUMERIC(20,8) NOT NULL,
    event_count       INT           NOT NULL,
    status            TEXT NOT NULL CHECK (status IN ('settled', 'capped')),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_cr_commission_amount CHECK (commission_amount >= 0),
    CONSTRAINT chk_cr_total_fee_base CHECK (total_fee_base >= 0),
    CONSTRAINT chk_cr_event_count CHECK (event_count > 0),
    -- 幂等：同一 inviter / 日 / kind 只写一条
    CONSTRAINT uq_cr_inviter_date_kind UNIQUE (inviter_uid, period_date, kind)
);

CREATE INDEX IF NOT EXISTS idx_cr_inviter_time ON commission_records(inviter_uid, period_date DESC);
CREATE INDEX IF NOT EXISTS idx_cr_date         ON commission_records(period_date);

-- ── 5. agent_applications ──
CREATE TABLE IF NOT EXISTS agent_applications (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    applicant_uid        TEXT NOT NULL REFERENCES users(uid),
    status               TEXT NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    channel_description  TEXT NOT NULL DEFAULT '',
    audience_size        INT,
    contact_info         JSONB NOT NULL DEFAULT '{}'::jsonb,
    proposed_rate        NUMERIC(5,4),
    review_note          TEXT NOT NULL DEFAULT '',
    submitted_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at          TIMESTAMPTZ,
    reviewed_by          TEXT REFERENCES users(uid),
    CONSTRAINT chk_aa_proposed_rate CHECK (proposed_rate IS NULL OR (proposed_rate >= 0 AND proposed_rate <= 1.0)),
    CONSTRAINT chk_aa_audience_size CHECK (audience_size IS NULL OR audience_size >= 0)
);

CREATE INDEX IF NOT EXISTS idx_aa_applicant ON agent_applications(applicant_uid, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_aa_status    ON agent_applications(status, submitted_at DESC);
-- 同一 applicant 只允许一条 pending（防刷）
CREATE UNIQUE INDEX IF NOT EXISTS uq_aa_applicant_pending
    ON agent_applications(applicant_uid)
    WHERE status = 'pending';

-- ── 6. commission_events_dlq（死信队列）──
-- 风险缓解：RecordCommissionEvent 重试 3 次仍失败时落此表，
--           留人工排查。避免事件彻底丢失。
CREATE TABLE IF NOT EXISTS commission_events_dlq (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invitee_uid    TEXT NOT NULL,
    fee_base       NUMERIC(20,8) NOT NULL,
    product_type   TEXT NOT NULL,
    source_transaction_id TEXT,
    payload        JSONB NOT NULL DEFAULT '{}'::jsonb,  -- 原始 event 草稿（cascade 链快照）
    error_text     TEXT NOT NULL,
    retry_count    INT  NOT NULL DEFAULT 0,
    dlq_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at    TIMESTAMPTZ,
    resolved_note  TEXT
);
CREATE INDEX IF NOT EXISTS idx_ce_dlq_unresolved ON commission_events_dlq(dlq_at DESC) WHERE resolved_at IS NULL;

-- ── 7. wallet_transactions.type 枚举扩展 ──
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
    'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
    'copy_allocate','copy_withdraw','copy_pnl_settle',
    'copy_profit_share_out','copy_profit_share_in',
    'referral_commission_in',  -- direct 返佣入账（amount > 0）
    'agent_override_in'        -- override 级差入账（amount > 0）
  ));

-- ── 8. Backfill：存量用户 ──
-- 策略：
--   - my_rebate_rate 默认 0.10（和 PLATFORM_USER_DEFAULT_RATE 对齐）
--   - is_agent=false、is_frozen_referral=false、inviter_uid=NULL
--   - Flag 未开启前这些字段完全不被读取，对老用户零影响
-- 幂等：ADD COLUMN DEFAULT 已经初始化，这里只是显式确认
UPDATE users
SET
    inviter_uid                = COALESCE(inviter_uid, NULL),
    my_rebate_rate             = COALESCE(my_rebate_rate, 0.10),
    is_agent                   = COALESCE(is_agent, false),
    agent_approved_at          = COALESCE(agent_approved_at, NULL),
    lifetime_commission_earned = COALESCE(lifetime_commission_earned, 0),
    is_frozen_referral         = COALESCE(is_frozen_referral, false)
WHERE my_rebate_rate IS NULL
   OR is_agent IS NULL
   OR lifetime_commission_earned IS NULL
   OR is_frozen_referral IS NULL;

-- 每个存量用户一条默认 invite_link（code = short_id）
-- 注意：
--   - ON CONFLICT (code) DO NOTHING 幂等，多次跑不重复插入
--   - 只为 short_id 非 NULL 且符合格式的用户生成（老的 short_id 可能有奇怪字符）
--   - 不符合正则的 short_id 用户：Commit 7 的 /api/referral/me 会 lazy 生成
--   - 大表下此语句可能锁一段时间 → 生产执行前建议窗口化或分批
INSERT INTO invite_links (owner_uid, code, name, is_active)
SELECT uid, short_id, 'Default', true
  FROM users
 WHERE short_id IS NOT NULL
   AND short_id ~ '^[a-zA-Z0-9_]{3,20}$'
ON CONFLICT (code) DO NOTHING;

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考，正常不执行）
-- ─────────────────────────────────────────────
-- BEGIN;
-- ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
-- ALTER TABLE wallet_transactions
--   ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
--     'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
--     'copy_allocate','copy_withdraw','copy_pnl_settle',
--     'copy_profit_share_out','copy_profit_share_in'));
--
-- DROP INDEX IF EXISTS idx_ce_dlq_unresolved;
-- DROP TABLE IF EXISTS commission_events_dlq;
--
-- DROP INDEX IF EXISTS uq_aa_applicant_pending;
-- DROP INDEX IF EXISTS idx_aa_status;
-- DROP INDEX IF EXISTS idx_aa_applicant;
-- DROP TABLE IF EXISTS agent_applications;
--
-- DROP INDEX IF EXISTS idx_cr_date;
-- DROP INDEX IF EXISTS idx_cr_inviter_time;
-- DROP TABLE IF EXISTS commission_records;
--
-- DROP INDEX IF EXISTS idx_ce_source_tx;
-- DROP INDEX IF EXISTS idx_ce_status;
-- DROP INDEX IF EXISTS idx_ce_invitee_time;
-- DROP INDEX IF EXISTS idx_ce_settle_scan;
-- DROP TABLE IF EXISTS commission_events;
--
-- DROP INDEX IF EXISTS idx_invite_links_active;
-- DROP INDEX IF EXISTS idx_invite_links_owner;
-- DROP TABLE IF EXISTS invite_links;
--
-- DROP TRIGGER IF EXISTS trg_users_agent_invariant ON users;
-- DROP FUNCTION IF EXISTS enforce_agent_invariant();
-- DROP INDEX IF EXISTS idx_users_is_agent;
-- DROP INDEX IF EXISTS idx_users_inviter_uid;
--
-- ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_lifetime_commission_earned;
-- ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_no_self_invite;
-- ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_my_rebate_rate;
-- ALTER TABLE users
--   DROP COLUMN IF EXISTS is_frozen_referral,
--   DROP COLUMN IF EXISTS lifetime_commission_earned,
--   DROP COLUMN IF EXISTS agent_approved_at,
--   DROP COLUMN IF EXISTS is_agent,
--   DROP COLUMN IF EXISTS my_rebate_rate,
--   DROP COLUMN IF EXISTS inviter_uid;
-- COMMIT;
-- ═══════════════════════════════════════════════════════════
