package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type TraderRepo struct {
	pool *pgxpool.Pool
}

func NewTraderRepo(pool *pgxpool.Pool) *TraderRepo {
	return &TraderRepo{pool: pool}
}

// ── Application ──

func (r *TraderRepo) CreateApplication(ctx context.Context, uid string, req *model.SubmitApplicationRequest) (*model.TraderApplication, error) {
	app := &model.TraderApplication{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO trader_applications (user_id, real_name, id_number, phone, nationality, address,
			experience_years, markets, capital_source, estimated_volume, risk_agreed, terms_agreed)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		RETURNING id, user_id, status, real_name, id_number, phone, nationality, address,
			experience_years, markets, capital_source, estimated_volume, risk_agreed, terms_agreed,
			reviewed_by, reviewed_at, rejection_reason, created_at, updated_at
	`, uid, req.RealName, req.IDNumber, req.Phone, req.Nationality, req.Address,
		req.ExperienceYears, req.Markets, req.CapitalSource, req.EstimatedVolume,
		req.RiskAgreed, req.TermsAgreed,
	).Scan(
		&app.ID, &app.UserID, &app.Status, &app.RealName, &app.IDNumber, &app.Phone,
		&app.Nationality, &app.Address, &app.ExperienceYears, &app.Markets,
		&app.CapitalSource, &app.EstimatedVolume, &app.RiskAgreed, &app.TermsAgreed,
		&app.ReviewedBy, &app.ReviewedAt, &app.RejectionReason, &app.CreatedAt, &app.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create application: %w", err)
	}
	return app, nil
}

func (r *TraderRepo) GetApplicationByUserID(ctx context.Context, uid string) (*model.TraderApplication, error) {
	app := &model.TraderApplication{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, status, real_name, id_number, phone, nationality, address,
			experience_years, markets, capital_source, estimated_volume, risk_agreed, terms_agreed,
			reviewed_by, reviewed_at, rejection_reason, created_at, updated_at
		FROM trader_applications
		WHERE user_id = $1
		ORDER BY created_at DESC LIMIT 1
	`, uid).Scan(
		&app.ID, &app.UserID, &app.Status, &app.RealName, &app.IDNumber, &app.Phone,
		&app.Nationality, &app.Address, &app.ExperienceYears, &app.Markets,
		&app.CapitalSource, &app.EstimatedVolume, &app.RiskAgreed, &app.TermsAgreed,
		&app.ReviewedBy, &app.ReviewedAt, &app.RejectionReason, &app.CreatedAt, &app.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return app, nil
}

func (r *TraderRepo) ListApplications(ctx context.Context, status string, limit, offset int) ([]model.TraderApplication, int, error) {
	var total int
	query := `SELECT COUNT(*) FROM trader_applications`
	args := []any{}
	if status != "" {
		query += ` WHERE status = $1`
		args = append(args, status)
	}
	err := r.pool.QueryRow(ctx, query, args...).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count applications: %w", err)
	}

	listQuery := `
		SELECT a.id, a.user_id, a.status, a.real_name, a.id_number, a.phone,
			a.nationality, a.address, a.experience_years, a.markets,
			a.capital_source, a.estimated_volume, a.risk_agreed, a.terms_agreed,
			a.reviewed_by, a.reviewed_at, a.rejection_reason, a.created_at, a.updated_at,
			COALESCE(u.display_name,''), COALESCE(u.email,''), COALESCE(u.avatar_url,'')
		FROM trader_applications a
		JOIN users u ON u.uid = a.user_id
	`
	listArgs := []any{}
	if status != "" {
		listQuery += ` WHERE a.status = $1 ORDER BY a.created_at DESC LIMIT $2 OFFSET $3`
		listArgs = append(listArgs, status, limit, offset)
	} else {
		listQuery += ` ORDER BY a.created_at DESC LIMIT $1 OFFSET $2`
		listArgs = append(listArgs, limit, offset)
	}

	rows, err := r.pool.Query(ctx, listQuery, listArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("list applications: %w", err)
	}
	defer rows.Close()

	var apps []model.TraderApplication
	for rows.Next() {
		var a model.TraderApplication
		if err := rows.Scan(
			&a.ID, &a.UserID, &a.Status, &a.RealName, &a.IDNumber, &a.Phone,
			&a.Nationality, &a.Address, &a.ExperienceYears, &a.Markets,
			&a.CapitalSource, &a.EstimatedVolume, &a.RiskAgreed, &a.TermsAgreed,
			&a.ReviewedBy, &a.ReviewedAt, &a.RejectionReason, &a.CreatedAt, &a.UpdatedAt,
			&a.DisplayName, &a.Email, &a.AvatarURL,
		); err != nil {
			return nil, 0, err
		}
		apps = append(apps, a)
	}
	return apps, total, nil
}

