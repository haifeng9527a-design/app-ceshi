-- Add close_price column and allow 'liquidated' status
ALTER TABLE positions ADD COLUMN IF NOT EXISTS close_price NUMERIC(20,8);

-- Update status check constraint to allow 'liquidated'
ALTER TABLE positions DROP CONSTRAINT IF EXISTS positions_status_check;
ALTER TABLE positions ADD CONSTRAINT positions_status_check
    CHECK (status IN ('open','closed','liquidated'));

-- Index for fetching position history (closed + liquidated)
CREATE INDEX IF NOT EXISTS idx_positions_user_closed
    ON positions(user_id, closed_at DESC) WHERE status IN ('closed','liquidated');
