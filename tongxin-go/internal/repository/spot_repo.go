package repository

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type SpotRepo struct {
	pool *pgxpool.Pool
}

func NewSpotRepo(pool *pgxpool.Pool) *SpotRepo {
	return &SpotRepo{pool: pool}
}

// ── 配置 / 元数据查询 ──

// ListSupportedSymbols 返回所有上架的现货交易对。
func (r *SpotRepo) ListSupportedSymbols(ctx context.Context, category string, activeOnly bool) ([]model.SpotSupportedSymbol, error) {
	q := `
		SELECT symbol, base_asset, quote_asset, category, display_name,
		       min_qty, qty_precision, price_precision, is_active, sort_order
		FROM spot_supported_symbols
		WHERE ($1 = '' OR category = $1)
		  AND ($2 = false OR is_active = true)
		ORDER BY sort_order, symbol
	`
	rows, err := r.pool.Query(ctx, q, category, activeOnly)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]model.SpotSupportedSymbol, 0)
	for rows.Next() {
		var s model.SpotSupportedSymbol
		if err := rows.Scan(&s.Symbol, &s.BaseAsset, &s.QuoteAsset, &s.Category,
			&s.DisplayName, &s.MinQty, &s.QtyPrecision, &s.PricePrecision,
			&s.IsActive, &s.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// GetSupportedSymbol 单个交易对元数据。
func (r *SpotRepo) GetSupportedSymbol(ctx context.Context, symbol string) (*model.SpotSupportedSymbol, error) {
	var s model.SpotSupportedSymbol
	err := r.pool.QueryRow(ctx, `
		SELECT symbol, base_asset, quote_asset, category, display_name,
		       min_qty, qty_precision, price_precision, is_active, sort_order
		FROM spot_supported_symbols
		WHERE symbol = $1
	`, symbol).Scan(&s.Symbol, &s.BaseAsset, &s.QuoteAsset, &s.Category,
		&s.DisplayName, &s.MinQty, &s.QtyPrecision, &s.PricePrecision,
		&s.IsActive, &s.SortOrder)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// ListFeeSchedule 返回所有 VIP 等级的现货费率。
func (r *SpotRepo) ListFeeSchedule(ctx context.Context) ([]model.SpotFeeTier, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT vip_level, maker_fee, taker_fee, updated_at
		FROM spot_fee_schedule
		ORDER BY vip_level
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]model.SpotFeeTier, 0, 5)
	for rows.Next() {
		var t model.SpotFeeTier
		if err := rows.Scan(&t.VipLevel, &t.MakerFee, &t.TakerFee, &t.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// GetFeeRate 单个 VIP 等级的费率（fallback 到 0 级）。
func (r *SpotRepo) GetFeeRate(ctx context.Context, vipLevel int) (makerFee, takerFee float64, err error) {
	err = r.pool.QueryRow(ctx, `
		SELECT maker_fee, taker_fee
		FROM spot_fee_schedule
		WHERE vip_level = $1
	`, vipLevel).Scan(&makerFee, &takerFee)
	if errors.Is(err, pgx.ErrNoRows) {
		// fallback: VIP 0
		err = r.pool.QueryRow(ctx, `
			SELECT maker_fee, taker_fee FROM spot_fee_schedule WHERE vip_level = 0
		`).Scan(&makerFee, &takerFee)
	}
	return makerFee, takerFee, err
}

// UpdateFeeTier admin 用：调整某 VIP 等级费率。
func (r *SpotRepo) UpdateFeeTier(ctx context.Context, vipLevel int, makerFee, takerFee float64) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO spot_fee_schedule (vip_level, maker_fee, taker_fee, updated_at)
		VALUES ($1, $2, $3, NOW())
		ON CONFLICT (vip_level) DO UPDATE SET
			maker_fee = EXCLUDED.maker_fee,
			taker_fee = EXCLUDED.taker_fee,
			updated_at = NOW()
	`, vipLevel, makerFee, takerFee)
	return err
}

// ── 订单查询 ──

// GetOrder 单订单详情。
func (r *SpotRepo) GetOrder(ctx context.Context, orderID string) (*model.SpotOrder, error) {
	var o model.SpotOrder
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, user_id, symbol, base_asset, quote_asset, side, order_type,
		       qty, price, filled_price, filled_qty, quote_qty, frozen_amount,
		       status, fee, fee_asset, fee_rate, is_maker,
		       COALESCE(reject_reason,''), client_order_id,
		       created_at, filled_at, cancelled_at
		FROM spot_orders WHERE id = $1::uuid
	`, orderID).Scan(&o.ID, &o.UserID, &o.Symbol, &o.BaseAsset, &o.QuoteAsset,
		&o.Side, &o.OrderType, &o.Qty, &o.Price, &o.FilledPrice, &o.FilledQty,
		&o.QuoteQty, &o.FrozenAmount, &o.Status, &o.Fee, &o.FeeAsset,
		&o.FeeRate, &o.IsMaker, &o.RejectReason, &o.ClientOrderID,
		&o.CreatedAt, &o.FilledAt, &o.CancelledAt)
	if err != nil {
		return nil, err
	}
	return &o, nil
}

// ListUserOrders 用户订单列表（按 status 过滤）。
func (r *SpotRepo) ListUserOrders(ctx context.Context, userID, status, symbol string, limit, offset int) ([]*model.SpotOrder, int, error) {
	// count
	var total int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM spot_orders
		WHERE user_id = $1
		  AND ($2 = '' OR status = $2)
		  AND ($3 = '' OR symbol = $3)
	`, userID, status, symbol).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id::text, user_id, symbol, base_asset, quote_asset, side, order_type,
		       qty, price, filled_price, filled_qty, quote_qty, frozen_amount,
		       status, fee, fee_asset, fee_rate, is_maker,
		       COALESCE(reject_reason,''), client_order_id,
		       created_at, filled_at, cancelled_at
		FROM spot_orders
		WHERE user_id = $1
		  AND ($2 = '' OR status = $2)
		  AND ($3 = '' OR symbol = $3)
		ORDER BY created_at DESC
		LIMIT $4 OFFSET $5
	`, userID, status, symbol, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	out := make([]*model.SpotOrder, 0, limit)
	for rows.Next() {
		o := &model.SpotOrder{}
		if err := rows.Scan(&o.ID, &o.UserID, &o.Symbol, &o.BaseAsset, &o.QuoteAsset,
			&o.Side, &o.OrderType, &o.Qty, &o.Price, &o.FilledPrice, &o.FilledQty,
			&o.QuoteQty, &o.FrozenAmount, &o.Status, &o.Fee, &o.FeeAsset,
			&o.FeeRate, &o.IsMaker, &o.RejectReason, &o.ClientOrderID,
			&o.CreatedAt, &o.FilledAt, &o.CancelledAt); err != nil {
			return nil, 0, err
		}
		out = append(out, o)
	}
	return out, total, rows.Err()
}

// ListPendingOrdersForSymbol 内存加载用：所有 pending 限价单。
func (r *SpotRepo) ListPendingOrdersForSymbol(ctx context.Context, symbol string) ([]*model.SpotOrder, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, user_id, symbol, base_asset, quote_asset, side, order_type,
		       qty, price, filled_price, filled_qty, quote_qty, frozen_amount,
		       status, fee, fee_asset, fee_rate, is_maker,
		       COALESCE(reject_reason,''), client_order_id,
		       created_at, filled_at, cancelled_at
		FROM spot_orders
		WHERE status = 'pending'
		  AND ($1 = '' OR symbol = $1)
		ORDER BY created_at
	`, symbol)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]*model.SpotOrder, 0)
	for rows.Next() {
		o := &model.SpotOrder{}
		if err := rows.Scan(&o.ID, &o.UserID, &o.Symbol, &o.BaseAsset, &o.QuoteAsset,
			&o.Side, &o.OrderType, &o.Qty, &o.Price, &o.FilledPrice, &o.FilledQty,
			&o.QuoteQty, &o.FrozenAmount, &o.Status, &o.Fee, &o.FeeAsset,
			&o.FeeRate, &o.IsMaker, &o.RejectReason, &o.ClientOrderID,
			&o.CreatedAt, &o.FilledAt, &o.CancelledAt); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// ── 资产持仓 ──

// GetSpotBalance 返回某币种 main 账户下的 available + frozen。
func (r *SpotRepo) GetSpotBalance(ctx context.Context, userID, asset string) (available, frozen float64, err error) {
	err = r.pool.QueryRow(ctx, `
		SELECT COALESCE(ab.available, 0), COALESCE(ab.frozen, 0)
		FROM asset_accounts aa
		LEFT JOIN asset_balances ab
		  ON ab.account_id = aa.id AND ab.asset_code = $2
		WHERE aa.user_id = $1
		  AND aa.account_type IN ('main', 'spot')
		ORDER BY CASE WHEN aa.account_type = 'spot' THEN 0 ELSE 1 END
		LIMIT 1
	`, userID, strings.ToUpper(asset)).Scan(&available, &frozen)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, 0, nil
	}
	return available, frozen, err
}

// ── 核心成交事务 ──

// PlaceMarketOrderResult 市价单成交后的结果（已含手续费扣除）。
type PlaceMarketOrderResult struct {
	OrderID         string
	FilledPrice     float64
	FilledQty       float64
	QuoteQty        float64
	Fee             float64
	BaseAvailable   float64 // 成交后 base 可用
	QuoteAvailable  float64 // 成交后 quote 可用
}

// ExecuteSpotMarketOrder 市价单全流程原子执行（buy 或 sell）。
//
// buy:  USDT.available -= (cost + fee), BTC.available += qty
// sell: BTC.available -= qty,           USDT.available += (proceeds - fee)
//
// 成交价 = filledPrice（service 层从 cache 读取最新价后传入）。
func (r *SpotRepo) ExecuteSpotMarketOrder(ctx context.Context, params struct {
	UserID        string
	Symbol        string
	BaseAsset     string
	QuoteAsset    string
	Side          string  // buy / sell
	Qty           float64
	FilledPrice   float64
	FeeRate       float64
	ClientOrderID *string
}) (*PlaceMarketOrderResult, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// 1. 解析 main 账户 ID
	var accountID string
	if err := tx.QueryRow(ctx, `
		SELECT id::text FROM asset_accounts
		WHERE user_id = $1 AND account_type IN ('main','spot')
		ORDER BY CASE WHEN account_type = 'spot' THEN 0 ELSE 1 END
		LIMIT 1
	`, params.UserID).Scan(&accountID); err != nil {
		return nil, fmt.Errorf("resolve main account: %w", err)
	}

	quoteCost := params.Qty * params.FilledPrice
	fee := quoteCost * params.FeeRate

	var (
		baseAvailable  float64
		quoteAvailable float64
	)

	if params.Side == model.SpotSideBuy {
		// 扣 quote (USDT) = cost + fee
		needed := quoteCost + fee
		// 扣减 quote
		tag, err := tx.Exec(ctx, `
			UPDATE asset_balances
			SET available = available - $1, updated_at = NOW()
			WHERE account_id = $2::uuid AND asset_code = $3 AND available >= $1
		`, needed, accountID, params.QuoteAsset)
		if err != nil {
			return nil, fmt.Errorf("debit quote: %w", err)
		}
		if tag.RowsAffected() == 0 {
			return nil, ErrInsufficientBalance
		}
		// 读最新 quote available
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, params.QuoteAsset).Scan(&quoteAvailable); err != nil {
			return nil, fmt.Errorf("read quote available: %w", err)
		}

		// 加 base (BTC)
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_balances (account_id, asset_code, available, frozen, updated_at)
			VALUES ($1::uuid, $2, $3, 0, NOW())
			ON CONFLICT (account_id, asset_code) DO UPDATE
			SET available = asset_balances.available + EXCLUDED.available, updated_at = NOW()
		`, accountID, params.BaseAsset, params.Qty); err != nil {
			return nil, fmt.Errorf("credit base: %w", err)
		}
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, params.BaseAsset).Scan(&baseAvailable); err != nil {
			return nil, fmt.Errorf("read base available: %w", err)
		}
	} else if params.Side == model.SpotSideSell {
		// 扣 base
		tag, err := tx.Exec(ctx, `
			UPDATE asset_balances
			SET available = available - $1, updated_at = NOW()
			WHERE account_id = $2::uuid AND asset_code = $3 AND available >= $1
		`, params.Qty, accountID, params.BaseAsset)
		if err != nil {
			return nil, fmt.Errorf("debit base: %w", err)
		}
		if tag.RowsAffected() == 0 {
			return nil, ErrInsufficientBalance
		}
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, params.BaseAsset).Scan(&baseAvailable); err != nil {
			return nil, fmt.Errorf("read base available: %w", err)
		}

		// 加 quote = proceeds - fee
		proceeds := quoteCost - fee
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_balances (account_id, asset_code, available, frozen, updated_at)
			VALUES ($1::uuid, $2, $3, 0, NOW())
			ON CONFLICT (account_id, asset_code) DO UPDATE
			SET available = asset_balances.available + EXCLUDED.available, updated_at = NOW()
		`, accountID, params.QuoteAsset, proceeds); err != nil {
			return nil, fmt.Errorf("credit quote: %w", err)
		}
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, params.QuoteAsset).Scan(&quoteAvailable); err != nil {
			return nil, fmt.Errorf("read quote available: %w", err)
		}
	} else {
		return nil, fmt.Errorf("invalid side: %s", params.Side)
	}

	// 2. 写 spot_orders
	var orderID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO spot_orders (
			user_id, symbol, base_asset, quote_asset, side, order_type,
			qty, filled_price, filled_qty, quote_qty,
			status, fee, fee_asset, fee_rate, is_maker, client_order_id,
			filled_at
		) VALUES (
			$1, $2, $3, $4, $5, 'market',
			$6, $7, $6, $8,
			'filled', $9, $4, $10, false, $11,
			NOW()
		) RETURNING id::text
	`, params.UserID, params.Symbol, params.BaseAsset, params.QuoteAsset, params.Side,
		params.Qty, params.FilledPrice, quoteCost, fee, params.FeeRate,
		params.ClientOrderID).Scan(&orderID); err != nil {
		return nil, fmt.Errorf("insert spot_order: %w", err)
	}

	// 3. 写 ledger entries
	if err := r.writeSpotLedger(ctx, tx, params.UserID, accountID, params.BaseAsset, params.QuoteAsset,
		params.Side, params.Qty, quoteCost, fee, baseAvailable, quoteAvailable, orderID); err != nil {
		return nil, err
	}

	// 4. 写 wallet_transactions（汇总型，方便对账）
	walletTxType := "spot_buy"
	if params.Side == model.SpotSideSell {
		walletTxType = "spot_sell"
	}
	noteText := fmt.Sprintf("%s %s @ %.8f", strings.ToUpper(params.Side), params.Symbol, params.FilledPrice)
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
		VALUES ($1, $2, $3, 0, $4, $5)
	`, params.UserID, walletTxType, quoteCost, orderID, noteText); err != nil {
		return nil, fmt.Errorf("write wallet_tx: %w", err)
	}

	// fee 单独一行
	if fee > 0 {
		if _, err := tx.Exec(ctx, `
			INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
			VALUES ($1, 'spot_fee', $2, 0, $3, $4)
		`, params.UserID, fee, orderID, fmt.Sprintf("Spot fee %s", params.Symbol)); err != nil {
			return nil, fmt.Errorf("write fee tx: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &PlaceMarketOrderResult{
		OrderID:        orderID,
		FilledPrice:    params.FilledPrice,
		FilledQty:      params.Qty,
		QuoteQty:       quoteCost,
		Fee:            fee,
		BaseAvailable:  baseAvailable,
		QuoteAvailable: quoteAvailable,
	}, nil
}

// PlaceLimitOrderParams 限价单挂单参数。
type PlaceLimitOrderParams struct {
	UserID        string
	Symbol        string
	BaseAsset     string
	QuoteAsset    string
	Side          string
	Qty           float64
	Price         float64
	FeeRate       float64 // 用 maker fee
	ClientOrderID *string
}

// ExecuteSpotLimitPlace 限价单挂单：冻结资产 + 写 spot_orders(status=pending)。
func (r *SpotRepo) ExecuteSpotLimitPlace(ctx context.Context, p PlaceLimitOrderParams) (string, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	var accountID string
	if err := tx.QueryRow(ctx, `
		SELECT id::text FROM asset_accounts
		WHERE user_id = $1 AND account_type IN ('main','spot')
		ORDER BY CASE WHEN account_type = 'spot' THEN 0 ELSE 1 END
		LIMIT 1
	`, p.UserID).Scan(&accountID); err != nil {
		return "", fmt.Errorf("resolve main account: %w", err)
	}

	quoteCost := p.Qty * p.Price
	fee := quoteCost * p.FeeRate

	var (
		freezeAsset  string
		freezeAmount float64
	)
	if p.Side == model.SpotSideBuy {
		freezeAsset = p.QuoteAsset
		freezeAmount = quoteCost + fee
	} else {
		freezeAsset = p.BaseAsset
		freezeAmount = p.Qty
	}

	// 冻结：available -= freezeAmount, frozen += freezeAmount
	tag, err := tx.Exec(ctx, `
		UPDATE asset_balances
		SET available = available - $1, frozen = frozen + $1, updated_at = NOW()
		WHERE account_id = $2::uuid AND asset_code = $3 AND available >= $1
	`, freezeAmount, accountID, freezeAsset)
	if err != nil {
		return "", fmt.Errorf("freeze: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return "", ErrInsufficientBalance
	}

	// 写订单
	var orderID string
	if err := tx.QueryRow(ctx, `
		INSERT INTO spot_orders (
			user_id, symbol, base_asset, quote_asset, side, order_type,
			qty, price, frozen_amount,
			status, fee_rate, is_maker, client_order_id
		) VALUES (
			$1, $2, $3, $4, $5, 'limit',
			$6, $7, $8,
			'pending', $9, true, $10
		) RETURNING id::text
	`, p.UserID, p.Symbol, p.BaseAsset, p.QuoteAsset, p.Side,
		p.Qty, p.Price, freezeAmount, p.FeeRate, p.ClientOrderID).Scan(&orderID); err != nil {
		return "", fmt.Errorf("insert pending: %w", err)
	}

	// ledger（freeze 记录）
	var availableAfter, frozenAfter float64
	if err := tx.QueryRow(ctx, `
		SELECT available, frozen FROM asset_balances
		WHERE account_id = $1::uuid AND asset_code = $2
	`, accountID, freezeAsset).Scan(&availableAfter, &frozenAfter); err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO asset_ledger_entries (
			user_id, account_id, asset_code, direction, entry_type,
			amount, available_after, frozen_after, ref_type, ref_id, note
		) VALUES ($1, $2::uuid, $3, 'debit', 'spot_freeze', $4, $5, $6, 'spot_order', $7, $8)
	`, p.UserID, accountID, freezeAsset, freezeAmount, availableAfter, frozenAfter,
		orderID, fmt.Sprintf("Freeze for %s %s @ %.8f", strings.ToUpper(p.Side), p.Symbol, p.Price)); err != nil {
		return "", err
	}

	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return orderID, nil
}