func (r *TraderRepo) UpdateApplicationStatus(ctx context.Context, id, status, reviewedBy, reason string) error {
	now := time.Now()
	_, err := r.pool.Exec(ctx, `
		UPDATE trader_applications
		SET status = $2, reviewed_by = $3, reviewed_at = $4, rejection_reason = $5, updated_at = $6
		WHERE id = $1
	`, id, status, reviewedBy, now, reason, now)
	return err
}

func (r *TraderRepo) GetApplicationByID(ctx context.Context, id string) (*model.TraderApplication, error) {
	app := &model.TraderApplication{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, status, real_name, id_number, phone, nationality, address,
			experience_years, markets, capital_source, estimated_volume, risk_agreed, terms_agreed,
			reviewed_by, reviewed_at, rejection_reason, created_at, updated_at
		FROM trader_applications WHERE id = $1
	`, id).Scan(
		&app.ID, &app.UserID, &app.Status, &app.RealName, &app.IDNumber, &app.Phone,
		&app.Nationality, &app.Address, &app.ExperienceYears, &app.Markets,
		&app.CapitalSource, &app.EstimatedVolume, &app.RiskAgreed, &app.TermsAgreed,
		&app.ReviewedBy, &app.ReviewedAt, &app.RejectionReason, &app.CreatedAt, &app.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return app, nil
}

// ── User Trader Status ──

func (r *TraderRepo) SetUserTrader(ctx context.Context, uid string, isTrader bool) error {
	if isTrader {
		now := time.Now()
		_, err := r.pool.Exec(ctx, `
			UPDATE users SET is_trader = true, trader_approved_at = $2, updated_at = NOW() WHERE uid = $1
		`, uid, now)
		return err
	}
	_, err := r.pool.Exec(ctx, `
		UPDATE users SET is_trader = false, trader_approved_at = NULL, updated_at = NOW() WHERE uid = $1
	`, uid)
	return err
}

func (r *TraderRepo) UpdateAllowCopyTrading(ctx context.Context, uid string, allow bool) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE users SET allow_copy_trading = $2, updated_at = NOW() WHERE uid = $1
	`, uid, allow)
	return err
}

// ── Trader Stats ──

func (r *TraderRepo) GetTraderStats(ctx context.Context, uid string) (*model.TraderStats, error) {
	s := &model.TraderStats{UserID: uid}
	err := r.pool.QueryRow(ctx, `
		SELECT total_trades, win_trades, total_pnl, win_rate, avg_pnl, max_drawdown, followers_count, updated_at
		FROM trader_stats WHERE user_id = $1
	`, uid).Scan(
		&s.TotalTrades, &s.WinTrades, &s.TotalPnl, &s.WinRate, &s.AvgPnl,
		&s.MaxDrawdown, &s.FollowersCount, &s.UpdatedAt,
	)
	if err != nil {
		// Return empty stats if not found
		return &model.TraderStats{UserID: uid}, nil
	}
	return s, nil
}

