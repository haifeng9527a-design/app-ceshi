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
			0,
			(SELECT COUNT(*) FROM copy_trading WHERE trader_id = $1 AND status = 'active'),
			NOW()
		FROM positions
		WHERE user_id = $1 AND status = 'closed'
		ON CONFLICT (user_id) DO UPDATE SET
			total_trades = EXCLUDED.total_trades,
			win_trades = EXCLUDED.win_trades,
			total_pnl = EXCLUDED.total_pnl,
			win_rate = EXCLUDED.win_rate,
			avg_pnl = EXCLUDED.avg_pnl,
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

func (r *TraderRepo) CreateCopyTrading(ctx context.Context, followerID, traderID string, ratio float64, maxPos *float64) (*model.CopyTrading, error) {
	ct := &model.CopyTrading{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO copy_trading (follower_id, trader_id, copy_ratio, max_position)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (follower_id, trader_id) DO UPDATE SET
			status = 'active', copy_ratio = $3, max_position = $4, updated_at = NOW()
		RETURNING id, follower_id, trader_id, status, copy_ratio, max_position, created_at, updated_at
	`, followerID, traderID, ratio, maxPos).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status, &ct.CopyRatio,
		&ct.MaxPosition, &ct.CreatedAt, &ct.UpdatedAt,
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
		SELECT id, follower_id, trader_id, status, copy_ratio, max_position, created_at, updated_at
		FROM copy_trading
		WHERE follower_id = $1 AND trader_id = $2
	`, followerID, traderID).Scan(
		&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status, &ct.CopyRatio,
		&ct.MaxPosition, &ct.CreatedAt, &ct.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return ct, nil
}

func (r *TraderRepo) ListFollowers(ctx context.Context, traderID string) ([]model.CopyTrading, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT ct.id, ct.follower_id, ct.trader_id, ct.status, ct.copy_ratio, ct.max_position,
			ct.created_at, ct.updated_at, COALESCE(u.display_name,''), COALESCE(u.avatar_url,'')
		FROM copy_trading ct
		JOIN users u ON u.uid = ct.follower_id
		WHERE ct.trader_id = $1 AND ct.status = 'active'
		ORDER BY ct.created_at DESC
	`, traderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []model.CopyTrading
	for rows.Next() {
		var ct model.CopyTrading
		if err := rows.Scan(
			&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status, &ct.CopyRatio,
			&ct.MaxPosition, &ct.CreatedAt, &ct.UpdatedAt, &ct.TraderName, &ct.TraderAvatar,
		); err != nil {
			return nil, err
		}
		list = append(list, ct)
	}
	return list, nil
}

func (r *TraderRepo) ListFollowing(ctx context.Context, followerID string) ([]model.CopyTrading, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT ct.id, ct.follower_id, ct.trader_id, ct.status, ct.copy_ratio, ct.max_position,
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

	var list []model.CopyTrading
	for rows.Next() {
		var ct model.CopyTrading
		if err := rows.Scan(
			&ct.ID, &ct.FollowerID, &ct.TraderID, &ct.Status, &ct.CopyRatio,
			&ct.MaxPosition, &ct.CreatedAt, &ct.UpdatedAt, &ct.TraderName, &ct.TraderAvatar,
		); err != nil {
			return nil, err
		}
		list = append(list, ct)
	}
	return list, nil
}

// ── Trader Profile ──

func (r *TraderRepo) GetTraderProfile(ctx context.Context, uid string) (*model.TraderProfile, error) {
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
	return p, nil
}
