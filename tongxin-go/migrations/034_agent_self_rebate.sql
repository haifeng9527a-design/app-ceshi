-- ═══════════════════════════════════════════════════════════
-- 034: Agent Self-Rebate — 代理自返佣
-- ═══════════════════════════════════════════════════════════
-- 背景：
--   migration 031 实现了 direct + override 两类返佣，但显式禁止了
--   self-commission（chk_ce_no_self_commission CHECK invitee != inviter）。
--   产品决策：
--     - 仅代理（is_agent = true）享自返佣
--     - 自返比例 = my_rebate_rate（与 direct 共用同一字段）
--     - 到账时机：T+1 日结，与 direct/override 同管道
--     - 日上限：自返不封顶（DAILY_COMMISSION_CAP_USD 仅作用于 direct/override）
--
-- 改动：
--   1) 放宽 commission_events 的 self-check：允许 kind='self' 时 invitee = inviter
--   2) 扩展 commission_events.kind 枚举：增加 'self'
--   3) 扩展 commission_records.kind 枚举：增加 'self'
--   4) 扩展 wallet_transactions.type 枚举：增加 'agent_self_rebate_in'
--
-- 兼容性 / 回滚：
--   - 全部是 ALTER CONSTRAINT，回滚 SQL 在文件末尾
--   - 历史 commission_events / records 不变，因为旧数据没有 kind='self'
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ── 1. commission_events：放宽 self-check，扩展 kind 枚举 ──
-- 原 CHECK：CHECK (invitee_uid <> inviter_uid)
-- 新 CHECK：kind='self' 时允许相等；其它 kind 仍禁止
ALTER TABLE commission_events DROP CONSTRAINT IF EXISTS chk_ce_no_self_commission;
ALTER TABLE commission_events
  ADD CONSTRAINT chk_ce_no_self_commission
  CHECK (kind = 'self' OR invitee_uid <> inviter_uid);

-- 扩展 kind CHECK
ALTER TABLE commission_events DROP CONSTRAINT IF EXISTS commission_events_kind_check;
ALTER TABLE commission_events
  ADD CONSTRAINT commission_events_kind_check
  CHECK (kind IN ('direct', 'override', 'self'));

-- ── 2. commission_records：扩展 kind 枚举 ──
ALTER TABLE commission_records DROP CONSTRAINT IF EXISTS commission_records_kind_check;
ALTER TABLE commission_records
  ADD CONSTRAINT commission_records_kind_check
  CHECK (kind IN ('direct', 'override', 'self'));

-- ── 3. wallet_transactions：扩展 type 枚举 ──
-- 加 'agent_self_rebate_in'（amount > 0，代理自返佣入账）
-- 修复：补上 migration 032 漏更新约束的 spot_buy / spot_sell / spot_fee
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
    'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
    'copy_allocate','copy_withdraw','copy_pnl_settle',
    'copy_profit_share_out','copy_profit_share_in',
    'spot_buy','spot_sell','spot_fee',
    'referral_commission_in',  -- direct 返佣入账
    'agent_override_in',       -- override 级差入账
    'agent_self_rebate_in'     -- 代理自返佣入账（amount > 0）
  ));

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考）
-- ─────────────────────────────────────────────
-- BEGIN;
-- ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
-- ALTER TABLE wallet_transactions
--   ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
--     'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
--     'copy_allocate','copy_withdraw','copy_pnl_settle',
--     'copy_profit_share_out','copy_profit_share_in',
--     'referral_commission_in','agent_override_in'));
--
-- ALTER TABLE commission_records DROP CONSTRAINT IF EXISTS commission_records_kind_check;
-- ALTER TABLE commission_records
--   ADD CONSTRAINT commission_records_kind_check
--   CHECK (kind IN ('direct', 'override'));
--
-- ALTER TABLE commission_events DROP CONSTRAINT IF EXISTS commission_events_kind_check;
-- ALTER TABLE commission_events
--   ADD CONSTRAINT commission_events_kind_check
--   CHECK (kind IN ('direct', 'override'));
--
-- ALTER TABLE commission_events DROP CONSTRAINT IF EXISTS chk_ce_no_self_commission;
-- ALTER TABLE commission_events
--   ADD CONSTRAINT chk_ce_no_self_commission
--   CHECK (invitee_uid <> inviter_uid);
-- COMMIT;
-- ═══════════════════════════════════════════════════════════