func (r *TraderRepo) RefreshTraderStats(ctx context.Context, uid string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO trader_stats (user_id, total_trades, win_trades, total_pnl, win_rate, avg_pnl, max_drawdown, followers_count, updated_at)
		SELECT
			$1,
			COUNT(*),
			COUNT(*) FILTER (WHERE realized_pnl > 0),
			COALESCE(SUM(realized_pnl), 0),
			CASE WHEN COUNT(*) > 0
				THEN ROUND(COUNT(*) FILTER (WHERE realized_pnl > 0)::NUMERIC / COUNT(*)::NUMERIC * 100, 2)
				ELSE 0
			END,
			CASE WHEN COUNT(*) > 0
				THEN ROUND(COALESCE(SUM(realized_pnl), 0) / COUNT(*)::NUMERIC, 2)
				ELSE 0
			END,
			COALESCE((
				SELECT ROUND(MAX(drawdown_pct), 2) FROM (
					SELECT
						CASE WHEN peak > 0
							THEN (peak - running_pnl) / peak * 100
							ELSE 0
						END AS drawdown_pct
					FROM (
						SELECT
							running_pnl,
							MAX(running_pnl) OVER (ORDER BY closed_at ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS peak
						FROM (
							SELECT
								closed_at,
								SUM(realized_pnl) OVER (ORDER BY closed_at) AS running_pnl
							FROM positions
							WHERE user_id = $1 AND status IN ('closed', 'liquidated')
						) cumulative
					) with_peak
					WHERE running_pnl < peak
				) dd
			), 0),
			(SELECT COUNT(*) FROM copy_trading WHERE trader_id = $1 AND status = 'active'),
			NOW()
		FROM positions
		WHERE user_id = $1 AND status IN ('closed', 'liquidated')
		ON CONFLICT (user_id) DO UPDATE SET
			total_trades = EXCLUDED.total_trades,
			win_trades = EXCLUDED.win_trades,
			total_pnl = EXCLUDED.total_pnl,
			win_rate = EXCLUDED.win_rate,
			avg_pnl = EXCLUDED.avg_pnl,
			max_drawdown = EXCLUDED.max_drawdown,
			followers_count = EXCLUDED.followers_count,
			updated_at = NOW()
	`, uid)
	return err
}

func (r *TraderRepo) ListTraderRankings(ctx context.Context, sortBy string, limit, offset int) ([]model.TraderRankingItem, int, error) {
	var total int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM users WHERE is_trader = true
	`).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	orderClause := "ts.total_pnl DESC"
	switch sortBy {
	case "win_rate":
		orderClause = "ts.win_rate DESC"
	case "followers":
		orderClause = "ts.followers_count DESC"
	case "trades":
		orderClause = "ts.total_trades DESC"
	}

	rows, err := r.pool.Query(ctx, fmt.Sprintf(`
		SELECT u.uid, u.display_name, COALESCE(u.avatar_url,''),
			COALESCE(ts.total_trades, 0), COALESCE(ts.win_rate, 0),
			COALESCE(ts.total_pnl, 0), COALESCE(ts.avg_pnl, 0),
			COALESCE(ts.max_drawdown, 0), COALESCE(ts.followers_count, 0),
			COALESCE(u.allow_copy_trading, false)
		FROM users u
		LEFT JOIN trader_stats ts ON ts.user_id = u.uid
		WHERE u.is_trader = true
		ORDER BY %s
		LIMIT $1 OFFSET $2
	`, orderClause), limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []model.TraderRankingItem
	for rows.Next() {
		var item model.TraderRankingItem
		if err := rows.Scan(
			&item.UID, &item.DisplayName, &item.AvatarURL,
			&item.TotalTrades, &item.WinRate, &item.TotalPnl, &item.AvgPnl,
			&item.MaxDrawdown, &item.FollowersCount, &item.AllowCopyTrading,
		); err != nil {
			return nil, 0, err
		}
		items = append(items, item)
	}
	return items, total, nil
}

// ── Copy Trading ──

func (r *TraderRepo) CreateCopyTrading(ctx context.Context, followerID, traderID string, req *model.FollowTraderRequest) (*model.CopyTrading, error) {
	ct := &model.CopyTrading{}
	copyMode := req.CopyMode
	if copyMode == "" {
		copyMode = "fixed"
	}
	leverageMode := req.LeverageMode
	if leverageMode == "" {
		leverageMode = "trader"
	}
	tpSlMode := req.TpSlMode
	if tpSlMode == "" {
		tpSlMode = "trader"
	}
	followDir := req.FollowDirection
	if followDir == "" {
		followDir = "both"
	}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO copy_trading (follower_id, trader_id, copy_mode, copy_ratio, fixed_amount,
			max_position, max_single_margin, follow_symbols, leverage_mode, custom_leverage,
			tp_sl_mode, custom_tp_ratio, custom_sl_ratio, follow_direction,
			allocated_capital, available_capital, frozen_capital)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $15, 0)
		ON CONFLICT (follower_id, trader_id) DO UPDATE SET
			status = 'active', copy_mode = $3, copy_ratio = $4, fixed_amount = $5,
			max_position = $6, max_single_margin = $7, follow_symbols = $8,
			leverage_mode = $9, custom_leverage = $10, tp_sl_mode = $11,
			custom_tp_ratio = $12, custom_sl_ratio = $13, follow_direction = $14,
			allocated_capital = copy_trading.allocated_capital + $15,
			available_capital = copy_trading.available_capital + $15,
			updated_at = NOW()
		RETURNING id, follower_id, trader_id, status, copy_mode, copy_ratio, fixed_amount,
			max_position, max_single_margin, follow_symbols, leverage_mode, custom_leverage,
			tp_sl_mode, custom_tp_ratio, custom_sl_ratio, follow_direction,
			allocated_capital, available_capital, frozen_capital,
			created_at, updated_at
	`, followerID, traderID, copyMode, req.CopyRatio, req.FixedAmount,
		req.MaxPosition, req.MaxSingleMargin, req.FollowSymbols,
		leverageMode, req.CustomLeverage, tpSlMode,
		req.CustomTpRatio, req.CustomSlRatio, followDir,
		req.AllocatedCapital).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status,
		&ct.CopyMode, &ct.CopyRatio, &ct.FixedAmount,
		&ct.MaxPosition, &ct.MaxSingleMargin, &ct.FollowSymbols,
		&ct.LeverageMode, &ct.CustomLeverage, &ct.TpSlMode,
		&ct.CustomTpRatio, &ct.CustomSlRatio, &ct.FollowDirection,
		&ct.AllocatedCapital, &ct.AvailableCapital, &ct.FrozenCapital,
		&ct.CreatedAt, &ct.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create copy trading: %w", err)
	}
	return ct, nil
}

func (r *TraderRepo) StopCopyTrading(ctx context.Context, followerID, traderID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE copy_trading SET status = 'stopped', updated_at = NOW()
		WHERE follower_id = $1 AND trader_id = $2
	`, followerID, traderID)
	return err
}

