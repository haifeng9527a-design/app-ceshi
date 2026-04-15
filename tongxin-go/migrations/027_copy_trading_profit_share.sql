-- ═══════════════════════════════════════════════════════════
-- 027: Copy Trading Profit Share — 跟单分润
-- ═══════════════════════════════════════════════════════════
-- 背景：当前跟单系统 follower 赚的钱 100% 进自己的池子，
--       trader 拿不到任何商业回报。本 migration 引入「分润」：
--       trader 可设置默认分润比例（0-20%），新 follower 跟单
--       时把比例 snapshot 到 copy_trading 行；平仓时若该跟单关系
--       的子账户净值突破历史高水位线 (HWM) 才按比例抽分润。
--
-- 核心算法：HWM 高水位线（亏损不抽、回本前不抽）
--   real_profit          = (available_capital + frozen_capital) - cumulative_net_deposit
--   equity_after_close   = available_after + frozen_after
--   if equity_after_close > high_water_mark:
--     chargeable    = min(equity_after_close - high_water_mark, max(0, pnl - close_fee))
--     share_amount  = chargeable * profit_share_rate
--     hwm_after     = equity_after_close - share_amount
--   else: skip
--
-- 公平性：
--   - trader 改默认比例只对【新】 follower 生效（snapshot 锁定）
--   - 追加本金 → cumulative_net_deposit & hwm 同步 +delta
--   - 赎回本金 → cumulative_net_deposit & hwm 同步 -delta（hwm 钳到 0）
--
-- 资金链路：单事务原子完成
--   follower 池子.available_capital -= share
--   trader 主钱包.balance += share
--   wallet_transactions 写两条（follower out / trader in）
--   copy_profit_share_records 写一条审计
-- ═══════════════════════════════════════════════════════════

BEGIN;

-- ── 1. copy_trading 加 4 列 ──
ALTER TABLE copy_trading
  ADD COLUMN IF NOT EXISTS profit_share_rate        NUMERIC(5,4)  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS high_water_mark          NUMERIC(20,8) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cumulative_net_deposit   NUMERIC(20,8) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cumulative_profit_shared NUMERIC(20,8) NOT NULL DEFAULT 0;

-- 比例上限 20%、HWM 与累计净入金非负
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_copy_trading_profit_share'
  ) THEN
    ALTER TABLE copy_trading
      ADD CONSTRAINT chk_copy_trading_profit_share
      CHECK (
        profit_share_rate >= 0
        AND profit_share_rate <= 0.2000
        AND high_water_mark >= 0
        AND cumulative_net_deposit >= 0
        AND cumulative_profit_shared >= 0
      );
  END IF;
END$$;

-- ── 2. users 加 2 列（trader 默认比例 + 累计已收分润）──
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS default_profit_share_rate NUMERIC(5,4)  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lifetime_profit_shared_in NUMERIC(20,8) NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_default_profit_share_rate'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_default_profit_share_rate
      CHECK (default_profit_share_rate >= 0 AND default_profit_share_rate <= 0.2000);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_lifetime_profit_shared_in'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT chk_users_lifetime_profit_shared_in
      CHECK (lifetime_profit_shared_in >= 0);
  END IF;
END$$;

-- ── 3. 新建分润审计表 ──
CREATE TABLE IF NOT EXISTS copy_profit_share_records (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    copy_trading_id  UUID NOT NULL REFERENCES copy_trading(id) ON DELETE CASCADE,
    follower_user_id TEXT NOT NULL REFERENCES users(uid),
    trader_user_id   TEXT NOT NULL REFERENCES users(uid),
    position_id      UUID NOT NULL REFERENCES positions(id),

    -- 本笔 PnL 快照
    gross_pnl        NUMERIC(20,8) NOT NULL,
    close_fee        NUMERIC(20,8) NOT NULL DEFAULT 0,
    net_pnl          NUMERIC(20,8) NOT NULL,

    -- HWM 推进快照
    equity_before    NUMERIC(20,8) NOT NULL,
    equity_after     NUMERIC(20,8) NOT NULL,
    hwm_before       NUMERIC(20,8) NOT NULL,
    hwm_after        NUMERIC(20,8) NOT NULL,

    -- 分润计算
    rate_applied     NUMERIC(5,4)  NOT NULL,
    share_amount     NUMERIC(20,8) NOT NULL DEFAULT 0,

    status           TEXT NOT NULL CHECK (status IN (
                       'settled',           -- 成功抽分润
                       'skipped_below_hwm', -- 没创新高
                       'skipped_loss',      -- 本笔亏损或持平
                       'skipped_zero_rate'  -- snapshot 比例为 0（存量 follower）
                     ))
);

