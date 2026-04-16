package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"tongxin-go/internal/model"
)

// TimeSeriesRepo 负责 M4 多指标叠加图的数据聚合查询。
//
// 设计要点：
//   - 每个 metric 独立 SQL（不是单个 UNION ALL 大查询）。
//     理由：日期补零、聚合列名映射、WHERE 条件不同，强行合并反而复杂。
//     性能：数据量小（几千 wallet_tx + commission_records），多查询依然亚秒。
//
//   - 粒度：使用 Postgres 的 date_trunc('day'|'week'|'month', ts) 做分桶，之后在 Go 端
//     做空日期补零（返回给前端 series 保证连续）。
//
//   - 时区：统一 UTC。前端若显示本地时间，只在渲染层换算。
type TimeSeriesRepo struct {
	pool *pgxpool.Pool
}

func NewTimeSeriesRepo(pool *pgxpool.Pool) *TimeSeriesRepo {
	return &TimeSeriesRepo{pool: pool}
}

var (
	ErrTimeSeriesBadRange       = errors.New("from must be <= to")
	ErrTimeSeriesBadGranularity = errors.New("granularity must be day, week, or month")
)

// ValidGranularity 与前端下拉/默认值对齐。
func ValidGranularity(g string) bool {
	return g == "day" || g == "week" || g == "month"
}

// TimeSeriesQuery 查询入参。
type TimeSeriesQuery struct {
	AgentUID    string
	Metric      string // 'deposit' | 'withdraw' | 'volume' | 'commission'
	From        time.Time
	To          time.Time
	Granularity string // 'day' | 'week' | 'month'
}

// QueryMetric 按单一 metric 拉时间序列（已包含 date_trunc 聚合）。
// 返回 points 顺序：按 bucket 日期升序；不补零（Service 层补）。
func (r *TimeSeriesRepo) QueryMetric(
	ctx context.Context, q TimeSeriesQuery,
) ([]model.TimeSeriesPoint, error) {
	if q.From.After(q.To) {
		return nil, ErrTimeSeriesBadRange
	}
	if !ValidGranularity(q.Granularity) {
		return nil, ErrTimeSeriesBadGranularity
	}

	sql, args, err := r.buildSQL(q)
	if err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, fmt.Errorf("query time-series %s: %w", q.Metric, err)
	}
	defer rows.Close()

	out := make([]model.TimeSeriesPoint, 0, 32)
	for rows.Next() {
		var ts time.Time
		var value float64
		if err := rows.Scan(&ts, &value); err != nil {
			return nil, fmt.Errorf("scan time-series row: %w", err)
		}
		out = append(out, model.TimeSeriesPoint{
			Date:  ts.UTC().Format("2006-01-02"),
			Value: value,
		})
	}
	return out, rows.Err()
}

// buildSQL 按 metric 分派具体 SQL。
// 所有 SQL 的 bucket 列都叫 bucket::date，值列叫 value::float8。
func (r *TimeSeriesRepo) buildSQL(q TimeSeriesQuery) (string, []interface{}, error) {
	// date_trunc 的第一个参数必须 inline（Postgres 不支持参数化）。校验过 q.Granularity 即安全。
	trunc := q.Granularity

	switch q.Metric {
	case "deposit":
		sql := fmt.Sprintf(`
			SELECT date_trunc('%s', wt.created_at AT TIME ZONE 'UTC')::date AS bucket,
			       COALESCE(SUM(wt.amount), 0)::float8 AS value
			FROM wallet_transactions wt
			JOIN users u ON u.uid = wt.user_id
			WHERE u.inviter_uid = $1
			  AND wt.type = 'deposit'
			  AND wt.created_at >= $2
			  AND wt.created_at <  $3
			GROUP BY bucket
			ORDER BY bucket
		`, trunc)
		return sql, []interface{}{q.AgentUID, q.From, q.To}, nil

	case "withdraw":
		// withdraw 原值为负数，取绝对值
		sql := fmt.Sprintf(`
			SELECT date_trunc('%s', wt.created_at AT TIME ZONE 'UTC')::date AS bucket,
			       COALESCE(SUM(-wt.amount), 0)::float8 AS value
			FROM wallet_transactions wt
			JOIN users u ON u.uid = wt.user_id
			WHERE u.inviter_uid = $1
			  AND wt.type = 'withdraw'
			  AND wt.created_at >= $2
			  AND wt.created_at <  $3
			GROUP BY bucket
			ORDER BY bucket
		`, trunc)
		return sql, []interface{}{q.AgentUID, q.From, q.To}, nil

	case "volume":
		// 合约 filled 成交额 + 现货 quote_qty。UNION ALL 后外层 group。
		sql := fmt.Sprintf(`
			WITH buckets AS (
				SELECT date_trunc('%[1]s', o.filled_at AT TIME ZONE 'UTC')::date AS bucket,
				       (o.filled_price * o.qty)::float8 AS value
				FROM orders o
				JOIN users u ON u.uid = o.user_id
				WHERE u.inviter_uid = $1
				  AND o.status = 'filled'
				  AND o.filled_at IS NOT NULL
				  AND o.filled_at >= $2
				  AND o.filled_at <  $3
				UNION ALL
				SELECT date_trunc('%[1]s', s.filled_at AT TIME ZONE 'UTC')::date AS bucket,
				       s.quote_qty::float8 AS value
				FROM spot_orders s
				JOIN users u ON u.uid = s.user_id
				WHERE u.inviter_uid = $1
				  AND s.status = 'filled'
				  AND s.filled_at IS NOT NULL
				  AND s.filled_at >= $2
				  AND s.filled_at <  $3
			)
			SELECT bucket, COALESCE(SUM(value), 0)::float8 AS value
			FROM buckets
			GROUP BY bucket
			ORDER BY bucket
		`, trunc)
		return sql, []interface{}{q.AgentUID, q.From, q.To}, nil

	case "commission":
		// commission_records.period_date 本身就是 date，直接 date_trunc 也 OK
		sql := fmt.Sprintf(`
			SELECT date_trunc('%s', cr.period_date)::date AS bucket,
			       COALESCE(SUM(cr.commission_amount), 0)::float8 AS value
			FROM commission_records cr
			WHERE cr.inviter_uid = $1
			  AND cr.period_date >= $2::date
			  AND cr.period_date <  $3::date
			GROUP BY bucket
			ORDER BY bucket
		`, trunc)
		return sql, []interface{}{q.AgentUID, q.From, q.To}, nil

	default:
		return "", nil, fmt.Errorf("unsupported metric: %s", q.Metric)
	}
}