func (r *TraderRepo) GetCopyRelation(ctx context.Context, followerID, traderID string) (*model.CopyTrading, error) {
	ct := &model.CopyTrading{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, follower_id, trader_id, status, copy_mode, copy_ratio, fixed_amount,
			max_position, max_single_margin, follow_symbols, leverage_mode, custom_leverage,
			tp_sl_mode, custom_tp_ratio, custom_sl_ratio, follow_direction,
			allocated_capital, available_capital, frozen_capital,
			created_at, updated_at
		FROM copy_trading
		WHERE follower_id = $1 AND trader_id = $2
	`, followerID, traderID).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status,
		&ct.CopyMode, &ct.CopyRatio, &ct.FixedAmount,
		&ct.MaxPosition, &ct.MaxSingleMargin, &ct.FollowSymbols,
		&ct.LeverageMode, &ct.CustomLeverage, &ct.TpSlMode,
		&ct.CustomTpRatio, &ct.CustomSlRatio, &ct.FollowDirection,
		&ct.AllocatedCapital, &ct.AvailableCapital, &ct.FrozenCapital,
		&ct.CreatedAt, &ct.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return ct, nil
}

func (r *TraderRepo) ListFollowers(ctx context.Context, traderID string) ([]model.CopyTrading, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT ct.id, ct.follower_id, ct.trader_id, ct.status,
			ct.copy_mode, ct.copy_ratio, ct.fixed_amount, ct.max_position, ct.max_single_margin,
			ct.follow_symbols, ct.leverage_mode, ct.custom_leverage,
			ct.tp_sl_mode, ct.custom_tp_ratio, ct.custom_sl_ratio, ct.follow_direction,
			ct.allocated_capital, ct.available_capital, ct.frozen_capital,
			ct.created_at, ct.updated_at, COALESCE(u.display_name,''), COALESCE(u.avatar_url,'')
		FROM copy_trading ct
		JOIN users u ON u.uid = ct.follower_id
		WHERE ct.trader_id = $1 AND ct.status IN ('active','paused')
		ORDER BY ct.created_at DESC
	`, traderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCopyTradingRows(rows)
}

func (r *TraderRepo) ListFollowing(ctx context.Context, followerID string) ([]model.CopyTrading, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT ct.id, ct.follower_id, ct.trader_id, ct.status,
			ct.copy_mode, ct.copy_ratio, ct.fixed_amount, ct.max_position, ct.max_single_margin,
			ct.follow_symbols, ct.leverage_mode, ct.custom_leverage,
			ct.tp_sl_mode, ct.custom_tp_ratio, ct.custom_sl_ratio, ct.follow_direction,
			ct.allocated_capital, ct.available_capital, ct.frozen_capital,
			ct.created_at, ct.updated_at, COALESCE(u.display_name,''), COALESCE(u.avatar_url,'')
		FROM copy_trading ct
		JOIN users u ON u.uid = ct.trader_id
		WHERE ct.follower_id = $1 AND ct.status != 'stopped'
		ORDER BY ct.created_at DESC
	`, followerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCopyTradingRows(rows)
}

// ── Copy Trading: New Methods ──

func scanCopyTradingRows(rows interface {
	Next() bool
	Scan(dest ...any) error
}) ([]model.CopyTrading, error) {
	var list []model.CopyTrading
	for rows.Next() {
		var ct model.CopyTrading
		if err := rows.Scan(
			&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status,
			&ct.CopyMode, &ct.CopyRatio, &ct.FixedAmount,
			&ct.MaxPosition, &ct.MaxSingleMargin, &ct.FollowSymbols,
			&ct.LeverageMode, &ct.CustomLeverage, &ct.TpSlMode,
			&ct.CustomTpRatio, &ct.CustomSlRatio, &ct.FollowDirection,
			&ct.AllocatedCapital, &ct.AvailableCapital, &ct.FrozenCapital,
			&ct.CreatedAt, &ct.UpdatedAt, &ct.TraderName, &ct.TraderAvatar,
		); err != nil {
			return nil, err
		}
		list = append(list, ct)
	}
	return list, nil
}

func (r *TraderRepo) ListActiveFollowersByTraderID(ctx context.Context, traderID string) ([]model.CopyTrading, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT ct.id, ct.follower_id, ct.trader_id, ct.status,
			ct.copy_mode, ct.copy_ratio, ct.fixed_amount, ct.max_position, ct.max_single_margin,
			ct.follow_symbols, ct.leverage_mode, ct.custom_leverage,
			ct.tp_sl_mode, ct.custom_tp_ratio, ct.custom_sl_ratio, ct.follow_direction,
			ct.allocated_capital, ct.available_capital, ct.frozen_capital,
			ct.created_at, ct.updated_at, COALESCE(u.display_name,''), COALESCE(u.avatar_url,'')
		FROM copy_trading ct
		JOIN users u ON u.uid = ct.follower_id
		WHERE ct.trader_id = $1 AND ct.status = 'active'
	`, traderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanCopyTradingRows(rows)
}

func (r *TraderRepo) UpdateCopyTradingSettings(ctx context.Context, followerID, traderID string, req *model.FollowTraderRequest) (*model.CopyTrading, error) {
	ct := &model.CopyTrading{}
	copyMode := req.CopyMode
	if copyMode == "" {
		copyMode = "fixed"
	}
	leverageMode := req.LeverageMode
	if leverageMode == "" {
		leverageMode = "trader"
	}
	tpSlMode := req.TpSlMode
	if tpSlMode == "" {
		tpSlMode = "trader"
	}
	followDir := req.FollowDirection
	if followDir == "" {
		followDir = "both"
	}
	err := r.pool.QueryRow(ctx, `
		UPDATE copy_trading SET
			copy_mode = $3, copy_ratio = $4, fixed_amount = $5,
			max_position = $6, max_single_margin = $7, follow_symbols = $8,
			leverage_mode = $9, custom_leverage = $10, tp_sl_mode = $11,
			custom_tp_ratio = $12, custom_sl_ratio = $13, follow_direction = $14,
			updated_at = NOW()
		WHERE follower_id = $1 AND trader_id = $2 AND status != 'stopped'
		RETURNING id, follower_id, trader_id, status, copy_mode, copy_ratio, fixed_amount,
			max_position, max_single_margin, follow_symbols, leverage_mode, custom_leverage,
			tp_sl_mode, custom_tp_ratio, custom_sl_ratio, follow_direction,
			allocated_capital, available_capital, frozen_capital,
			created_at, updated_at
	`, followerID, traderID, copyMode, req.CopyRatio, req.FixedAmount,
		req.MaxPosition, req.MaxSingleMargin, req.FollowSymbols,
		leverageMode, req.CustomLeverage, tpSlMode,
		req.CustomTpRatio, req.CustomSlRatio, followDir).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status,
		&ct.CopyMode, &ct.CopyRatio, &ct.FixedAmount,
		&ct.MaxPosition, &ct.MaxSingleMargin, &ct.FollowSymbols,
		&ct.LeverageMode, &ct.CustomLeverage, &ct.TpSlMode,
		&ct.CustomTpRatio, &ct.CustomSlRatio, &ct.FollowDirection,
		&ct.AllocatedCapital, &ct.AvailableCapital, &ct.FrozenCapital,
		&ct.CreatedAt, &ct.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("update copy trading settings: %w", err)
	}
	return ct, nil
}

