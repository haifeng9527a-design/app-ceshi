-- Performance indexes for scaling as data grows.
-- All indexes use CREATE INDEX IF NOT EXISTS so this migration is idempotent.
-- Rollback: DROP INDEX IF EXISTS <name>;

-- Admin dashboard aggregates open positions by symbol
-- (position_repo_admin.go: SELECT symbol, COUNT(*) FROM positions WHERE status='open' GROUP BY symbol).
-- Current coverage: none — status='open' is a large partition, full scan today.
CREATE INDEX IF NOT EXISTS idx_positions_symbol_open
    ON positions(symbol) WHERE status = 'open';

-- User position history (closed + liquidated), ordered by closed_at DESC.
-- (position_repo.go: WHERE user_id=$1 AND status IN ('closed','liquidated') ORDER BY closed_at DESC).
-- Current coverage: none — existing idx_positions_user_open is status='open' only.
CREATE INDEX IF NOT EXISTS idx_positions_user_history
    ON positions(user_id, closed_at DESC) WHERE status <> 'open';

-- Liquidation stats on closed_at (admin stats / revenue reports).
-- (position_repo_admin.go + revenue_repo.go: WHERE status='liquidated' AND closed_at >= ...).
CREATE INDEX IF NOT EXISTS idx_positions_liquidated_closed_at
    ON positions(closed_at DESC) WHERE status = 'liquidated';
