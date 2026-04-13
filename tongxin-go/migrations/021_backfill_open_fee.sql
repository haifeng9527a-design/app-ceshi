-- Backfill open_fee for positions that were created before fee tracking.
-- Uses default taker fee rate of 0.05% (0.0005).
UPDATE positions
SET open_fee = ROUND((entry_price * qty * 0.0005)::NUMERIC, 8)
WHERE open_fee = 0 AND entry_price > 0 AND qty > 0;