func (r *TraderRepo) PauseCopyTrading(ctx context.Context, followerID, traderID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE copy_trading SET status = 'paused', updated_at = NOW()
		WHERE follower_id = $1 AND trader_id = $2 AND status = 'active'
	`, followerID, traderID)
	return err
}

func (r *TraderRepo) ResumeCopyTrading(ctx context.Context, followerID, traderID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE copy_trading SET status = 'active', updated_at = NOW()
		WHERE follower_id = $1 AND trader_id = $2 AND status = 'paused'
	`, followerID, traderID)
	return err
}

func (r *TraderRepo) GetTotalCopyMarginByTrader(ctx context.Context, followerID, traderID string) (float64, error) {
	var total float64
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(margin_amount), 0) FROM positions
		WHERE user_id = $1 AND source_trader_id = $2 AND is_copy_trade = true AND status = 'open'
	`, followerID, traderID).Scan(&total)
	return total, err
}

// ── Copy Trading: Allocated Capital (虚拟子账户) ──

// FreezeFromBucket 跟单开仓时，从子账户 available 扣保证金，转入 frozen。
// 受影响行 = 0 表示余额不足或 ID 不存在，应在调用方报错并跳过。
func (r *TraderRepo) FreezeFromBucket(ctx context.Context, copyTradingID string, amount float64) error {
	if amount <= 0 {
		return fmt.Errorf("freeze amount must be positive: %v", amount)
	}
	tag, err := r.pool.Exec(ctx, `
		UPDATE copy_trading
		SET available_capital = available_capital - $2,
		    frozen_capital    = frozen_capital + $2,
		    updated_at = NOW()
		WHERE id = $1 AND status = 'active' AND available_capital >= $2
	`, copyTradingID, amount)
	if err != nil {
		return fmt.Errorf("freeze from bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("insufficient bucket capital or copy_trading not active: %s", copyTradingID)
	}
	return nil
}

// SettleToBucket 跟单平仓结算：释放冻结保证金 + 入账 PnL - 扣手续费。
// releasedMargin 必须 > 0；pnl 可正可负；fee 必须 >= 0。
// available 一定不会被本函数推到负值（约束保证），若 frozen 不足以释放则报错。
func (r *TraderRepo) SettleToBucket(ctx context.Context, copyTradingID string, releasedMargin, pnl, fee float64) error {
	if releasedMargin < 0 {
		return fmt.Errorf("releasedMargin must be >= 0: %v", releasedMargin)
	}
	if fee < 0 {
		return fmt.Errorf("fee must be >= 0: %v", fee)
	}
	// available += releasedMargin + pnl - fee；frozen -= releasedMargin
	// 若 pnl 大幅亏损导致 available 变负 → 触发 chk_copy_trading_capital_nonneg 约束 → 报错
	tag, err := r.pool.Exec(ctx, `
		UPDATE copy_trading
		SET frozen_capital    = frozen_capital - $2,
		    available_capital = available_capital + $2 + $3 - $4,
		    updated_at = NOW()
		WHERE id = $1 AND frozen_capital >= $2
	`, copyTradingID, releasedMargin, pnl, fee)
	if err != nil {
		return fmt.Errorf("settle to bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("insufficient frozen capital or copy_trading not found: %s", copyTradingID)
	}
	return nil
}

// AdjustAllocatedCapital 用户主动追加 / 赎回本金。delta>0 追加，<0 赎回。
// 调用方负责钱包侧（balance ± |delta|）和 wallet_transactions 流水的写入；
// 此方法只动子账户 allocated/available。
func (r *TraderRepo) AdjustAllocatedCapital(ctx context.Context, copyTradingID string, delta float64) error {
	if delta == 0 {
		return nil
	}
	if delta > 0 {
		// 追加：available + allocated 同时 += delta
		tag, err := r.pool.Exec(ctx, `
			UPDATE copy_trading
			SET allocated_capital = allocated_capital + $2,
			    available_capital = available_capital + $2,
			    updated_at = NOW()
			WHERE id = $1 AND status = 'active'
		`, copyTradingID, delta)
		if err != nil {
			return fmt.Errorf("top up bucket: %w", err)
		}
		if tag.RowsAffected() == 0 {
			return fmt.Errorf("copy_trading not active: %s", copyTradingID)
		}
		return nil
	}
	// 赎回：|delta| 必须 ≤ available；allocated 同步减
	withdraw := -delta
	tag, err := r.pool.Exec(ctx, `
		UPDATE copy_trading
		SET allocated_capital = allocated_capital - $2,
		    available_capital = available_capital - $2,
		    updated_at = NOW()
		WHERE id = $1 AND status = 'active' AND available_capital >= $2 AND allocated_capital >= $2
	`, copyTradingID, withdraw)
	if err != nil {
		return fmt.Errorf("withdraw from bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("withdraw exceeds bucket available or allocated: %s", copyTradingID)
	}
	return nil
}

// GetCopyTradingByID 按 ID 取（service 层取最新池子余额给前端用）。
func (r *TraderRepo) GetCopyTradingByID(ctx context.Context, id string) (*model.CopyTrading, error) {
	ct := &model.CopyTrading{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, follower_id, trader_id, status, copy_mode, copy_ratio, fixed_amount,
			max_position, max_single_margin, follow_symbols, leverage_mode, custom_leverage,
			tp_sl_mode, custom_tp_ratio, custom_sl_ratio, follow_direction,
			allocated_capital, available_capital, frozen_capital,
			created_at, updated_at
		FROM copy_trading WHERE id = $1
	`, id).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status,
		&ct.CopyMode, &ct.CopyRatio, &ct.FixedAmount,
		&ct.MaxPosition, &ct.MaxSingleMargin, &ct.FollowSymbols,
		&ct.LeverageMode, &ct.CustomLeverage, &ct.TpSlMode,
		&ct.CustomTpRatio, &ct.CustomSlRatio, &ct.FollowDirection,
		&ct.AllocatedCapital, &ct.AvailableCapital, &ct.FrozenCapital,
		&ct.CreatedAt, &ct.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return ct, nil
}

