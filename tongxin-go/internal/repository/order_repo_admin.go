package repository

import (
	"context"
	"fmt"
	"strings"
)

type OrderFilters struct {
	Status string
	Symbol string
	UserID string
	Limit  int
	Offset int
}

// ListAllFiltered returns all orders with user display_name for admin.
func (r *OrderRepo) ListAllFiltered(ctx context.Context, f OrderFilters) ([]map[string]any, int, error) {
	where := []string{"1=1"}
	args := []any{}
	idx := 1

	if f.Status != "" {
		where = append(where, fmt.Sprintf("o.status=$%d", idx))
		args = append(args, f.Status)
		idx++
	}
	if f.Symbol != "" {
		where = append(where, fmt.Sprintf("o.symbol=$%d", idx))
		args = append(args, f.Symbol)
		idx++
	}
	if f.UserID != "" {
		where = append(where, fmt.Sprintf("o.user_id=$%d", idx))
		args = append(args, f.UserID)
		idx++
	}

	whereClause := strings.Join(where, " AND ")

	var total int
	if err := r.pool.QueryRow(ctx,
		fmt.Sprintf(`SELECT COUNT(*) FROM orders o WHERE %s`, whereClause), args...).
		Scan(&total); err != nil {
		return nil, 0, err
	}

	dataQ := fmt.Sprintf(`SELECT o.id, o.user_id, COALESCE(u.display_name,''), o.symbol, o.side,
		o.order_type, o.qty, o.price, o.filled_price, o.leverage, o.margin_amount,
		o.status, o.fee, o.is_copy_trade, o.created_at, o.filled_at
		FROM orders o LEFT JOIN users u ON u.uid=o.user_id
		WHERE %s ORDER BY o.created_at DESC LIMIT $%d OFFSET $%d`,
		whereClause, idx, idx+1)
	args = append(args, f.Limit, f.Offset)

	rows, err := r.pool.Query(ctx, dataQ, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		var id, uid, dn, symbol, side, orderType, status string
		var qty, margin, fee float64
		var price, filledPrice *float64
		var leverage int
		var isCopy bool
		var createdAt, filledAt interface{}
		if err := rows.Scan(&id, &uid, &dn, &symbol, &side, &orderType, &qty,
			&price, &filledPrice, &leverage, &margin, &status, &fee, &isCopy,
			&createdAt, &filledAt); err != nil {
			return nil, 0, err
		}
		results = append(results, map[string]any{
			"id": id, "user_id": uid, "display_name": dn, "symbol": symbol,
			"side": side, "order_type": orderType, "qty": qty,
			"price": price, "filled_price": filledPrice, "leverage": leverage,
			"margin_amount": margin, "status": status, "fee": fee,
			"is_copy_trade": isCopy, "created_at": createdAt, "filled_at": filledAt,
		})
	}
	return results, total, nil
}