-- dashboard 按 trader 反查最常见
CREATE INDEX IF NOT EXISTS idx_psr_trader_time
    ON copy_profit_share_records(trader_user_id, created_at DESC);
-- follower 自己的池子明细
CREATE INDEX IF NOT EXISTS idx_psr_follower_time
    ON copy_profit_share_records(follower_user_id, created_at DESC);
-- 单个跟单关系的累计审计
CREATE INDEX IF NOT EXISTS idx_psr_copy_trading_time
    ON copy_profit_share_records(copy_trading_id, created_at DESC);
-- 反查某个仓位是否分过润（防重）
CREATE INDEX IF NOT EXISTS idx_psr_position
    ON copy_profit_share_records(position_id);

-- ── 4. wallet_transactions 枚举扩展 ──
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
    'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
    'copy_allocate',          -- 用户分配本金给某交易员（wallet → 子账户）
    'copy_withdraw',          -- 取消关注/赎回本金（子账户 → wallet）
    'copy_pnl_settle',        -- 跟单仓位结算（标记性流水）
    'copy_profit_share_out',  -- follower 视角：从子账户支付分润给 trader（amount<0）
    'copy_profit_share_in'    -- trader 视角：收到 follower 分润入主钱包（amount>0）
  ));

-- ── 5. Backfill：保护存量 ──
-- 策略：所有存量 active 跟单关系 profit_share_rate=0，永远不触发分润；
--      trader users 的 default_profit_share_rate 也保持 0，必须主动到
--      dashboard 设置才会启用。这样上线对老用户零影响。
--
-- HWM / cumulative_net_deposit 仍然初始化到合理值，便于将来若手动开启
-- 分润时数据基线正确：
--   cumulative_net_deposit = allocated_capital   （把当前已分配视为净入金基线）
--   high_water_mark        = max(cumulative_net_deposit, available + frozen)
--                            （在亏的 → 必须先回本到原始 deposit；在赚的 → HWM 跟到当前净值）
UPDATE copy_trading
SET cumulative_net_deposit = allocated_capital,
    high_water_mark        = GREATEST(allocated_capital, available_capital + frozen_capital),
    profit_share_rate      = 0,
    cumulative_profit_shared = 0
WHERE status IN ('active','paused')
  AND cumulative_net_deposit = 0;  -- 幂等：只补未填的

COMMIT;

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考，正常不执行）
-- ─────────────────────────────────────────────
-- DROP INDEX IF EXISTS idx_psr_position;
-- DROP INDEX IF EXISTS idx_psr_copy_trading_time;
-- DROP INDEX IF EXISTS idx_psr_follower_time;
-- DROP INDEX IF EXISTS idx_psr_trader_time;
-- DROP TABLE IF EXISTS copy_profit_share_records;
--
-- ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_lifetime_profit_shared_in;
-- ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_default_profit_share_rate;
-- ALTER TABLE users
--   DROP COLUMN IF EXISTS lifetime_profit_shared_in,
--   DROP COLUMN IF EXISTS default_profit_share_rate;
--
-- ALTER TABLE copy_trading DROP CONSTRAINT IF EXISTS chk_copy_trading_profit_share;
-- ALTER TABLE copy_trading
--   DROP COLUMN IF EXISTS cumulative_profit_shared,
--   DROP COLUMN IF EXISTS cumulative_net_deposit,
--   DROP COLUMN IF EXISTS high_water_mark,
--   DROP COLUMN IF EXISTS profit_share_rate;
--
-- ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
-- ALTER TABLE wallet_transactions
--   ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
--     'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
--     'copy_allocate','copy_withdraw','copy_pnl_settle'));
-- ═══════════════════════════════════════════════════════════
