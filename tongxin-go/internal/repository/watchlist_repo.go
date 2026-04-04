package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

type WatchlistRepo struct {
	pool *pgxpool.Pool
}

func NewWatchlistRepo(pool *pgxpool.Pool) *WatchlistRepo {
	return &WatchlistRepo{pool: pool}
}

type WatchlistItem struct {
	Symbol     string `json:"symbol"`
	SymbolType string `json:"symbol_type"`
	AddedAt    string `json:"added_at"`
}

func (r *WatchlistRepo) List(ctx context.Context, uid string) ([]WatchlistItem, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT symbol, symbol_type, added_at::text
		FROM watchlist WHERE user_id = $1 ORDER BY added_at DESC
	`, uid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []WatchlistItem
	for rows.Next() {
		var item WatchlistItem
		if err := rows.Scan(&item.Symbol, &item.SymbolType, &item.AddedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func (r *WatchlistRepo) Add(ctx context.Context, uid, symbol, symbolType string) error {
	if symbolType == "" {
		symbolType = "stock"
	}
	_, err := r.pool.Exec(ctx, `
		INSERT INTO watchlist (user_id, symbol, symbol_type) VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING
	`, uid, symbol, symbolType)
	return err
}

func (r *WatchlistRepo) Remove(ctx context.Context, uid, symbol string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM watchlist WHERE user_id = $1 AND symbol = $2`, uid, symbol)
	return err
}

func (r *WatchlistRepo) Check(ctx context.Context, uid, symbol string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM watchlist WHERE user_id = $1 AND symbol = $2)
	`, uid, symbol).Scan(&exists)
	return exists, err
}
