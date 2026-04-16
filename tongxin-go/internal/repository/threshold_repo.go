package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"tongxin-go/internal/model"
)

// ThresholdRepo 封装 agent_thresholds 表（migration 037）。
type ThresholdRepo struct {
	pool *pgxpool.Pool
}

func NewThresholdRepo(pool *pgxpool.Pool) *ThresholdRepo {
	return &ThresholdRepo{pool: pool}
}

var (
	ErrThresholdNotFound = errors.New("threshold not found")
	// ErrThresholdInvalidMetric 由 service 层校验 metric 是否在
	// SupportedThresholdMetrics 列表中返回。这里定义只是方便 handler 识别。
	ErrThresholdInvalidMetric = errors.New("invalid metric")
	ErrThresholdInvalidOp     = errors.New("invalid op")
)

// Upsert 按 (agent_uid, metric) 唯一键做 upsert：
//   - 新增时 last_triggered_at 初始化为 NULL
//   - 修改时不重置 last_triggered_at（避免用户改阈值就把防抖清零 → 立刻再推送）
func (r *ThresholdRepo) Upsert(ctx context.Context, in *model.UpsertThresholdInput) (*model.AgentThreshold, error) {
	if in == nil || in.AgentUID == "" || in.Metric == "" || in.Op == "" {
		return nil, errors.New("agent_uid / metric / op required")
	}
	t := &model.AgentThreshold{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO agent_thresholds (agent_uid, metric, op, threshold_value, is_enabled)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (agent_uid, metric) DO UPDATE SET
		  op              = EXCLUDED.op,
		  threshold_value = EXCLUDED.threshold_value,
		  is_enabled      = EXCLUDED.is_enabled
		RETURNING id, agent_uid, metric, op, threshold_value, is_enabled, last_triggered_at, created_at
	`, in.AgentUID, in.Metric, in.Op, in.ThresholdValue, in.IsEnabled).Scan(
		&t.ID, &t.AgentUID, &t.Metric, &t.Op, &t.ThresholdValue, &t.IsEnabled, &t.LastTriggeredAt, &t.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("upsert threshold: %w", err)
	}
	return t, nil
}

// ListByAgent 返回某代理全部阈值（按 metric 字典序）。
func (r *ThresholdRepo) ListByAgent(ctx context.Context, agentUID string) ([]*model.AgentThreshold, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, agent_uid, metric, op, threshold_value, is_enabled, last_triggered_at, created_at
		FROM agent_thresholds
		WHERE agent_uid = $1
		ORDER BY metric ASC
	`, agentUID)
	if err != nil {
		return nil, fmt.Errorf("list thresholds: %w", err)
	}
	defer rows.Close()

	list := make([]*model.AgentThreshold, 0)
	for rows.Next() {
		t := &model.AgentThreshold{}
		if err := rows.Scan(
			&t.ID, &t.AgentUID, &t.Metric, &t.Op, &t.ThresholdValue, &t.IsEnabled, &t.LastTriggeredAt, &t.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan threshold: %w", err)
		}
		list = append(list, t)
	}
	return list, nil
}

// Delete 仅当该阈值属于此 agent 时才删。
func (r *ThresholdRepo) Delete(ctx context.Context, id, agentUID string) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM agent_thresholds WHERE id = $1 AND agent_uid = $2`,
		id, agentUID,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrThresholdNotFound
		}
		return fmt.Errorf("delete threshold: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrThresholdNotFound
	}
	return nil
}

// ListAllEnabled cron scanner 使用：拉全部 enabled=true 的阈值（跨 agent）。
// 对于 5 个代理 * 4 种 metric = 最多 20 条，无需分页。
func (r *ThresholdRepo) ListAllEnabled(ctx context.Context) ([]*model.AgentThreshold, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, agent_uid, metric, op, threshold_value, is_enabled, last_triggered_at, created_at
		FROM agent_thresholds
		WHERE is_enabled = true
	`)
	if err != nil {
		return nil, fmt.Errorf("list all enabled: %w", err)
	}
	defer rows.Close()

	list := make([]*model.AgentThreshold, 0)
	for rows.Next() {
		t := &model.AgentThreshold{}
		if err := rows.Scan(
			&t.ID, &t.AgentUID, &t.Metric, &t.Op, &t.ThresholdValue, &t.IsEnabled, &t.LastTriggeredAt, &t.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan threshold: %w", err)
		}
		list = append(list, t)
	}
	return list, nil
}

// MarkTriggered cron 触发后记录时间戳，用于 24h 防抖。
func (r *ThresholdRepo) MarkTriggered(ctx context.Context, id string, at time.Time) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE agent_thresholds SET last_triggered_at = $1 WHERE id = $2`,
		at, id,
	)
	if err != nil {
		return fmt.Errorf("mark triggered: %w", err)
	}
	return nil
}
