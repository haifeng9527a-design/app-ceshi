package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type PositionRepo struct {
	pool *pgxpool.Pool
}

func NewPositionRepo(pool *pgxpool.Pool) *PositionRepo {
	return &PositionRepo{pool: pool}
}

// UpsertPosition creates a new position or adds to an existing one (averaging entry price).
func (r *PositionRepo) UpsertPosition(ctx context.Context, p *model.Position) (*model.Position, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("upsert begin: %w", err)
	}
	defer tx.Rollback(ctx)

	// Check for existing open position with same user/symbol/side (only self-traded, not copy)
	var existing model.Position
	err = tx.QueryRow(ctx,
		`SELECT id, qty, entry_price, margin_amount FROM positions
		 WHERE user_id = $1 AND symbol = $2 AND side = $3 AND status = 'open'
		 AND copy_trading_id IS NULL`,
		p.UserID, p.Symbol, p.Side).
		Scan(&existing.ID, &existing.Qty, &existing.EntryPrice, &existing.MarginAmount)

	if err == pgx.ErrNoRows {
		// Create new position
		err = tx.QueryRow(ctx,
			`INSERT INTO positions (user_id, symbol, side, qty, entry_price, leverage,
			 margin_mode, margin_amount, liq_price, tp_price, sl_price, open_fee, status)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'open')
			 RETURNING id, created_at, updated_at`,
			p.UserID, p.Symbol, p.Side, p.Qty, p.EntryPrice, p.Leverage,
			p.MarginMode, p.MarginAmount, p.LiqPrice, p.TpPrice, p.SlPrice, p.OpenFee).
			Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("insert position: %w", err)
		}
		p.Status = "open"
	} else if err != nil {
		return nil, fmt.Errorf("check existing position: %w", err)
	} else {
		// Add to existing: recalculate average entry price
		newQty := existing.Qty + p.Qty
		newAvgEntry := (existing.Qty*existing.EntryPrice + p.Qty*p.EntryPrice) / newQty
		newMargin := existing.MarginAmount + p.MarginAmount

		// liq_price will be recalculated by the service layer after upsert
		err = tx.QueryRow(ctx,
			`UPDATE positions SET qty = $2, entry_price = $3, margin_amount = $4,
			 open_fee = open_fee + $5, updated_at = NOW()
			 WHERE id = $1
			 RETURNING id, user_id, symbol, side, qty, entry_price, leverage,
			 margin_mode, margin_amount, liq_price, status, realized_pnl, open_fee, close_fee, created_at, updated_at`,
			existing.ID, newQty, newAvgEntry, newMargin, p.OpenFee).
			Scan(&p.ID, &p.UserID, &p.Symbol, &p.Side, &p.Qty, &p.EntryPrice,
				&p.Leverage, &p.MarginMode, &p.MarginAmount, &p.LiqPrice,
				&p.Status, &p.RealizedPnl, &p.OpenFee, &p.CloseFee, &p.CreatedAt, &p.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("update position: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("upsert commit: %w", err)
	}
	return p, nil
}

func (r *PositionRepo) GetByID(ctx context.Context, id string) (*model.Position, error) {
	var p model.Position
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, symbol, side, qty, entry_price, leverage,
		 margin_mode, margin_amount, liq_price, tp_price, sl_price,
		 status, realized_pnl, open_fee, close_fee,
		 is_copy_trade, source_position_id, source_trader_id, copy_trading_id,
		 created_at, updated_at
		 FROM positions WHERE id = $1`, id).
		Scan(&p.ID, &p.UserID, &p.Symbol, &p.Side, &p.Qty, &p.EntryPrice,
			&p.Leverage, &p.MarginMode, &p.MarginAmount, &p.LiqPrice,
			&p.TpPrice, &p.SlPrice, &p.Status, &p.RealizedPnl,
			&p.OpenFee, &p.CloseFee,
			&p.IsCopyTrade, &p.SourcePositionID, &p.SourceTraderID, &p.CopyTradingID,
			&p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("get position: %w", err)
	}
	return &p, nil
}

func (r *PositionRepo) ListOpen(ctx context.Context, userID string) ([]model.Position, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, symbol, side, qty, entry_price, leverage,
		 margin_mode, margin_amount, liq_price, tp_price, sl_price,
		 status, realized_pnl, open_fee, close_fee,
		 is_copy_trade, source_position_id, source_trader_id, copy_trading_id,
		 created_at, updated_at
		 FROM positions WHERE user_id = $1 AND status = 'open'
		 ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("list open positions: %w", err)
	}
	defer rows.Close()
	return scanPositions(rows)
}

// ListAllOpen returns all open positions across all users (for cache loading on startup).
func (r *PositionRepo) ListAllOpen(ctx context.Context) ([]model.Position, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, symbol, side, qty, entry_price, leverage,
		 margin_mode, margin_amount, liq_price, tp_price, sl_price,
		 status, realized_pnl, open_fee, close_fee,
		 is_copy_trade, source_position_id, source_trader_id, copy_trading_id,
		 created_at, updated_at
		 FROM positions WHERE status = 'open'`)
	if err != nil {
		return nil, fmt.Errorf("list all open positions: %w", err)
	}
	defer rows.Close()
	return scanPositions(rows)
}