// ── Copy Trade Logs ──

func (r *TraderRepo) CreateCopyTradeLog(ctx context.Context, log *model.CopyTradeLog) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO copy_trade_logs (copy_trading_id, follower_id, trader_id, action,
			source_order_id, source_position_id, follower_order_id, follower_position_id,
			symbol, side, trader_qty, follower_qty, trader_margin, follower_margin,
			follower_leverage, realized_pnl, skip_reason)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
	`, log.CopyTradingID, log.FollowerID, log.TraderID, log.Action,
		log.SourceOrderID, log.SourcePositionID, log.FollowerOrderID, log.FollowerPositionID,
		log.Symbol, log.Side, log.TraderQty, log.FollowerQty, log.TraderMargin, log.FollowerMargin,
		log.FollowerLeverage, log.RealizedPnl, log.SkipReason)
	return err
}

func (r *TraderRepo) ListCopyTradeLogsByFollower(ctx context.Context, followerID string, limit, offset int) ([]model.CopyTradeLog, int, error) {
	var total int
	_ = r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM copy_trade_logs WHERE follower_id = $1`, followerID).Scan(&total)

	rows, err := r.pool.Query(ctx, `
		SELECT l.id, l.copy_trading_id, l.follower_id, l.trader_id, l.action,
			l.source_order_id, l.source_position_id, l.follower_order_id, l.follower_position_id,
			l.symbol, l.side, l.trader_qty, l.follower_qty, l.trader_margin, l.follower_margin,
			l.follower_leverage, COALESCE(l.realized_pnl, 0), COALESCE(l.skip_reason, ''),
			l.created_at, COALESCE(u.display_name,''), COALESCE(u.avatar_url,'')
		FROM copy_trade_logs l
		JOIN users u ON u.uid = l.trader_id
		WHERE l.follower_id = $1
		ORDER BY l.created_at DESC LIMIT $2 OFFSET $3
	`, followerID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var logs []model.CopyTradeLog
	for rows.Next() {
		var l model.CopyTradeLog
		if err := rows.Scan(
			&l.ID, &l.CopyTradingID, &l.FollowerID, &l.TraderID, &l.Action,
			&l.SourceOrderID, &l.SourcePositionID, &l.FollowerOrderID, &l.FollowerPositionID,
			&l.Symbol, &l.Side, &l.TraderQty, &l.FollowerQty, &l.TraderMargin, &l.FollowerMargin,
			&l.FollowerLeverage, &l.RealizedPnl, &l.SkipReason,
			&l.CreatedAt, &l.TraderName, &l.TraderAvatar,
		); err != nil {
			return nil, 0, err
		}
		logs = append(logs, l)
	}
	return logs, total, nil
}

