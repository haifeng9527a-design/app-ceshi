package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type RevenueRepo struct {
	pool *pgxpool.Pool
}

func NewRevenueRepo(pool *pgxpool.Pool) *RevenueRepo {
	return &RevenueRepo{pool: pool}
}

// ListDaily returns daily revenue rows within a date range.
func (r *RevenueRepo) ListDaily(ctx context.Context, dateFrom, dateTo string) ([]model.DailyRevenue, error) {
	q := `SELECT date, fee_income, liquidation_income, total_income, trade_count, liquidation_count, active_users
		  FROM daily_revenue WHERE 1=1`
	args := []any{}
	idx := 1

	if dateFrom != "" {
		q += fmt.Sprintf(` AND date >= $%d`, idx)
		args = append(args, dateFrom)
		idx++
	}
	if dateTo != "" {
		q += fmt.Sprintf(` AND date <= $%d`, idx)
		args = append(args, dateTo)
		idx++
	}
	q += ` ORDER BY date DESC LIMIT 365`

	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("list daily revenue: %w", err)
	}
	defer rows.Close()

	var results []model.DailyRevenue
	for rows.Next() {
		var dr model.DailyRevenue
		var d time.Time
		if err := rows.Scan(&d, &dr.FeeIncome, &dr.LiquidationIncome, &dr.TotalIncome,
			&dr.TradeCount, &dr.LiquidationCount, &dr.ActiveUsers); err != nil {
			return nil, err
		}
		dr.Date = d.Format("2006-01-02")
		results = append(results, dr)
	}
	return results, nil
}

// GetSummary returns revenue aggregated by today/week/month/all-time.
func (r *RevenueRepo) GetSummary(ctx context.Context) (*model.RevenueSummary, error) {
	s := &model.RevenueSummary{}

	// Today — compute from wallet_transactions + positions in real time
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(ABS(amount)),0) FROM wallet_transactions WHERE type='fee' AND created_at >= CURRENT_DATE`).
		Scan(&s.Today.FeeIncome)
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(margin_amount),0) FROM positions WHERE status='liquidated' AND closed_at >= CURRENT_DATE`).
		Scan(&s.Today.LiquidationIncome)
	s.Today.TotalIncome = s.Today.FeeIncome + s.Today.LiquidationIncome

	// Week
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(fee_income),0), COALESCE(SUM(liquidation_income),0)
		 FROM daily_revenue WHERE date >= date_trunc('week', CURRENT_DATE)::date`).
		Scan(&s.Week.FeeIncome, &s.Week.LiquidationIncome)
	s.Week.FeeIncome += s.Today.FeeIncome
	s.Week.LiquidationIncome += s.Today.LiquidationIncome
	s.Week.TotalIncome = s.Week.FeeIncome + s.Week.LiquidationIncome

	// Month
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(fee_income),0), COALESCE(SUM(liquidation_income),0)
		 FROM daily_revenue WHERE date >= date_trunc('month', CURRENT_DATE)::date`).
		Scan(&s.Month.FeeIncome, &s.Month.LiquidationIncome)
	s.Month.FeeIncome += s.Today.FeeIncome
	s.Month.LiquidationIncome += s.Today.LiquidationIncome
	s.Month.TotalIncome = s.Month.FeeIncome + s.Month.LiquidationIncome

	// All time
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(fee_income),0), COALESCE(SUM(liquidation_income),0)
		 FROM daily_revenue`).
		Scan(&s.AllTime.FeeIncome, &s.AllTime.LiquidationIncome)
	s.AllTime.FeeIncome += s.Today.FeeIncome
	s.AllTime.LiquidationIncome += s.Today.LiquidationIncome
	s.AllTime.TotalIncome = s.AllTime.FeeIncome + s.AllTime.LiquidationIncome

	return s, nil
}

// CalcAndUpsertToday aggregates today's revenue from transactions and positions, then upserts.
func (r *RevenueRepo) CalcAndUpsertToday(ctx context.Context) error {
	var feeIncome, liqIncome float64
	var tradeCount, liqCount, activeUsers int

	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(ABS(amount)),0) FROM wallet_transactions WHERE type='fee' AND created_at >= CURRENT_DATE`).
		Scan(&feeIncome)
	_ = r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(margin_amount),0) FROM positions WHERE status='liquidated' AND closed_at >= CURRENT_DATE`).
		Scan(&liqIncome)
	_ = r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM orders WHERE status='filled' AND filled_at >= CURRENT_DATE`).
		Scan(&tradeCount)
	_ = r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM positions WHERE status='liquidated' AND closed_at >= CURRENT_DATE`).
		Scan(&liqCount)
	_ = r.pool.QueryRow(ctx,
		`SELECT COUNT(DISTINCT user_id) FROM orders WHERE created_at >= CURRENT_DATE`).
		Scan(&activeUsers)

	totalIncome := feeIncome + liqIncome

	_, err := r.pool.Exec(ctx,
		`INSERT INTO daily_revenue (date, fee_income, liquidation_income, total_income, trade_count, liquidation_count, active_users)
		 VALUES (CURRENT_DATE, $1, $2, $3, $4, $5, $6)
		 ON CONFLICT (date) DO UPDATE SET
		   fee_income=EXCLUDED.fee_income, liquidation_income=EXCLUDED.liquidation_income,
		   total_income=EXCLUDED.total_income, trade_count=EXCLUDED.trade_count,
		   liquidation_count=EXCLUDED.liquidation_count, active_users=EXCLUDED.active_users`,
		feeIncome, liqIncome, totalIncome, tradeCount, liqCount, activeUsers)
	return err
}