// UpdateTPSL updates the take-profit and stop-loss prices for a position.
func (r *PositionRepo) UpdateTPSL(ctx context.Context, id string, tp *float64, sl *float64) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE positions SET tp_price = $2, sl_price = $3, updated_at = NOW() WHERE id = $1`,
		id, tp, sl)
	return err
}

// UpdateLiqPrice updates the liquidation price for a position.
func (r *PositionRepo) UpdateLiqPrice(ctx context.Context, id string, liqPrice float64) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE positions SET liq_price = $2, updated_at = NOW() WHERE id = $1`,
		id, liqPrice)
	return err
}

func (r *PositionRepo) ClosePosition(ctx context.Context, id string, realizedPnl float64, closePrice float64, closeFee float64) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE positions SET status = 'closed', realized_pnl = $2, close_price = $3,
		 close_fee = close_fee + $4, closed_at = NOW(), updated_at = NOW()
		 WHERE id = $1 AND status = 'open'`,
		id, realizedPnl, closePrice, closeFee)
	if err != nil {
		return fmt.Errorf("close position: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("position already closed or not found")
	}
	return nil
}

func (r *PositionRepo) LiquidatePosition(ctx context.Context, id string, realizedPnl float64, closePrice float64) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE positions SET status = 'liquidated', realized_pnl = $2, close_price = $3,
		 closed_at = NOW(), updated_at = NOW()
		 WHERE id = $1 AND status = 'open'`,
		id, realizedPnl, closePrice)
	if err != nil {
		return fmt.Errorf("liquidate position: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("position already closed or not found")
	}
	return nil
}