// ExecuteSpotLimitFill 限价单到价成交：解冻 + 资产兑换 + 标记 filled。
func (r *SpotRepo) ExecuteSpotLimitFill(ctx context.Context, order *model.SpotOrder, fillPrice float64) (*PlaceMarketOrderResult, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// 重新读订单做 lock + 校验状态
	var status string
	if err := tx.QueryRow(ctx, `
		SELECT status FROM spot_orders WHERE id = $1::uuid FOR UPDATE
	`, order.ID).Scan(&status); err != nil {
		return nil, err
	}
	if status != model.SpotOrderStatusPending {
		return nil, fmt.Errorf("order not pending: %s", status)
	}

	var accountID string
	if err := tx.QueryRow(ctx, `
		SELECT id::text FROM asset_accounts
		WHERE user_id = $1 AND account_type IN ('main','spot')
		ORDER BY CASE WHEN account_type = 'spot' THEN 0 ELSE 1 END
		LIMIT 1
	`, order.UserID).Scan(&accountID); err != nil {
		return nil, err
	}

	quoteCost := order.Qty * fillPrice
	fee := quoteCost * order.FeeRate

	var (
		baseAvailable  float64
		quoteAvailable float64
	)

	if order.Side == model.SpotSideBuy {
		// 解冻 quote 全额，然后扣 (cost + fee) 实际花费
		// 由于挂单时按限价 freeze，成交价 ≤ 限价 ⇒ 实际花费 ≤ frozen
		// 退还差额到 available
		actualCost := quoteCost + fee
		refund := order.FrozenAmount - actualCost
		if refund < 0 {
			refund = 0 // 防御性
			actualCost = order.FrozenAmount
		}
		// frozen -= frozenAmount, available += refund
		if _, err := tx.Exec(ctx, `
			UPDATE asset_balances
			SET frozen = frozen - $1, available = available + $2, updated_at = NOW()
			WHERE account_id = $3::uuid AND asset_code = $4
		`, order.FrozenAmount, refund, accountID, order.QuoteAsset); err != nil {
			return nil, fmt.Errorf("unfreeze quote: %w", err)
		}
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, order.QuoteAsset).Scan(&quoteAvailable); err != nil {
			return nil, err
		}

		// 加 base
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_balances (account_id, asset_code, available, frozen, updated_at)
			VALUES ($1::uuid, $2, $3, 0, NOW())
			ON CONFLICT (account_id, asset_code) DO UPDATE
			SET available = asset_balances.available + EXCLUDED.available, updated_at = NOW()
		`, accountID, order.BaseAsset, order.Qty); err != nil {
			return nil, err
		}
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, order.BaseAsset).Scan(&baseAvailable); err != nil {
			return nil, err
		}
	} else {
		// sell: 解冻 base = qty (frozen 就是 qty)；加 quote = proceeds - fee
		if _, err := tx.Exec(ctx, `
			UPDATE asset_balances
			SET frozen = frozen - $1, updated_at = NOW()
			WHERE account_id = $2::uuid AND asset_code = $3
		`, order.FrozenAmount, accountID, order.BaseAsset); err != nil {
			return nil, err
		}
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, order.BaseAsset).Scan(&baseAvailable); err != nil {
			return nil, err
		}

		proceeds := quoteCost - fee
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_balances (account_id, asset_code, available, frozen, updated_at)
			VALUES ($1::uuid, $2, $3, 0, NOW())
			ON CONFLICT (account_id, asset_code) DO UPDATE
			SET available = asset_balances.available + EXCLUDED.available, updated_at = NOW()
		`, accountID, order.QuoteAsset, proceeds); err != nil {
			return nil, err
		}
		if err := tx.QueryRow(ctx, `
			SELECT available FROM asset_balances WHERE account_id = $1::uuid AND asset_code = $2
		`, accountID, order.QuoteAsset).Scan(&quoteAvailable); err != nil {
			return nil, err
		}
	}

	// mark filled
	if _, err := tx.Exec(ctx, `
		UPDATE spot_orders
		SET status = 'filled',
		    filled_price = $1,
		    filled_qty = qty,
		    quote_qty = $2,
		    fee = $3,
		    filled_at = NOW()
		WHERE id = $4::uuid
	`, fillPrice, quoteCost, fee, order.ID); err != nil {
		return nil, err
	}

	// ledger
	if err := r.writeSpotLedger(ctx, tx, order.UserID, accountID, order.BaseAsset, order.QuoteAsset,
		order.Side, order.Qty, quoteCost, fee, baseAvailable, quoteAvailable, order.ID); err != nil {
		return nil, err
	}

	// wallet_tx 汇总
	walletTxType := "spot_buy"
	if order.Side == model.SpotSideSell {
		walletTxType = "spot_sell"
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
		VALUES ($1, $2, $3, 0, $4, $5)
	`, order.UserID, walletTxType, quoteCost, order.ID,
		fmt.Sprintf("LIMIT %s %s @ %.8f", strings.ToUpper(order.Side), order.Symbol, fillPrice)); err != nil {
		return nil, err
	}
	if fee > 0 {
		if _, err := tx.Exec(ctx, `
			INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
			VALUES ($1, 'spot_fee', $2, 0, $3, $4)
		`, order.UserID, fee, order.ID, fmt.Sprintf("Spot fee %s", order.Symbol)); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &PlaceMarketOrderResult{
		OrderID:        order.ID,
		FilledPrice:    fillPrice,
		FilledQty:      order.Qty,
		QuoteQty:       quoteCost,
		Fee:            fee,
		BaseAvailable:  baseAvailable,
		QuoteAvailable: quoteAvailable,
	}, nil
}

// ExecuteSpotLimitCancel 取消限价单：解冻 + 标记 cancelled。
func (r *SpotRepo) ExecuteSpotLimitCancel(ctx context.Context, orderID, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// FOR UPDATE 锁住，避免与 Fill 竞态
	var (
		status, side, baseAsset, quoteAsset string
		frozenAmount                        float64
		ownerUID                            string
	)
	if err := tx.QueryRow(ctx, `
		SELECT user_id, status, side, base_asset, quote_asset, frozen_amount
		FROM spot_orders WHERE id = $1::uuid FOR UPDATE
	`, orderID).Scan(&ownerUID, &status, &side, &baseAsset, &quoteAsset, &frozenAmount); err != nil {
		return err
	}
	if ownerUID != userID {
		return ErrOrderForbidden
	}
	if status != model.SpotOrderStatusPending {
		return fmt.Errorf("order not pending: %s", status)
	}

	var accountID string
	if err := tx.QueryRow(ctx, `
		SELECT id::text FROM asset_accounts
		WHERE user_id = $1 AND account_type IN ('main','spot')
		ORDER BY CASE WHEN account_type = 'spot' THEN 0 ELSE 1 END
		LIMIT 1
	`, userID).Scan(&accountID); err != nil {
		return err
	}

	freezeAsset := quoteAsset
	if side == model.SpotSideSell {
		freezeAsset = baseAsset
	}

	// 解冻：frozen -= freezeAmount, available += freezeAmount
	if _, err := tx.Exec(ctx, `
		UPDATE asset_balances
		SET frozen = frozen - $1, available = available + $1, updated_at = NOW()
		WHERE account_id = $2::uuid AND asset_code = $3
	`, frozenAmount, accountID, freezeAsset); err != nil {
		return err
	}

	// mark cancelled
	if _, err := tx.Exec(ctx, `
		UPDATE spot_orders
		SET status = 'cancelled', cancelled_at = NOW()
		WHERE id = $1::uuid
	`, orderID); err != nil {
		return err
	}

	// ledger（unfreeze 记录）
	var availableAfter, frozenAfter float64
	if err := tx.QueryRow(ctx, `
		SELECT available, frozen FROM asset_balances
		WHERE account_id = $1::uuid AND asset_code = $2
	`, accountID, freezeAsset).Scan(&availableAfter, &frozenAfter); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO asset_ledger_entries (
			user_id, account_id, asset_code, direction, entry_type,
			amount, available_after, frozen_after, ref_type, ref_id, note
		) VALUES ($1, $2::uuid, $3, 'credit', 'spot_unfreeze', $4, $5, $6, 'spot_order', $7, 'Limit order cancelled')
	`, userID, accountID, freezeAsset, frozenAmount, availableAfter, frozenAfter, orderID); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// ── 内部 helpers ──

