package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type OrderRepo struct {
	pool *pgxpool.Pool
}

func NewOrderRepo(pool *pgxpool.Pool) *OrderRepo {
	return &OrderRepo{pool: pool}
}

func (r *OrderRepo) Create(ctx context.Context, o *model.Order) error {
	err := r.pool.QueryRow(ctx,
		`INSERT INTO orders (user_id, symbol, side, order_type, qty, price, filled_price,
		 leverage, margin_mode, margin_amount, status, filled_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
		 RETURNING id, created_at`,
		o.UserID, o.Symbol, o.Side, o.OrderType, o.Qty, o.Price, o.FilledPrice,
		o.Leverage, o.MarginMode, o.MarginAmount, o.Status, o.FilledAt).
		Scan(&o.ID, &o.CreatedAt)
	if err != nil {
		return fmt.Errorf("create order: %w", err)
	}
	return nil
}

func (r *OrderRepo) GetByID(ctx context.Context, id string) (*model.Order, error) {
	var o model.Order
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, symbol, side, order_type, qty, price, filled_price,
		 leverage, margin_mode, margin_amount, status, COALESCE(reject_reason,''),
		 created_at, filled_at, cancelled_at
		 FROM orders WHERE id = $1`, id).
		Scan(&o.ID, &o.UserID, &o.Symbol, &o.Side, &o.OrderType, &o.Qty, &o.Price,
			&o.FilledPrice, &o.Leverage, &o.MarginMode, &o.MarginAmount, &o.Status,
			&o.RejectReason, &o.CreatedAt, &o.FilledAt, &o.CancelledAt)
	if err != nil {
		return nil, fmt.Errorf("get order: %w", err)
	}
	return &o, nil
}

func (r *OrderRepo) ListByUser(ctx context.Context, userID, status string, limit int) ([]model.Order, error) {
	if limit <= 0 {
		limit = 50
	}
	var query string
	var args []any
	if status == "" || status == "all" {
		query = `SELECT id, user_id, symbol, side, order_type, qty, price, filled_price,
		         leverage, margin_mode, margin_amount, status, COALESCE(reject_reason,''),
		         created_at, filled_at, cancelled_at
		         FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2`
		args = []any{userID, limit}
	} else {
		query = `SELECT id, user_id, symbol, side, order_type, qty, price, filled_price,
		         leverage, margin_mode, margin_amount, status, COALESCE(reject_reason,''),
		         created_at, filled_at, cancelled_at
		         FROM orders WHERE user_id = $1 AND status = $2 ORDER BY created_at DESC LIMIT $3`
		args = []any{userID, status, limit}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list orders: %w", err)
	}
	defer rows.Close()

	return scanOrders(rows)
}

func (r *OrderRepo) ListPending(ctx context.Context) ([]model.Order, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, symbol, side, order_type, qty, price, filled_price,
		 leverage, margin_mode, margin_amount, status, COALESCE(reject_reason,''),
		 created_at, filled_at, cancelled_at
		 FROM orders WHERE status = 'pending'`)
	if err != nil {
		return nil, fmt.Errorf("list pending: %w", err)
	}
	defer rows.Close()
	return scanOrders(rows)
}

func (r *OrderRepo) ListPendingBySymbol(ctx context.Context, symbol string) ([]model.Order, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, symbol, side, order_type, qty, price, filled_price,
		 leverage, margin_mode, margin_amount, status, COALESCE(reject_reason,''),
		 created_at, filled_at, cancelled_at
		 FROM orders WHERE status = 'pending' AND symbol = $1`, symbol)
	if err != nil {
		return nil, fmt.Errorf("list pending by symbol: %w", err)
	}
	defer rows.Close()
	return scanOrders(rows)
}

func (r *OrderRepo) FillOrder(ctx context.Context, id string, filledPrice float64) error {
	now := time.Now()
	_, err := r.pool.Exec(ctx,
		`UPDATE orders SET status = 'filled', filled_price = $2, filled_at = $3
		 WHERE id = $1 AND status = 'pending'`,
		id, filledPrice, now)
	if err != nil {
		return fmt.Errorf("fill order: %w", err)
	}
	return nil
}

func (r *OrderRepo) Cancel(ctx context.Context, id, userID string) (*model.Order, error) {
	var o model.Order
	now := time.Now()
	err := r.pool.QueryRow(ctx,
		`UPDATE orders SET status = 'cancelled', cancelled_at = $3
		 WHERE id = $1 AND user_id = $2 AND status = 'pending'
		 RETURNING id, user_id, symbol, side, order_type, qty, price, filled_price,
		 leverage, margin_mode, margin_amount, status, COALESCE(reject_reason,''),
		 created_at, filled_at, cancelled_at`,
		id, userID, now).
		Scan(&o.ID, &o.UserID, &o.Symbol, &o.Side, &o.OrderType, &o.Qty, &o.Price,
			&o.FilledPrice, &o.Leverage, &o.MarginMode, &o.MarginAmount, &o.Status,
			&o.RejectReason, &o.CreatedAt, &o.FilledAt, &o.CancelledAt)
	if err != nil {
		return nil, fmt.Errorf("cancel order: %w", err)
	}
	return &o, nil
}

func scanOrders(rows interface {
	Next() bool
	Scan(dest ...any) error
}) ([]model.Order, error) {
	var orders []model.Order
	for rows.Next() {
		var o model.Order
		if err := rows.Scan(&o.ID, &o.UserID, &o.Symbol, &o.Side, &o.OrderType, &o.Qty,
			&o.Price, &o.FilledPrice, &o.Leverage, &o.MarginMode, &o.MarginAmount,
			&o.Status, &o.RejectReason, &o.CreatedAt, &o.FilledAt, &o.CancelledAt); err != nil {
			return nil, err
		}
		orders = append(orders, o)
	}
	return orders, nil
}
