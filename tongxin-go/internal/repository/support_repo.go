package repository

import (
	"context"
	"slices"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type SupportRepo struct {
	pool *pgxpool.Pool
}

func NewSupportRepo(pool *pgxpool.Pool) *SupportRepo {
	return &SupportRepo{pool: pool}
}

func (r *SupportRepo) GetActiveByCustomer(ctx context.Context, customerUID string) (*model.SupportAssignment, error) {
	item := &model.SupportAssignment{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, customer_uid, agent_uid, assigned_by, status, conversation_id, created_at, updated_at
		FROM support_assignments
		WHERE customer_uid = $1 AND status = 'active'
		ORDER BY updated_at DESC
		LIMIT 1
	`, customerUID).Scan(
		&item.ID,
		&item.CustomerUID,
		&item.AgentUID,
		&item.AssignedBy,
		&item.Status,
		&item.ConversationID,
		&item.CreatedAt,
		&item.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return item, nil
}

func (r *SupportRepo) ReplaceActive(ctx context.Context, customerUID, agentUID string, assignedBy *string, conversationID string) (*model.SupportAssignment, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `
		UPDATE support_assignments
		SET status = 'transferred', updated_at = NOW()
		WHERE customer_uid = $1 AND status = 'active'
	`, customerUID); err != nil {
		return nil, err
	}

	item := &model.SupportAssignment{}
	if err := tx.QueryRow(ctx, `
		INSERT INTO support_assignments (customer_uid, agent_uid, assigned_by, status, conversation_id)
		VALUES ($1, $2, $3, 'active', $4)
		RETURNING id, customer_uid, agent_uid, assigned_by, status, conversation_id, created_at, updated_at
	`, customerUID, agentUID, assignedBy, conversationID).Scan(
		&item.ID,
		&item.CustomerUID,
		&item.AgentUID,
		&item.AssignedBy,
		&item.Status,
		&item.ConversationID,
		&item.CreatedAt,
		&item.UpdatedAt,
	); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return item, nil
}

func (r *SupportRepo) GetByConversationID(ctx context.Context, conversationID string) (*model.SupportAssignment, error) {
	item := &model.SupportAssignment{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, customer_uid, agent_uid, assigned_by, status, conversation_id, created_at, updated_at
		FROM support_assignments
		WHERE conversation_id = $1 AND status = 'active'
		LIMIT 1
	`, conversationID).Scan(
		&item.ID,
		&item.CustomerUID,
		&item.AgentUID,
		&item.AssignedBy,
		&item.Status,
		&item.ConversationID,
		&item.CreatedAt,
		&item.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return item, nil
}

func (r *SupportRepo) CountActiveByAgentUIDs(ctx context.Context, agentUIDs []string) (map[string]int, error) {
	result := make(map[string]int)
	if len(agentUIDs) == 0 {
		return result, nil
	}

	uniq := slices.Compact(slices.Clone(agentUIDs))
	rows, err := r.pool.Query(ctx, `
		SELECT agent_uid, COUNT(*)::int
		FROM support_assignments
		WHERE status = 'active' AND agent_uid = ANY($1)
		GROUP BY agent_uid
	`, uniq)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var agentUID string
		var count int
		if err := rows.Scan(&agentUID, &count); err != nil {
			return nil, err
		}
		result[agentUID] = count
	}
	for _, uid := range uniq {
		if _, ok := result[uid]; !ok {
			result[uid] = 0
		}
	}
	return result, nil
}

func IsNoRows(err error) bool {
	return err == pgx.ErrNoRows
}