// writeSpotLedger 在 tx 内写两条 ledger entries（base + quote）。
func (r *SpotRepo) writeSpotLedger(ctx context.Context, tx pgx.Tx, userID, accountID, baseAsset, quoteAsset, side string, qty, quoteCost, fee, baseAvailable, quoteAvailable float64, orderID string) error {
	if side == model.SpotSideBuy {
		// debit quote (cost + fee), credit base (qty)
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_ledger_entries (
				user_id, account_id, asset_code, direction, entry_type,
				amount, available_after, ref_type, ref_id, note
			) VALUES ($1, $2::uuid, $3, 'debit', 'spot_buy', $4, $5, 'spot_order', $6, 'Spot buy quote leg')
		`, userID, accountID, quoteAsset, quoteCost+fee, quoteAvailable, orderID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_ledger_entries (
				user_id, account_id, asset_code, direction, entry_type,
				amount, available_after, ref_type, ref_id, note
			) VALUES ($1, $2::uuid, $3, 'credit', 'spot_buy', $4, $5, 'spot_order', $6, 'Spot buy base leg')
		`, userID, accountID, baseAsset, qty, baseAvailable, orderID); err != nil {
			return err
		}
	} else {
		// debit base (qty), credit quote (proceeds - fee)
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_ledger_entries (
				user_id, account_id, asset_code, direction, entry_type,
				amount, available_after, ref_type, ref_id, note
			) VALUES ($1, $2::uuid, $3, 'debit', 'spot_sell', $4, $5, 'spot_order', $6, 'Spot sell base leg')
		`, userID, accountID, baseAsset, qty, baseAvailable, orderID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_ledger_entries (
				user_id, account_id, asset_code, direction, entry_type,
				amount, available_after, ref_type, ref_id, note
			) VALUES ($1, $2::uuid, $3, 'credit', 'spot_sell', $4, $5, 'spot_order', $6, 'Spot sell quote leg')
		`, userID, accountID, quoteAsset, quoteCost-fee, quoteAvailable, orderID); err != nil {
			return err
		}
	}
	// fee leg
	if fee > 0 {
		if _, err := tx.Exec(ctx, `
			INSERT INTO asset_ledger_entries (
				user_id, account_id, asset_code, direction, entry_type,
				amount, available_after, ref_type, ref_id, note
			) VALUES ($1, $2::uuid, $3, 'debit', 'spot_fee', $4, $5, 'spot_order', $6, 'Spot trading fee')
		`, userID, accountID, quoteAsset, fee, quoteAvailable, orderID); err != nil {
			return err
		}
	}
	return nil
}

// ── 错误 ──

var (
	ErrInsufficientBalance = errors.New("insufficient balance")
	ErrOrderForbidden      = errors.New("order does not belong to user")
)
