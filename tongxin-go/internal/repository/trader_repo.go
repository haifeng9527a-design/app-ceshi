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
			COALESCE(u.allow_copy_trading, false),
			COALESCE(u.default_profit_share_rate, 0)
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
			&item.DefaultProfitShareRate,
		); err != nil {
			return nil, 0, err
		}
		items = append(items, item)
	}
	return items, total, nil
}

// ── Copy Trading ──

// CreateCopyTrading 创建 / 复活 copy_trading 行。
// snapshotShareRate 在 INSERT 时直接写入 profit_share_rate 列；
// ON CONFLICT (复活) 时**不**覆盖原行的 profit_share_rate（保护存量 follower 的 snapshot）。
// 调用方传 0 表示禁用分润（feature flag off 或 trader 没设默认比例）。
func (r *TraderRepo) CreateCopyTrading(ctx context.Context, followerID, traderID string, req *model.FollowTraderRequest, snapshotShareRate float64) (*model.CopyTrading, error) {
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
	// 防御性夹紧（service 层应已校验，repo 再夹一次保护数据库 CHECK 约束）
	if snapshotShareRate < 0 {
		snapshotShareRate = 0
	}
	if snapshotShareRate > 0.2 {
		snapshotShareRate = 0.2
	}
	// 注意：本方法只创建 / 复活 copy_trading 行（纯配置 + status），
	// 不动 allocated_capital/available_capital/frozen_capital。
	// 资金划转必须通过 walletRepo.AllocateToCopyBucket 在独立事务里完成。
	err := r.pool.QueryRow(ctx, `
		INSERT INTO copy_trading (follower_id, trader_id, copy_mode, copy_ratio, fixed_amount,
			max_position, max_single_margin, follow_symbols, leverage_mode, custom_leverage,
			tp_sl_mode, custom_tp_ratio, custom_sl_ratio, follow_direction, profit_share_rate)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
		ON CONFLICT (follower_id, trader_id) DO UPDATE SET
			status = 'active', copy_mode = $3, copy_ratio = $4, fixed_amount = $5,
			max_position = $6, max_single_margin = $7, follow_symbols = $8,
			leverage_mode = $9, custom_leverage = $10, tp_sl_mode = $11,
			custom_tp_ratio = $12, custom_sl_ratio = $13, follow_direction = $14,
			updated_at = NOW()
		RETURNING id, follower_id, trader_id, status, copy_mode, copy_ratio, fixed_amount,
			max_position, max_single_margin, follow_symbols, leverage_mode, custom_leverage,
			tp_sl_mode, custom_tp_ratio, custom_sl_ratio, follow_direction,
			allocated_capital, available_capital, frozen_capital,
			profit_share_rate, high_water_mark, cumulative_net_deposit, cumulative_profit_shared,
			created_at, updated_at
	`, followerID, traderID, copyMode, req.CopyRatio, req.FixedAmount,
		req.MaxPosition, req.MaxSingleMargin, req.FollowSymbols,
		leverageMode, req.CustomLeverage, tpSlMode,
		req.CustomTpRatio, req.CustomSlRatio, followDir, snapshotShareRate).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status,
		&ct.CopyMode, &ct.CopyRatio, &ct.FixedAmount,
		&ct.MaxPosition, &ct.MaxSingleMargin, &ct.FollowSymbols,
		&ct.LeverageMode, &ct.CustomLeverage, &ct.TpSlMode,
		&ct.CustomTpRatio, &ct.CustomSlRatio, &ct.FollowDirection,
		&ct.AllocatedCapital, &ct.AvailableCapital, &ct.FrozenCapital,
		&ct.ProfitShareRate, &ct.HighWaterMark, &ct.CumulativeNetDeposit, &ct.CumulativeProfitShared,
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
			profit_share_rate, high_water_mark, cumulative_net_deposit, cumulative_profit_shared,
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
		&ct.ProfitShareRate, &ct.HighWaterMark, &ct.CumulativeNetDeposit, &ct.CumulativeProfitShared,
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
			ct.profit_share_rate, ct.high_water_mark, ct.cumulative_net_deposit, ct.cumulative_profit_shared,
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
			ct.profit_share_rate, ct.high_water_mark, ct.cumulative_net_deposit, ct.cumulative_profit_shared,
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
			&ct.ProfitShareRate, &ct.HighWaterMark, &ct.CumulativeNetDeposit, &ct.CumulativeProfitShared,
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
			ct.profit_share_rate, ct.high_water_mark, ct.cumulative_net_deposit, ct.cumulative_profit_shared,
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
			profit_share_rate, high_water_mark, cumulative_net_deposit, cumulative_profit_shared,
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
		&ct.ProfitShareRate, &ct.HighWaterMark, &ct.CumulativeNetDeposit, &ct.CumulativeProfitShared,
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

// FreezeFromBucket 跟单开仓时一次性扣 margin + openFee：
//   available -= (margin + fee)
//   frozen    += margin   （fee 是真实损耗，不进 frozen）
// 失败（available 不够 or 池子非 active）会返回错误，调用方应跳过这笔。
func (r *TraderRepo) FreezeFromBucket(ctx context.Context, copyTradingID string, margin, fee float64) error {
	if margin <= 0 {
		return fmt.Errorf("freeze margin must be positive: %v", margin)
	}
	if fee < 0 {
		return fmt.Errorf("fee must be >= 0: %v", fee)
	}
	// NOTE: `$2::numeric + $3::numeric` 是必要的显式类型转换。
	// pgx 绑定 float64 参数时不会固定 parameter 类型，若写成 `$2 + $3`，
	// PostgreSQL 在没有列上下文（比如 WHERE 里的 `>= $2 + $3`）的情况下
	// 会把两个参数都当 unknown，报 `operator is not unique: unknown + unknown
	// (SQLSTATE 42725)`。SET 子句里虽然 `available_capital - $2 - $3` 能借
	// 列类型推断，但为了统一和防御，一律加 ::numeric。
	tag, err := r.pool.Exec(ctx, `
		UPDATE copy_trading
		SET available_capital = available_capital - $2::numeric - $3::numeric,
		    frozen_capital    = frozen_capital + $2::numeric,
		    updated_at = NOW()
		WHERE id = $1 AND status = 'active'
		  AND available_capital >= $2::numeric + $3::numeric
	`, copyTradingID, margin, fee)
	if err != nil {
		return fmt.Errorf("freeze from bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("insufficient bucket capital or copy_trading not active: %s", copyTradingID)
	}
	return nil
}

// UnfreezeBucket 撤销 FreezeFromBucket（当后续 createOrder/createPosition 失败时使用）。
//   frozen    -= margin
//   available += (margin + fee)   （fee 也退回，因为整笔回滚）
func (r *TraderRepo) UnfreezeBucket(ctx context.Context, copyTradingID string, margin, fee float64) error {
	if margin <= 0 {
		return nil
	}
	// 见 FreezeFromBucket 的说明：$2 / $3 必须加 ::numeric 显式类型，
	// 否则 `$2 + $3` 在无列上下文时会被 pgx 当 unknown 类型报错。
	tag, err := r.pool.Exec(ctx, `
		UPDATE copy_trading
		SET frozen_capital    = frozen_capital - $2::numeric,
		    available_capital = available_capital + $2::numeric + $3::numeric,
		    updated_at = NOW()
		WHERE id = $1 AND frozen_capital >= $2::numeric
	`, copyTradingID, margin, fee)
	if err != nil {
		return fmt.Errorf("unfreeze bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("frozen insufficient or copy_trading not found: %s", copyTradingID)
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
//
// 分润 HWM 同步（migration 027 引入）：
//   追加 +delta：cumulative_net_deposit += delta；high_water_mark += delta
//                （新注入的资金不算"赚的"，HWM 同步抬高才能正确判定后续创新高）
//   赎回 -|delta|：cumulative_net_deposit -= |delta|（GREATEST 钳到 0）；
//                  high_water_mark -= |delta|（GREATEST 钳到 0）
func (r *TraderRepo) AdjustAllocatedCapital(ctx context.Context, copyTradingID string, delta float64) error {
	if delta == 0 {
		return nil
	}
	if delta > 0 {
		// 追加：available + allocated + cumulative_net_deposit + high_water_mark 同时 += delta
		tag, err := r.pool.Exec(ctx, `
			UPDATE copy_trading
			SET allocated_capital       = allocated_capital + $2,
			    available_capital       = available_capital + $2,
			    cumulative_net_deposit  = cumulative_net_deposit + $2,
			    high_water_mark         = high_water_mark + $2,
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
	// 赎回：|delta| 上限 = available（含已实现盈亏，允许把盈利提走）。
	// allocated / cumulative_net_deposit / high_water_mark 同步减，
	// 用 GREATEST 钳到 0 —— 保持 chk_capital_nonneg 与 chk_copy_trading_profit_share 约束。
	withdraw := -delta
	tag, err := r.pool.Exec(ctx, `
		UPDATE copy_trading
		SET allocated_capital       = GREATEST(0, allocated_capital - $2),
		    available_capital       = available_capital - $2,
		    cumulative_net_deposit  = GREATEST(0, cumulative_net_deposit - $2),
		    high_water_mark         = GREATEST(0, high_water_mark - $2),
		    updated_at = NOW()
		WHERE id = $1 AND status = 'active' AND available_capital >= $2
	`, copyTradingID, withdraw)
	if err != nil {
		return fmt.Errorf("withdraw from bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("withdraw exceeds bucket available: %s", copyTradingID)
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
			profit_share_rate, high_water_mark, cumulative_net_deposit, cumulative_profit_shared,
			created_at, updated_at
		FROM copy_trading WHERE id = $1
	`, id).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status,
		&ct.CopyMode, &ct.CopyRatio, &ct.FixedAmount,
		&ct.MaxPosition, &ct.MaxSingleMargin, &ct.FollowSymbols,
		&ct.LeverageMode, &ct.CustomLeverage, &ct.TpSlMode,
		&ct.CustomTpRatio, &ct.CustomSlRatio, &ct.FollowDirection,
		&ct.AllocatedCapital, &ct.AvailableCapital, &ct.FrozenCapital,
		&ct.ProfitShareRate, &ct.HighWaterMark, &ct.CumulativeNetDeposit, &ct.CumulativeProfitShared,
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
		SELECT uid, display_name, COALESCE(avatar_url,''), COALESCE(is_trader, false), COALESCE(allow_copy_trading, false),
			COALESCE(default_profit_share_rate, 0)
		FROM users WHERE uid = $1
	`, uid).Scan(&p.UID, &p.DisplayName, &p.AvatarURL, &p.IsTrader, &p.AllowCopyTrading, &p.DefaultProfitShareRate)
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

// ═══════════════════════════════════════════════════════════
// Profit Share (跟单分润) — 详见 migrations/027
// ═══════════════════════════════════════════════════════════

// ProfitShareResult SettleToBucketWithCommission 的返回值，service 层用来组装 WS 事件。
type ProfitShareResult struct {
	Settled        bool    // true = 实际抽了分润；false = skipped
	ShareAmount    float64 // 抽走的分润额（>=0）
	HwmBefore      float64
	HwmAfter       float64
	EquityBefore   float64
	EquityAfter    float64
	RateApplied    float64
	NetPnl         float64
	Status         string // settled / skipped_below_hwm / skipped_loss / skipped_zero_rate
	BucketBalance  float64 // 结算后 follower 池子 available_capital
	NewLifetimeIn  float64 // 结算后 trader.lifetime_profit_shared_in（仅 settled 时有意义）
}

// SettleToBucketWithCommission 跟单平仓结算 + HWM 分润抽成（单事务）。
//
// 步骤（同一 DB 事务内原子完成，任一失败整体回滚）：
//  1. SELECT copy_trading FOR UPDATE，拿当前 available/frozen/hwm/rate/cumulative_profit_shared
//  2. 计算 equity_before = available + frozen
//     equity_after  = (available + releasedMargin + pnl - closeFee) + (frozen - releasedMargin)
//                   = equity_before + pnl - closeFee
//     net_pnl       = pnl - closeFee
//  3. 分润判定：
//       rate == 0                     → skipped_zero_rate
//       net_pnl <= 0                  → skipped_loss
//       equity_after <= hwm           → skipped_below_hwm
//       否则 chargeable = min(equity_after - hwm, net_pnl)
//            share     = chargeable * rate
//            hwm_after = equity_after - share
//  4. UPDATE copy_trading 一次写入：available, frozen, hwm, cumulative_profit_shared
//     （share=0 时 hwm 不动，cumulative_profit_shared 不动，仅做结算）
//  5. 若 share > 0：
//       UPDATE wallets SET balance += share WHERE user_id = trader
//       INSERT wallet_transactions(follower, copy_profit_share_out, -share)
//       INSERT wallet_transactions(trader,   copy_profit_share_in,  +share)
//       UPDATE users SET lifetime_profit_shared_in += share WHERE uid = trader
//  6. INSERT copy_profit_share_records（无论 settled / skipped 都记一条审计）
//
// 关键不变量：share <= net_pnl * rate <= net_pnl，所以扣完 available 仍非负，
// 不会触发 chk_copy_trading_capital_nonneg。
func (r *TraderRepo) SettleToBucketWithCommission(
	ctx context.Context,
	copyTradingID, traderUserID, positionID string,
	releasedMargin, pnl, closeFee float64,
) (*ProfitShareResult, error) {
	if releasedMargin < 0 {
		return nil, fmt.Errorf("releasedMargin must be >= 0: %v", releasedMargin)
	}
	if closeFee < 0 {
		return nil, fmt.Errorf("closeFee must be >= 0: %v", closeFee)
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("settle commission begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1. 锁行
	var (
		followerUserID         string
		availableBefore        float64
		frozenBefore           float64
		hwmBefore              float64
		rate                   float64
		cumulativeNetDeposit   float64
		cumulativeProfitShared float64
	)
	err = tx.QueryRow(ctx, `
		SELECT follower_id, available_capital, frozen_capital, high_water_mark,
		       profit_share_rate, cumulative_net_deposit, cumulative_profit_shared
		FROM copy_trading
		WHERE id = $1
		FOR UPDATE
	`, copyTradingID).Scan(
		&followerUserID, &availableBefore, &frozenBefore, &hwmBefore,
		&rate, &cumulativeNetDeposit, &cumulativeProfitShared,
	)
	if err != nil {
		return nil, fmt.Errorf("settle commission lock row: %w", err)
	}
	if frozenBefore < releasedMargin {
		return nil, fmt.Errorf("insufficient frozen capital: have %v, need %v", frozenBefore, releasedMargin)
	}

	// 2. 计算
	netPnl := pnl - closeFee
	equityBefore := availableBefore + frozenBefore
	availableAfterSettle := availableBefore + releasedMargin + pnl - closeFee
	frozenAfter := frozenBefore - releasedMargin
	equityAfter := availableAfterSettle + frozenAfter // == equityBefore + netPnl

	// 3. 分润判定
	var (
		share     float64
		status    string
		hwmAfter  = hwmBefore
	)
	switch {
	case rate <= 0:
		status = "skipped_zero_rate"
	case netPnl <= 0:
		status = "skipped_loss"
	case equityAfter <= hwmBefore:
		status = "skipped_below_hwm"
	default:
		chargeable := equityAfter - hwmBefore
		if chargeable > netPnl {
			chargeable = netPnl
		}
		share = chargeable * rate
		if share < 0 {
			share = 0 // 防御性：理论上不可能负
		}
		hwmAfter = equityAfter - share
		status = "settled"
	}

	availableAfterShare := availableAfterSettle - share

	// 4. UPDATE copy_trading
	_, err = tx.Exec(ctx, `
		UPDATE copy_trading
		SET available_capital        = $2,
		    frozen_capital           = $3,
		    high_water_mark          = $4,
		    cumulative_profit_shared = cumulative_profit_shared + $5,
		    updated_at = NOW()
		WHERE id = $1
	`, copyTradingID, availableAfterShare, frozenAfter, hwmAfter, share)
	if err != nil {
		return nil, fmt.Errorf("settle commission update copy_trading: %w", err)
	}

	var newLifetimeIn float64
	// 5. 若 share > 0 → 钱包 + 流水 + 累计
	if share > 0 {
		// follower 流水：amount<0、balance_after 用池子 available（不是钱包）
		_, err = tx.Exec(ctx, `
			INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
			VALUES ($1, 'copy_profit_share_out', $2, $3, $4, 'Profit share paid to trader')
		`, followerUserID, -share, availableAfterShare, copyTradingID)
		if err != nil {
			return nil, fmt.Errorf("settle commission record follower tx: %w", err)
		}

		// trader 钱包：balance += share
		var traderBalanceAfter float64
		err = tx.QueryRow(ctx, `
			INSERT INTO wallets (user_id, balance) VALUES ($1, $2)
			ON CONFLICT (user_id) DO UPDATE SET
				balance = wallets.balance + $2,
				updated_at = NOW()
			RETURNING balance
		`, traderUserID, share).Scan(&traderBalanceAfter)
		if err != nil {
			return nil, fmt.Errorf("settle commission credit trader wallet: %w", err)
		}

		// trader 流水：amount>0
		_, err = tx.Exec(ctx, `
			INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
			VALUES ($1, 'copy_profit_share_in', $2, $3, $4, 'Profit share received from follower')
		`, traderUserID, share, traderBalanceAfter, copyTradingID)
		if err != nil {
			return nil, fmt.Errorf("settle commission record trader tx: %w", err)
		}

		// trader 累计
		err = tx.QueryRow(ctx, `
			UPDATE users SET lifetime_profit_shared_in = lifetime_profit_shared_in + $2,
			                 updated_at = NOW()
			WHERE uid = $1
			RETURNING lifetime_profit_shared_in
		`, traderUserID, share).Scan(&newLifetimeIn)
		if err != nil {
			return nil, fmt.Errorf("settle commission update trader lifetime: %w", err)
		}
	}

	// 6. 审计（无论 settled/skipped）
	_, err = tx.Exec(ctx, `
		INSERT INTO copy_profit_share_records (
			copy_trading_id, follower_user_id, trader_user_id, position_id,
			gross_pnl, close_fee, net_pnl,
			equity_before, equity_after, hwm_before, hwm_after,
			rate_applied, share_amount, status
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
	`, copyTradingID, followerUserID, traderUserID, positionID,
		pnl, closeFee, netPnl,
		equityBefore, equityAfter, hwmBefore, hwmAfter,
		rate, share, status)
	if err != nil {
		return nil, fmt.Errorf("settle commission insert audit: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("settle commission commit: %w", err)
	}

	return &ProfitShareResult{
		Settled:       share > 0,
		ShareAmount:   share,
		HwmBefore:     hwmBefore,
		HwmAfter:      hwmAfter,
		EquityBefore:  equityBefore,
		EquityAfter:   equityAfter,
		RateApplied:   rate,
		NetPnl:        netPnl,
		Status:        status,
		BucketBalance: availableAfterShare,
		NewLifetimeIn: newLifetimeIn,
	}, nil
}

// UpdateDefaultShareRate 修改 trader 的默认分润比例。
// rate ∈ [0, 0.2]；不影响存量 follower 的 copy_trading.profit_share_rate（snapshot 锁定）。
func (r *TraderRepo) UpdateDefaultShareRate(ctx context.Context, traderUserID string, rate float64) error {
	if rate < 0 || rate > 0.2 {
		return fmt.Errorf("rate out of range [0, 0.2]: %v", rate)
	}
	tag, err := r.pool.Exec(ctx, `
		UPDATE users SET default_profit_share_rate = $2, updated_at = NOW()
		WHERE uid = $1 AND COALESCE(is_trader, false) = true
	`, traderUserID, rate)
	if err != nil {
		return fmt.Errorf("update default share rate: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("trader not found or not approved: %s", traderUserID)
	}
	return nil
}

// GetDefaultShareRate 读 trader 当前默认分润比例（snapshot 时用）。
// 不存在 / 非 trader 一律返回 0（绝不让分润误开启）。
func (r *TraderRepo) GetDefaultShareRate(ctx context.Context, traderUserID string) (float64, error) {
	var rate float64
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(default_profit_share_rate, 0)
		FROM users WHERE uid = $1 AND COALESCE(is_trader, false) = true
	`, traderUserID).Scan(&rate)
	if err != nil {
		return 0, nil // 安全回退：失败 → 0 比例
	}
	return rate, nil
}

// GetProfitShareSummary 交易员 dashboard 顶部三卡片 + 当前默认比例。
func (r *TraderRepo) GetProfitShareSummary(ctx context.Context, traderUserID string) (*model.ProfitShareSummary, error) {
	s := &model.ProfitShareSummary{}
	// lifetime + default_rate 直接从 users 读
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(lifetime_profit_shared_in, 0),
		       COALESCE(default_profit_share_rate, 0)
		FROM users WHERE uid = $1
	`, traderUserID).Scan(&s.Lifetime, &s.DefaultShareRate)
	if err != nil {
		return nil, fmt.Errorf("summary fetch user: %w", err)
	}
	// this_month: 从 audit 表实时聚合
	err = r.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(share_amount), 0)
		FROM copy_profit_share_records
		WHERE trader_user_id = $1
		  AND status = 'settled'
		  AND created_at >= DATE_TRUNC('month', NOW())
	`, traderUserID).Scan(&s.ThisMonth)
	if err != nil {
		return nil, fmt.Errorf("summary fetch this_month: %w", err)
	}
	// active_followers: 从 copy_trading 实时统计
	err = r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM copy_trading
		WHERE trader_id = $1 AND status = 'active'
	`, traderUserID).Scan(&s.ActiveFollowers)
	if err != nil {
		return nil, fmt.Errorf("summary fetch active_followers: %w", err)
	}
	return s, nil
}

// ListProfitShareRecords trader dashboard 明细列表（分页）。
// 只返回 status='settled' 的记录（前端不需要看 skip 项；如需可单独加 includeSkipped 开关）。
func (r *TraderRepo) ListProfitShareRecords(
	ctx context.Context,
	traderUserID string,
	limit, offset int,
) ([]model.ProfitShareRecord, int, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}

	var total int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM copy_profit_share_records
		WHERE trader_user_id = $1 AND status = 'settled'
	`, traderUserID).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count records: %w", err)
	}

	rows, err := r.pool.Query(ctx, `
		SELECT r.id, r.created_at, r.copy_trading_id, r.follower_user_id, r.trader_user_id, r.position_id,
		       r.gross_pnl, r.close_fee, r.net_pnl,
		       r.equity_before, r.equity_after, r.hwm_before, r.hwm_after,
		       r.rate_applied, r.share_amount, r.status,
		       COALESCE(u.display_name, ''),
		       COALESCE(p.symbol || ' ' || p.side, '')
		FROM copy_profit_share_records r
		LEFT JOIN users u ON u.uid = r.follower_user_id
		LEFT JOIN positions p ON p.id = r.position_id
		WHERE r.trader_user_id = $1 AND r.status = 'settled'
		ORDER BY r.created_at DESC
		LIMIT $2 OFFSET $3
	`, traderUserID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("list records: %w", err)
	}
	defer rows.Close()

	var out []model.ProfitShareRecord
	for rows.Next() {
		var rec model.ProfitShareRecord
		if err := rows.Scan(
			&rec.ID, &rec.CreatedAt, &rec.CopyTradingID, &rec.FollowerUserID, &rec.TraderUserID, &rec.PositionID,
			&rec.GrossPnl, &rec.CloseFee, &rec.NetPnl,
			&rec.EquityBefore, &rec.EquityAfter, &rec.HwmBefore, &rec.HwmAfter,
			&rec.RateApplied, &rec.ShareAmount, &rec.Status,
			&rec.FollowerName, &rec.PositionInfo,
		); err != nil {
			return nil, 0, fmt.Errorf("scan record: %w", err)
		}
		out = append(out, rec)
	}
	return out, total, nil
}
