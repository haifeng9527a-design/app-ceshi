package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"tongxin-go/internal/model"
)

// WeeklyReportRepo Sprint 5：周报数据聚合。
//
// 数据口径与其他模块保持一致：
//   - 返佣：commission_events（按 inviter_uid / status / created_at 过滤，含 pending+settled）
//   - 下级交易量：commission_events.fee_base 合计（已涵盖合约 + 现货）
//   - 新增下级：users.created_at + inviter_uid
//   - 活跃下级：wallet_transactions/orders/spot_orders 任一表 7d 内 created_at / filled_at
//
// 统一 UTC。所有 7d 窗口 = [from, to)，to 独占。
type WeeklyReportRepo struct {
	pool *pgxpool.Pool
}

func NewWeeklyReportRepo(pool *pgxpool.Pool) *WeeklyReportRepo {
	return &WeeklyReportRepo{pool: pool}
}

// ListActiveAgentUIDs 返回所有 is_agent=true 且未被冻结的 UID。
// cron 遍历这批用户挨个生成周报。
func (r *WeeklyReportRepo) ListActiveAgentUIDs(ctx context.Context) ([]string, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT uid FROM users
		WHERE is_agent = true AND COALESCE(is_frozen_referral, false) = false
		ORDER BY uid
	`)
	if err != nil {
		return nil, fmt.Errorf("list agents: %w", err)
	}
	defer rows.Close()

	out := make([]string, 0, 64)
	for rows.Next() {
		var uid string
		if err := rows.Scan(&uid); err != nil {
			return nil, fmt.Errorf("scan agent uid: %w", err)
		}
		out = append(out, uid)
	}
	return out, rows.Err()
}

// AgentMeta 简单用户元数据，用于周报卡片头部。
type AgentMeta struct {
	UID         string
	DisplayName string
	Email       string
}

// GetAgentMeta 拉取 display_name / email。
// uid 不存在时返回 nil（调用方 skip 该 agent）。
func (r *WeeklyReportRepo) GetAgentMeta(ctx context.Context, uid string) (*AgentMeta, error) {
	var m AgentMeta
	err := r.pool.QueryRow(ctx, `
		SELECT uid, COALESCE(display_name, ''), COALESCE(email, '')
		FROM users WHERE uid = $1
	`, uid).Scan(&m.UID, &m.DisplayName, &m.Email)
	if err != nil {
		return nil, fmt.Errorf("get agent meta %s: %w", uid, err)
	}
	return &m, nil
}

// QueryWeeklyIndicators 一次性查出本周 4 个核心指标。
// 用 CTE + COALESCE 避免 NULL，不存在的记录归 0。
func (r *WeeklyReportRepo) QueryWeeklyIndicators(
	ctx context.Context, uid string, from, to time.Time,
) (model.WeeklyReportIndicators, error) {
	var ind model.WeeklyReportIndicators

	err := r.pool.QueryRow(ctx, `
		WITH
		commission AS (
			SELECT COALESCE(SUM(commission_amount), 0)::float8 AS v
			FROM commission_events
			WHERE inviter_uid = $1
			  AND created_at >= $2 AND created_at < $3
		),
		volume AS (
			SELECT COALESCE(SUM(fee_base), 0)::float8 AS v
			FROM commission_events
			WHERE inviter_uid = $1
			  AND created_at >= $2 AND created_at < $3
		),
		new_invitees AS (
			SELECT COUNT(*)::int AS v
			FROM users
			WHERE inviter_uid = $1
			  AND created_at >= $2 AND created_at < $3
		),
		active_invitees AS (
			SELECT COUNT(DISTINCT u.uid)::int AS v
			FROM users u
			LEFT JOIN wallet_transactions wt ON wt.user_id = u.uid
			  AND wt.created_at >= $2 AND wt.created_at < $3
			LEFT JOIN orders o ON o.user_id = u.uid
			  AND o.created_at >= $2 AND o.created_at < $3
			LEFT JOIN spot_orders s ON s.user_id = u.uid
			  AND s.created_at >= $2 AND s.created_at < $3
			WHERE u.inviter_uid = $1
			  AND (wt.id IS NOT NULL OR o.id IS NOT NULL OR s.id IS NOT NULL)
		)
		SELECT
			(SELECT v FROM commission),
			(SELECT v FROM volume),
			(SELECT v FROM new_invitees),
			(SELECT v FROM active_invitees)
	`, uid, from, to).Scan(&ind.CommissionUSDT, &ind.InviteeVolumeUSDT, &ind.NewInvitees, &ind.ActiveInvitees)

	if err != nil {
		return ind, fmt.Errorf("query indicators %s: %w", uid, err)
	}
	return ind, nil
}

// QueryDailyTrend 返回 7 天日度数据，按日期升序。未出现日期需上层补零。
func (r *WeeklyReportRepo) QueryDailyTrend(
	ctx context.Context, uid string, from, to time.Time,
) ([]model.WeeklyReportDailyPoint, error) {
	// 用 generate_series 生成 7 天骨架 → LEFT JOIN 聚合结果，一次查到补零后的日度数据
	rows, err := r.pool.Query(ctx, `
		WITH days AS (
			SELECT generate_series($2::date, ($3::date - interval '1 day')::date, interval '1 day')::date AS d
		),
		commission AS (
			SELECT (created_at AT TIME ZONE 'UTC')::date AS d,
			       SUM(commission_amount)::float8 AS v
			FROM commission_events
			WHERE inviter_uid = $1
			  AND created_at >= $2 AND created_at < $3
			GROUP BY 1
		),
		volume AS (
			SELECT (created_at AT TIME ZONE 'UTC')::date AS d,
			       SUM(fee_base)::float8 AS v
			FROM commission_events
			WHERE inviter_uid = $1
			  AND created_at >= $2 AND created_at < $3
			GROUP BY 1
		),
		active AS (
			SELECT act.d, COUNT(DISTINCT act.uid)::int AS v
			FROM (
				SELECT u.uid, (wt.created_at AT TIME ZONE 'UTC')::date AS d
				FROM users u
				JOIN wallet_transactions wt ON wt.user_id = u.uid
				WHERE u.inviter_uid = $1
				  AND wt.created_at >= $2 AND wt.created_at < $3
				UNION ALL
				SELECT u.uid, (o.created_at AT TIME ZONE 'UTC')::date
				FROM users u
				JOIN orders o ON o.user_id = u.uid
				WHERE u.inviter_uid = $1
				  AND o.created_at >= $2 AND o.created_at < $3
				UNION ALL
				SELECT u.uid, (s.created_at AT TIME ZONE 'UTC')::date
				FROM users u
				JOIN spot_orders s ON s.user_id = u.uid
				WHERE u.inviter_uid = $1
				  AND s.created_at >= $2 AND s.created_at < $3
			) act
			GROUP BY act.d
		)
		SELECT to_char(days.d, 'YYYY-MM-DD') AS date,
		       COALESCE(commission.v, 0)::float8 AS commission_usdt,
		       COALESCE(volume.v, 0)::float8 AS volume_usdt,
		       COALESCE(active.v, 0)::int AS active_invitees
		FROM days
		LEFT JOIN commission ON commission.d = days.d
		LEFT JOIN volume ON volume.d = days.d
		LEFT JOIN active ON active.d = days.d
		ORDER BY days.d
	`, uid, from, to)
	if err != nil {
		return nil, fmt.Errorf("query daily trend: %w", err)
	}
	defer rows.Close()

	out := make([]model.WeeklyReportDailyPoint, 0, 7)
	for rows.Next() {
		var p model.WeeklyReportDailyPoint
		if err := rows.Scan(&p.Date, &p.CommissionUSDT, &p.VolumeUSDT, &p.ActiveInvitees); err != nil {
			return nil, fmt.Errorf("scan daily point: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// QueryTopInvitees 本周返佣 Top N 直接下级。
func (r *WeeklyReportRepo) QueryTopInvitees(
	ctx context.Context, uid string, from, to time.Time, limit int,
) ([]model.WeeklyReportTopInvitee, error) {
	if limit <= 0 {
		limit = 5
	}
	rows, err := r.pool.Query(ctx, `
		SELECT u.uid,
		       COALESCE(u.display_name, '') AS display_name,
		       COALESCE(u.email, '') AS email,
		       COALESCE(SUM(ce.fee_base), 0)::float8 AS volume_usdt,
		       COALESCE(SUM(ce.commission_amount), 0)::float8 AS commission_usdt,
		       (COALESCE(u.my_rebate_rate, 0) * 100)::float8 AS rate_percent
		FROM users u
		LEFT JOIN commission_events ce
		  ON ce.invitee_uid = u.uid
		 AND ce.inviter_uid = $1
		 AND ce.created_at >= $2 AND ce.created_at < $3
		WHERE u.inviter_uid = $1
		GROUP BY u.uid, u.display_name, u.email, u.my_rebate_rate
		HAVING COALESCE(SUM(ce.commission_amount), 0) > 0
		ORDER BY commission_usdt DESC
		LIMIT $4
	`, uid, from, to, limit)
	if err != nil {
		return nil, fmt.Errorf("query top invitees: %w", err)
	}
	defer rows.Close()

	out := make([]model.WeeklyReportTopInvitee, 0, limit)
	for rows.Next() {
		var t model.WeeklyReportTopInvitee
		if err := rows.Scan(&t.UID, &t.DisplayName, &t.Email, &t.VolumeUSDT, &t.CommissionUSDT, &t.RatePercent); err != nil {
			return nil, fmt.Errorf("scan top invitee: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
