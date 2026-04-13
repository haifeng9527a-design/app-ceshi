package repository

import (
	"context"
	"fmt"
	"strings"

	"tongxin-go/internal/model"
)

type TransactionFilters struct {
	UserID string
	Type   string
	Limit  int
	Offset int
}

// GetPlatformFeeStats returns fee income aggregated by time periods.
func (r *WalletRepo) GetPlatformFeeStats(ctx context.Context) (*model.FeeStats, error) {
	var s model.FeeStats

	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(ABS(amount)),0) FROM wallet_transactions WHERE type='fee' AND created_at >= CURRENT_DATE`).
		Scan(&s.TodayFees)
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(ABS(amount)),0) FROM wallet_transactions WHERE type='fee' AND created_at >= date_trunc('week', CURRENT_DATE)`).
		Scan(&s.WeekFees)
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(ABS(amount)),0) FROM wallet_transactions WHERE type='fee' AND created_at >= date_trunc('month', CURRENT_DATE)`).
		Scan(&s.MonthFees)
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(ABS(amount)),0) FROM wallet_transactions WHERE type='fee'`).
		Scan(&s.TotalFees)

	return &s, nil
}

// ListAll returns all wallets with user info for admin view.
func (r *WalletRepo) ListAll(ctx context.Context, limit, offset int) ([]map[string]any, int, error) {
	var total int
	if err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM wallets`).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx,
		`SELECT w.user_id, COALESCE(u.display_name,''), COALESCE(u.email,''),
		 w.balance, w.frozen, w.total_deposit, w.updated_at
		 FROM wallets w LEFT JOIN users u ON u.uid=w.user_id
		 ORDER BY w.balance DESC LIMIT $1 OFFSET $2`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		var userID, dn, email string
		var balance, frozen, deposit float64
		var updatedAt interface{}
		if err := rows.Scan(&userID, &dn, &email, &balance, &frozen, &deposit, &updatedAt); err != nil {
			return nil, 0, err
		}
		results = append(results, map[string]any{
			"user_id": userID, "display_name": dn, "email": email,
			"balance": balance, "frozen": frozen, "total_deposit": deposit,
			"updated_at": updatedAt,
		})
	}
	return results, total, nil
}

// ListAllTransactions returns cross-user wallet transactions for admin.
func (r *WalletRepo) ListAllTransactions(ctx context.Context, f TransactionFilters) ([]map[string]any, int, error) {
	where := []string{"1=1"}
	args := []any{}
	idx := 1

	if f.UserID != "" {
		where = append(where, fmt.Sprintf("wt.user_id=$%d", idx))
		args = append(args, f.UserID)
		idx++
	}
	if f.Type != "" {
		where = append(where, fmt.Sprintf("wt.type=$%d", idx))
		args = append(args, f.Type)
		idx++
	}

	whereClause := strings.Join(where, " AND ")

	var total int
	if err := r.pool.QueryRow(ctx,
		fmt.Sprintf(`SELECT COUNT(*) FROM wallet_transactions wt WHERE %s`, whereClause), args...).
		Scan(&total); err != nil {
		return nil, 0, err
	}

	dataQ := fmt.Sprintf(`SELECT wt.id, wt.user_id, COALESCE(u.display_name,''), wt.type, wt.amount,
		wt.balance_after, wt.ref_id, wt.note, wt.created_at
		FROM wallet_transactions wt LEFT JOIN users u ON u.uid=wt.user_id
		WHERE %s ORDER BY wt.created_at DESC LIMIT $%d OFFSET $%d`, whereClause, idx, idx+1)
	args = append(args, f.Limit, f.Offset)

	rows, err := r.pool.Query(ctx, dataQ, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		var id, uid, dn, typ, refID, note string
		var amount, balAfter float64
		var createdAt interface{}
		if err := rows.Scan(&id, &uid, &dn, &typ, &amount, &balAfter, &refID, &note, &createdAt); err != nil {
			return nil, 0, err
		}
		results = append(results, map[string]any{
			"id": id, "user_id": uid, "display_name": dn, "type": typ,
			"amount": amount, "balance_after": balAfter, "ref_id": refID,
			"note": note, "created_at": createdAt,
		})
	}
	return results, total, nil
}