// ReducePosition decreases the qty and margin of an open position (partial close).
// pnl is the realized PnL for the closed portion, accumulated onto the position.
func (r *PositionRepo) ReducePosition(ctx context.Context, id string, newQty, newMargin, closeFee, pnl float64) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE positions SET qty = $2, margin_amount = $3, close_fee = close_fee + $4,
		 realized_pnl = realized_pnl + $5, updated_at = NOW()
		 WHERE id = $1 AND status = 'open'`,
		id, newQty, newMargin, closeFee, pnl)
	if err != nil {
		return fmt.Errorf("reduce position: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("position already closed or not found")
	}
	return nil
}

// ListClosed returns closed/liquidated positions for a user, ordered by close time desc.
func (r *PositionRepo) ListClosed(ctx context.Context, userID string, limit int) ([]model.Position, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, symbol, side, qty, entry_price, leverage,
		 margin_mode, margin_amount, liq_price, tp_price, sl_price,
		 status, realized_pnl, open_fee, close_fee, COALESCE(close_price, 0),
		 is_copy_trade, source_position_id, source_trader_id, copy_trading_id,
		 created_at, updated_at, closed_at
		 FROM positions WHERE user_id = $1 AND status IN ('closed','liquidated')
		 ORDER BY closed_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("list closed positions: %w", err)
	}
	defer rows.Close()

	var positions []model.Position
	for rows.Next() {
		var p model.Position
		if err := rows.Scan(&p.ID, &p.UserID, &p.Symbol, &p.Side, &p.Qty, &p.EntryPrice,
			&p.Leverage, &p.MarginMode, &p.MarginAmount, &p.LiqPrice,
			&p.TpPrice, &p.SlPrice, &p.Status, &p.RealizedPnl, &p.OpenFee, &p.CloseFee, &p.ClosePrice,
			&p.IsCopyTrade, &p.SourcePositionID, &p.SourceTraderID, &p.CopyTradingID,
			&p.CreatedAt, &p.UpdatedAt, &p.ClosedAt); err != nil {
			return nil, err
		}
		if p.MarginAmount > 0 {
			p.ROE = (p.RealizedPnl / p.MarginAmount) * 100
		}
		positions = append(positions, p)
	}
	if positions == nil {
		positions = []model.Position{}
	}
	return positions, nil
}

// ── Shared scanner for open positions ──

func scanPositions(rows interface {
	Next() bool
	Scan(dest ...any) error
}) ([]model.Position, error) {
	var positions []model.Position
	for rows.Next() {
		var p model.Position
		if err := rows.Scan(&p.ID, &p.UserID, &p.Symbol, &p.Side, &p.Qty, &p.EntryPrice,
			&p.Leverage, &p.MarginMode, &p.MarginAmount, &p.LiqPrice,
			&p.TpPrice, &p.SlPrice, &p.Status, &p.RealizedPnl,
			&p.OpenFee, &p.CloseFee,
			&p.IsCopyTrade, &p.SourcePositionID, &p.SourceTraderID, &p.CopyTradingID,
			&p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		positions = append(positions, p)
	}
	return positions, nil
}

// ── Copy Trading Position Methods ──

// CreateCopyPosition creates or merges into a follower's open position for the
// given copy_trading subscription. The unique index
// idx_positions_user_symbol_side_open — (user_id, symbol, side, copy_trading_id)
// WHERE status='open' — forbids two open rows for the same subscription, so when
// the trader adds to a position we must merge (weighted-average entry price,
// sum qty/margin/open_fee) instead of inserting a new row. liq_price is left to
// the service layer to recalculate after merge.
func (r *PositionRepo) CreateCopyPosition(ctx context.Context, p *model.Position) (*model.Position, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("create copy position begin: %w", err)
	}
	defer tx.Rollback(ctx)

	// Look up an existing open position for the same subscription.
	var existing model.Position
	err = tx.QueryRow(ctx,
		`SELECT id, qty, entry_price, margin_amount, open_fee FROM positions
		 WHERE user_id = $1 AND symbol = $2 AND side = $3 AND status = 'open'
		 AND copy_trading_id = $4`,
		p.UserID, p.Symbol, p.Side, p.CopyTradingID).
		Scan(&existing.ID, &existing.Qty, &existing.EntryPrice, &existing.MarginAmount, &existing.OpenFee)

	if err == pgx.ErrNoRows {
		// First fill for this subscription → INSERT.
		err = tx.QueryRow(ctx,
			`INSERT INTO positions (user_id, symbol, side, qty, entry_price, leverage,
			 margin_mode, margin_amount, liq_price, tp_price, sl_price, open_fee, status,
			 is_copy_trade, source_position_id, source_trader_id, copy_trading_id)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'open',$13,$14,$15,$16)
			 RETURNING id, created_at, updated_at`,
			p.UserID, p.Symbol, p.Side, p.Qty, p.EntryPrice, p.Leverage,
			p.MarginMode, p.MarginAmount, p.LiqPrice, p.TpPrice, p.SlPrice, p.OpenFee,
			p.IsCopyTrade, p.SourcePositionID, p.SourceTraderID, p.CopyTradingID).
			Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("insert copy position: %w", err)
		}
		p.Status = "open"
	} else if err != nil {
		return nil, fmt.Errorf("check existing copy position: %w", err)
	} else {
		// Merge: weighted-average entry, sum qty/margin/open_fee. Point the row at
		// the latest source position so triggerCopyClose can still locate it.
		newQty := existing.Qty + p.Qty
		newAvgEntry := (existing.Qty*existing.EntryPrice + p.Qty*p.EntryPrice) / newQty
		newMargin := existing.MarginAmount + p.MarginAmount
		newOpenFee := existing.OpenFee + p.OpenFee

		err = tx.QueryRow(ctx,
			`UPDATE positions SET qty = $2, entry_price = $3, margin_amount = $4,
			 open_fee = $5, source_position_id = $6, updated_at = NOW()
			 WHERE id = $1
			 RETURNING id, user_id, symbol, side, qty, entry_price, leverage,
			 margin_mode, margin_amount, liq_price, tp_price, sl_price,
			 status, realized_pnl, open_fee, close_fee,
			 is_copy_trade, source_position_id, source_trader_id, copy_trading_id,
			 created_at, updated_at`,
			existing.ID, newQty, newAvgEntry, newMargin, newOpenFee, p.SourcePositionID).
			Scan(&p.ID, &p.UserID, &p.Symbol, &p.Side, &p.Qty, &p.EntryPrice,
				&p.Leverage, &p.MarginMode, &p.MarginAmount, &p.LiqPrice,
				&p.TpPrice, &p.SlPrice, &p.Status, &p.RealizedPnl, &p.OpenFee, &p.CloseFee,
				&p.IsCopyTrade, &p.SourcePositionID, &p.SourceTraderID, &p.CopyTradingID,
				&p.CreatedAt, &p.UpdatedAt)
		if err != nil {
			return nil, fmt.Errorf("merge copy position: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("create copy position commit: %w", err)
	}
	return p, nil
}

// ListBySourcePosition returns all follower positions linked to a source (trader's) position.
func (r *PositionRepo) ListBySourcePosition(ctx context.Context, sourcePositionID string) ([]model.Position, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, symbol, side, qty, entry_price, leverage,
		 margin_mode, margin_amount, liq_price, tp_price, sl_price,
		 status, realized_pnl, open_fee, close_fee,
		 is_copy_trade, source_position_id, source_trader_id, copy_trading_id,
		 created_at, updated_at
		 FROM positions
		 WHERE source_position_id = $1 AND is_copy_trade = true AND status = 'open'`,
		sourcePositionID)
	if err != nil {
		return nil, fmt.Errorf("list by source position: %w", err)
	}
	defer rows.Close()
	return scanPositions(rows)
}
