package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"tongxin-go/internal/model"
)

// TouchRepo 封装 touch_history 表（migration 037）。
type TouchRepo struct {
	pool *pgxpool.Pool
}

func NewTouchRepo(pool *pgxpool.Pool) *TouchRepo {
	return &TouchRepo{pool: pool}
}

// Insert 写一条触达记录（同步调用：service 层已完成所有 channel 的实际发送）。
// payload 必须是 json.RawMessage（外层已 Marshal），由 pgx 直接存为 jsonb。
func (r *TouchRepo) Insert(
	ctx context.Context,
	agentUID string,
	inviteeUIDs []string,
	template string,
	channels []string,
	payload []byte,
	status string,
) (*model.TouchHistory, error) {
	if agentUID == "" || len(inviteeUIDs) == 0 || template == "" || len(channels) == 0 {
		return nil, errors.New("agent_uid / invitee_uids / template / channels required")
	}

	t := &model.TouchHistory{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO touch_history (agent_uid, invitee_uids, template, channels, payload, status)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, agent_uid, invitee_uids, template, channels, payload, status, created_at
	`, agentUID, inviteeUIDs, template, channels, payload, status).Scan(
		&t.ID, &t.AgentUID, &t.InviteeUIDs, &t.Template, &t.Channels, &t.Payload, &t.Status, &t.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("insert touch history: %w", err)
	}
	return t, nil
}

// List 返回代理自己的触达记录（按时间倒序）。
func (r *TouchRepo) List(ctx context.Context, agentUID string, limit int) ([]*model.TouchHistory, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := r.pool.Query(ctx, `
		SELECT id, agent_uid, invitee_uids, template, channels, payload, status, created_at
		FROM touch_history
		WHERE agent_uid = $1
		ORDER BY created_at DESC
		LIMIT $2
	`, agentUID, limit)
	if err != nil {
		return nil, fmt.Errorf("list touch history: %w", err)
	}
	defer rows.Close()

	list := make([]*model.TouchHistory, 0, limit)
	for rows.Next() {
		t := &model.TouchHistory{}
		if err := rows.Scan(
			&t.ID, &t.AgentUID, &t.InviteeUIDs, &t.Template, &t.Channels, &t.Payload, &t.Status, &t.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan touch history: %w", err)
		}
		list = append(list, t)
	}
	return list, nil
}