// ── Trader Profile ──

func (r *TraderRepo) GetTraderProfile(ctx context.Context, uid string, viewerID string) (*model.TraderProfile, error) {
	p := &model.TraderProfile{}
	err := r.pool.QueryRow(ctx, `
		SELECT uid, display_name, COALESCE(avatar_url,''), COALESCE(is_trader, false), COALESCE(allow_copy_trading, false)
		FROM users WHERE uid = $1
	`, uid).Scan(&p.UID, &p.DisplayName, &p.AvatarURL, &p.IsTrader, &p.AllowCopyTrading)
	if err != nil {
		return nil, err
	}
	stats, _ := r.GetTraderStats(ctx, uid)
	p.Stats = stats
	if viewerID != "" {
		p.IsFollowed, _ = r.IsFollowing(ctx, viewerID, uid)
	}
	return p, nil
}

// ── User Follows ──

func (r *TraderRepo) FollowUser(ctx context.Context, userID, traderID string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO user_follows (user_id, trader_id) VALUES ($1, $2)
		ON CONFLICT (user_id, trader_id) DO NOTHING
	`, userID, traderID)
	return err
}

func (r *TraderRepo) UnfollowUser(ctx context.Context, userID, traderID string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM user_follows WHERE user_id = $1 AND trader_id = $2
	`, userID, traderID)
	return err
}

