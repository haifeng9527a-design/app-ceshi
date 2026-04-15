-- ═══════════════════════════════════════════════════════════
-- 025: Copy Trading Allocated Capital — 跟单分配本金（虚拟子账户）
-- ═══════════════════════════════════════════════════════════
-- 背景：原跟单仓位计算用「跟随者主钱包总资金」做基数，
-- 一个用户跟多个交易员时仓位会重叠超额。
-- 新模型：每条 copy_trading 记录是个独立子账户：
--   - allocated_capital   = 用户当前已分配给该交易员的总本金（追加/赎回时变化）
--   - available_capital   = 子账户当前可用余额（开仓时减、平仓 PnL 入账时增）
--   - frozen_capital      = 子账户当前在跟单仓位里冻结的保证金
-- 不变量：available + frozen = allocated + 累计 realized_pnl - 累计 fee
--
-- 对应业务流：
--   关注交易员  → wallet.balance -= X，子账户 allocated/available += X
--   跟单开仓    → 子账户 available -= margin，frozen += margin（wallet 不动）
--   跟单平仓    → 子账户 frozen -= margin，available += margin + pnl - fee
--   取消关注    → 检查 frozen=0 后 wallet.balance += available，子账户停用
-- ═══════════════════════════════════════════════════════════

-- ── 1. 子账户三字段 ──
ALTER TABLE copy_trading
  ADD COLUMN IF NOT EXISTS allocated_capital NUMERIC(20,8) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS available_capital NUMERIC(20,8) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS frozen_capital    NUMERIC(20,8) NOT NULL DEFAULT 0;

-- 非负约束（允许 available 因 PnL 涨过 allocated，所以不约束二者关系）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_copy_trading_capital_nonneg'
  ) THEN
    ALTER TABLE copy_trading
      ADD CONSTRAINT chk_copy_trading_capital_nonneg
      CHECK (available_capital >= 0 AND frozen_capital >= 0 AND allocated_capital >= 0);
  END IF;
END$$;

-- ── 2. 钱包流水类型扩展 ──
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN (
    'deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee',
    'copy_allocate',     -- 用户分配本金给某交易员（wallet → 子账户）
    'copy_withdraw',     -- 取消关注/赎回本金（子账户 → wallet）
    'copy_pnl_settle'    -- 跟单仓位结算（标记性流水，金额 = pnl，不动 wallet.balance）
  ));

-- ── 3. Backfill 现存 active 订阅 ──
-- 现状：max_position 大致等价于"最大允许总仓位"，把它当作分配本金的初始值。
-- 当前已开仓占用 = SUM(positions.margin_amount WHERE copy_trading_id=ct.id AND status='open')
-- 对每条 active 订阅：
--   frozen_capital   = 当前 open 仓位的 margin 之和
--   allocated_capital = max(max_position, frozen_capital)  （保证 available >= 0）
--   available_capital = allocated_capital - frozen_capital
WITH ct_frozen AS (
  SELECT copy_trading_id, COALESCE(SUM(margin_amount), 0)::NUMERIC(20,8) AS frozen
  FROM positions
  WHERE status = 'open' AND copy_trading_id IS NOT NULL
  GROUP BY copy_trading_id
)
UPDATE copy_trading ct
SET allocated_capital = GREATEST(COALESCE(ct.max_position, 1000)::NUMERIC, COALESCE(f.frozen, 0)),
    frozen_capital    = COALESCE(f.frozen, 0),
    available_capital = GREATEST(
      GREATEST(COALESCE(ct.max_position, 1000)::NUMERIC, COALESCE(f.frozen, 0)) - COALESCE(f.frozen, 0),
      0
    )
FROM ct_frozen f
WHERE ct.id = f.copy_trading_id
  AND ct.status = 'active'
  AND ct.allocated_capital = 0;  -- 幂等：只补未填的

-- 没有任何 open 仓位的旧 active 订阅
UPDATE copy_trading
SET allocated_capital = COALESCE(max_position, 1000),
    available_capital = COALESCE(max_position, 1000),
    frozen_capital    = 0
WHERE status = 'active' AND allocated_capital = 0;

-- ── 4. 索引（用于 admin / 用户钱包页快速汇总）──
CREATE INDEX IF NOT EXISTS idx_copy_trading_follower_status
  ON copy_trading(follower_id, status) WHERE status = 'active';

-- ═══════════════════════════════════════════════════════════
-- 回滚 SQL（仅供参考，正常不执行）
-- ALTER TABLE copy_trading DROP CONSTRAINT IF EXISTS chk_copy_trading_capital_nonneg;
-- ALTER TABLE copy_trading
--   DROP COLUMN IF EXISTS allocated_capital,
--   DROP COLUMN IF EXISTS available_capital,
--   DROP COLUMN IF EXISTS frozen_capital;
-- ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;
-- ALTER TABLE wallet_transactions
--   ADD CONSTRAINT wallet_transactions_type_check CHECK (type IN
--     ('deposit','withdraw','order_freeze','order_unfreeze','trade_pnl','fee'));
-- DROP INDEX IF EXISTS idx_copy_trading_follower_status;
-- ═══════════════════════════════════════════════════════════
