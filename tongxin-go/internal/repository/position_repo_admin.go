package repository

import (
	"context"
	"fmt"
	"strings"

	"tongxin-go/internal/model"
)

type PositionFilters struct {
	Status      string
	Symbol      string
	UserID      string
	Side        string
	IsCopyTrade string
	Limit       int
	Offset      int
}

type LiquidationFilters struct {
	Symbol   string
	UserID   string
	DateFrom string
	DateTo   string
	Limit    int
	Offset   int
}

// ListAllFiltered returns positions with user display_name, supporting admin filters.
func (r *PositionRepo) ListAllFiltered(ctx context.Context, f PositionFilters) ([]map[string]any, int, error) {
	where := []string{"1=1"}
	args := []any{}
	idx := 1

	if f.Status != "" {
		where = append(where, fmt.Sprintf("p.status=$%d", idx))
		args = append(args, f.Status)
		idx++
	}
	if f.Symbol != "" {
		where = append(where, fmt.Sprintf("p.symbol=$%d", idx))
		args = append(args, f.Symbol)
		idx++
	}
	if f.UserID != "" {
		where = append(where, fmt.Sprintf("p.user_id=$%d", idx))
		args = append(args, f.UserID)
		idx++
	}
	if f.Side != "" {
		where = append(where, fmt.Sprintf("p.side=$%d", idx))
		args = append(args, f.Side)
		idx++
	}
	if f.IsCopyTrade == "true" {
		where = append(where, "p.is_copy_trade=true")
	} else if f.IsCopyTrade == "false" {
		where = append(where, "p.is_copy_trade=false")
	}

	whereClause := strings.Join(where, " AND ")

	// Count
	var total int
	countQ := fmt.Sprintf(`SELECT COUNT(*) FROM positions p WHERE %s`, whereClause)
	if err := r.pool.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count positions: %w", err)
	}

	// Data
	dataQ := fmt.Sprintf(`SELECT p.id, p.user_id, COALESCE(u.display_name,''), p.symbol, p.side, p.qty,
		p.entry_price, p.leverage, p.margin_mode, p.margin_amount,
		p.liq_price, p.tp_price, p.sl_price, p.status, p.realized_pnl,
		p.close_price, p.open_fee, p.close_fee, p.is_copy_trade,
		p.created_at, p.updated_at, p.closed_at
		FROM positions p LEFT JOIN users u ON u.uid=p.user_id
		WHERE %s ORDER BY p.created_at DESC LIMIT $%d OFFSET $%d`,
		whereClause, idx, idx+1)
	args = append(args, f.Limit, f.Offset)

	rows, err := r.pool.Query(ctx, dataQ, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("list positions: %w", err)
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		var p model.Position
		var displayName string
		if err := rows.Scan(
			&p.ID, &p.UserID, &displayName, &p.Symbol, &p.Side, &p.Qty,
			&p.EntryPrice, &p.Leverage, &p.MarginMode, &p.MarginAmount,
			&p.LiqPrice, &p.TpPrice, &p.SlPrice, &p.Status, &p.RealizedPnl,
			&p.ClosePrice, &p.OpenFee, &p.CloseFee, &p.IsCopyTrade,
			&p.CreatedAt, &p.UpdatedAt, &p.ClosedAt,
		); err != nil {
			return nil, 0, err
		}
		row := map[string]any{
			"id": p.ID, "user_id": p.UserID, "display_name": displayName,
			"symbol": p.Symbol, "side": p.Side, "qty": p.Qty,
			"entry_price": p.EntryPrice, "leverage": p.Leverage,
			"margin_mode": p.MarginMode, "margin_amount": p.MarginAmount,
			"liq_price": p.LiqPrice, "status": p.Status,
			"realized_pnl": p.RealizedPnl, "close_price": p.ClosePrice,
			"open_fee": p.OpenFee, "close_fee": p.CloseFee,
			"is_copy_trade": p.IsCopyTrade,
			"created_at": p.CreatedAt, "updated_at": p.UpdatedAt, "closed_at": p.ClosedAt,
		}
		results = append(results, row)
	}
	return results, total, nil
}

// GetOpenSummary returns aggregate stats for open positions.
func (r *PositionRepo) GetOpenSummary(ctx context.Context) (*model.PositionSummary, error) {
	var s model.PositionSummary
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*), COALESCE(SUM(margin_amount),0), 0
		 FROM positions WHERE status='open'`).
		Scan(&s.TotalOpen, &s.TotalMargin, &s.TotalUnrealPnl)
	if err != nil {
		return nil, fmt.Errorf("open summary: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT symbol, COUNT(*), COALESCE(SUM(margin_amount),0)
		 FROM positions WHERE status='open' GROUP BY symbol ORDER BY COUNT(*) DESC LIMIT 20`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var ss model.SymbolSummary
		if err := rows.Scan(&ss.Symbol, &ss.Count, &ss.TotalMargin); err != nil {
			return nil, err
		}
		s.BySymbol = append(s.BySymbol, ss)
	}
	return &s, nil
}