func (r *TraderRepo) IsFollowing(ctx context.Context, userID, traderID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM user_follows WHERE user_id = $1 AND trader_id = $2)
	`, userID, traderID).Scan(&exists)
	return exists, err
}

func (r *TraderRepo) ListFollowedTraders(ctx context.Context, userID string) ([]model.FollowedTrader, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT u.uid, u.display_name, COALESCE(u.avatar_url,''),
			COALESCE(u.is_trader, false), COALESCE(u.allow_copy_trading, false),
			uf.created_at,
			COALESCE(ts.total_trades, 0), COALESCE(ts.win_trades, 0),
			COALESCE(ts.total_pnl, 0), COALESCE(ts.win_rate, 0),
			COALESCE(ts.avg_pnl, 0), COALESCE(ts.max_drawdown, 0),
			COALESCE(ts.followers_count, 0),
			COALESCE(ct.status, ''),
			CASE WHEN ct.id IS NOT NULL AND ct.status IN ('active','paused') THEN true ELSE false END
		FROM user_follows uf
		JOIN users u ON u.uid = uf.trader_id
		LEFT JOIN trader_stats ts ON ts.user_id = uf.trader_id
		LEFT JOIN copy_trading ct ON ct.follower_id = uf.user_id AND ct.trader_id = uf.trader_id AND ct.status IN ('active','paused')
		WHERE uf.user_id = $1
		ORDER BY uf.created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []model.FollowedTrader
	for rows.Next() {
		var ft model.FollowedTrader
		var stats model.TraderStats
		err := rows.Scan(
			&ft.UID, &ft.DisplayName, &ft.AvatarURL,
			&ft.IsTrader, &ft.AllowCopyTrading,
			&ft.FollowedAt,
			&stats.TotalTrades, &stats.WinTrades,
			&stats.TotalPnl, &stats.WinRate,
			&stats.AvgPnl, &stats.MaxDrawdown,
			&stats.FollowersCount,
			&ft.CopyStatus,
			&ft.IsCopying,
		)
		if err != nil {
			return nil, err
		}
		stats.UserID = ft.UID
		ft.Stats = &stats
		list = append(list, ft)
	}
	return list, nil
}

func (r *TraderRepo) CountFollowers(ctx context.Context, traderID string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM user_follows WHERE trader_id = $1
	`, traderID).Scan(&count)
	return count, err
}

// GetEquityHistory returns daily cumulative PNL points for a trader's equity curve.
// period: "7d", "30d", or "all"
func (r *TraderRepo) GetEquityHistory(ctx context.Context, uid string, period string) ([]model.EquityPoint, error) {
	dateFilter := ""
	switch period {
	case "7d":
		dateFilter = " AND closed_at >= NOW() - INTERVAL '7 days'"
	case "30d":
		dateFilter = " AND closed_at >= NOW() - INTERVAL '30 days'"
	}

	query := `
		SELECT
			dt::TEXT AS date,
			COALESCE(daily_pnl, 0) AS daily_pnl,
			COALESCE(SUM(daily_pnl) OVER (ORDER BY dt), 0) AS cumulative_pnl
		FROM (
			SELECT
				DATE(closed_at) AS dt,
				SUM(realized_pnl) AS daily_pnl
			FROM positions
			WHERE user_id = $1 AND status IN ('closed', 'liquidated')` + dateFilter + `
			GROUP BY DATE(closed_at)
			ORDER BY dt
		) daily
		ORDER BY dt
	`

	rows, err := r.pool.Query(ctx, query, uid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var points []model.EquityPoint
	for rows.Next() {
		var p model.EquityPoint
		if err := rows.Scan(&p.Date, &p.DailyPnl, &p.CumulativePnl); err != nil {
			return nil, err
		}
		points = append(points, p)
	}
	return points, nil
}