// ListLiquidated returns liquidated positions with filters.
func (r *PositionRepo) ListLiquidated(ctx context.Context, f LiquidationFilters) ([]map[string]any, int, error) {
	where := []string{"p.status='liquidated'"}
	args := []any{}
	idx := 1

	if f.Symbol != "" {
		where = append(where, fmt.Sprintf("p.symbol=$%d", idx))
		args = append(args, f.Symbol)
		idx++
	}
	if f.UserID != "" {
		where = append(where, fmt.Sprintf("p.user_id=$%d", idx))
		args = append(args, f.UserID)
		idx++
	}
	if f.DateFrom != "" {
		where = append(where, fmt.Sprintf("p.closed_at >= $%d::timestamptz", idx))
		args = append(args, f.DateFrom)
		idx++
	}
	if f.DateTo != "" {
		where = append(where, fmt.Sprintf("p.closed_at <= $%d::timestamptz", idx))
		args = append(args, f.DateTo)
		idx++
	}

	whereClause := strings.Join(where, " AND ")

	var total int
	if err := r.pool.QueryRow(ctx, fmt.Sprintf(`SELECT COUNT(*) FROM positions p WHERE %s`, whereClause), args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	dataQ := fmt.Sprintf(`SELECT p.id, p.user_id, COALESCE(u.display_name,''), p.symbol, p.side,
		p.qty, p.entry_price, p.close_price, p.leverage, p.margin_amount, p.realized_pnl, p.closed_at
		FROM positions p LEFT JOIN users u ON u.uid=p.user_id
		WHERE %s ORDER BY p.closed_at DESC LIMIT $%d OFFSET $%d`, whereClause, idx, idx+1)
	args = append(args, f.Limit, f.Offset)

	rows, err := r.pool.Query(ctx, dataQ, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		var id, uid, dn, symbol, side string
		var qty, entry, close, margin, pnl float64
		var leverage int
		var closedAt *interface{}
		row := make(map[string]any)
		if err := rows.Scan(&id, &uid, &dn, &symbol, &side, &qty, &entry, &close, &leverage, &margin, &pnl, &closedAt); err != nil {
			return nil, 0, err
		}
		row["id"] = id
		row["user_id"] = uid
		row["display_name"] = dn
		row["symbol"] = symbol
		row["side"] = side
		row["qty"] = qty
		row["entry_price"] = entry
		row["close_price"] = close
		row["leverage"] = leverage
		row["margin_amount"] = margin
		row["realized_pnl"] = pnl
		row["closed_at"] = closedAt
		results = append(results, row)
	}
	return results, total, nil
}

// GetLiquidationStats returns aggregate liquidation statistics.
func (r *PositionRepo) GetLiquidationStats(ctx context.Context, dateFrom, dateTo string) (*model.LiquidationStats, error) {
	var s model.LiquidationStats

	// Total
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*), COALESCE(SUM(ABS(realized_pnl)),0) FROM positions WHERE status='liquidated'`).
		Scan(&s.TotalCount, &s.TotalLoss)
	if err != nil {
		return nil, err
	}

	// Today
	err = r.pool.QueryRow(ctx,
		`SELECT COUNT(*), COALESCE(SUM(ABS(realized_pnl)),0) FROM positions
		 WHERE status='liquidated' AND closed_at >= CURRENT_DATE`).
		Scan(&s.TodayCount, &s.TodayLoss)
	if err != nil {
		return nil, err
	}

	return &s, nil
}

// GetTradingOverview returns overall trading stats for the dashboard.
func (r *PositionRepo) GetTradingOverview(ctx context.Context) (*model.TradingOverview, error) {
	var o model.TradingOverview

	_ = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM positions WHERE status='open'`).Scan(&o.OpenPositions)
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(qty * entry_price),0) FROM positions WHERE created_at >= CURRENT_DATE`).
		Scan(&o.TodayVolume)
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(open_fee + close_fee),0) FROM positions WHERE created_at >= CURRENT_DATE`).
		Scan(&o.TodayFees)
	_ = r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM positions WHERE status='liquidated' AND closed_at >= CURRENT_DATE`).
		Scan(&o.TodayLiquidations)
	_ = r.pool.QueryRow(ctx,
		`SELECT COUNT(DISTINCT user_id) FROM positions WHERE created_at >= CURRENT_DATE`).
		Scan(&o.ActiveTraders)

	return &o, nil
}
