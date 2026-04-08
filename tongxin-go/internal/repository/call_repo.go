package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type CallRepo struct {
	pool *pgxpool.Pool
}

func NewCallRepo(pool *pgxpool.Pool) *CallRepo {
	return &CallRepo{pool: pool}
}

func (r *CallRepo) Create(ctx context.Context, conversationID, initiatorID, roomName, callType string) (*model.Call, error) {
	c := &model.Call{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO calls (conversation_id, initiator_id, room_name, call_type, status)
		VALUES ($1, $2, $3, $4, 'ringing')
		RETURNING id, conversation_id, initiator_id, room_name, call_type, status,
		          started_at, answered_at, ended_at, COALESCE(ended_by,''), COALESCE(end_reason,''),
		          created_at, updated_at
	`, conversationID, initiatorID, roomName, callType).Scan(
		&c.ID, &c.ConversationID, &c.InitiatorID, &c.RoomName, &c.CallType, &c.Status,
		&c.StartedAt, &c.AnsweredAt, &c.EndedAt, &c.EndedBy, &c.EndReason, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create call: %w", err)
	}
	return c, nil
}

func (r *CallRepo) GetByID(ctx context.Context, callID string) (*model.Call, error) {
	c := &model.Call{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, conversation_id, initiator_id, room_name, call_type, status,
		       started_at, answered_at, ended_at, COALESCE(ended_by,''), COALESCE(end_reason,''),
		       created_at, updated_at
		FROM calls
		WHERE id = $1
	`, callID).Scan(
		&c.ID, &c.ConversationID, &c.InitiatorID, &c.RoomName, &c.CallType, &c.Status,
		&c.StartedAt, &c.AnsweredAt, &c.EndedAt, &c.EndedBy, &c.EndReason, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("get call: %w", err)
	}
	return c, nil
}

func (r *CallRepo) FindActiveByConversation(ctx context.Context, conversationID string) (*model.Call, error) {
	c := &model.Call{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, conversation_id, initiator_id, room_name, call_type, status,
		       started_at, answered_at, ended_at, COALESCE(ended_by,''), COALESCE(end_reason,''),
		       created_at, updated_at
		FROM calls
		WHERE conversation_id = $1 AND status IN ('ringing', 'active')
		ORDER BY created_at DESC
		LIMIT 1
	`, conversationID).Scan(
		&c.ID, &c.ConversationID, &c.InitiatorID, &c.RoomName, &c.CallType, &c.Status,
		&c.StartedAt, &c.AnsweredAt, &c.EndedAt, &c.EndedBy, &c.EndReason, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return c, nil
}

func (r *CallRepo) Accept(ctx context.Context, callID string) (*model.Call, error) {
	c := &model.Call{}
	now := time.Now().UTC()
	err := r.pool.QueryRow(ctx, `
		UPDATE calls
		SET status = 'active', answered_at = $2, updated_at = NOW()
		WHERE id = $1 AND status = 'ringing'
		RETURNING id, conversation_id, initiator_id, room_name, call_type, status,
		          started_at, answered_at, ended_at, COALESCE(ended_by,''), COALESCE(end_reason,''),
		          created_at, updated_at
	`, callID, now).Scan(
		&c.ID, &c.ConversationID, &c.InitiatorID, &c.RoomName, &c.CallType, &c.Status,
		&c.StartedAt, &c.AnsweredAt, &c.EndedAt, &c.EndedBy, &c.EndReason, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("accept call: %w", err)
	}
	return c, nil
}

func (r *CallRepo) Reject(ctx context.Context, callID, endedBy, reason string) (*model.Call, error) {
	return r.finish(ctx, callID, "rejected", endedBy, reason)
}

func (r *CallRepo) End(ctx context.Context, callID, endedBy, reason string) (*model.Call, error) {
	return r.finish(ctx, callID, "ended", endedBy, reason)
}

func (r *CallRepo) finish(ctx context.Context, callID, status, endedBy, reason string) (*model.Call, error) {
	c := &model.Call{}
	now := time.Now().UTC()
	err := r.pool.QueryRow(ctx, `
		UPDATE calls
		SET status = $2, ended_at = $3, ended_by = $4, end_reason = $5, updated_at = NOW()
		WHERE id = $1 AND status IN ('ringing', 'active')
		RETURNING id, conversation_id, initiator_id, room_name, call_type, status,
		          started_at, answered_at, ended_at, COALESCE(ended_by,''), COALESCE(end_reason,''),
		          created_at, updated_at
	`, callID, status, now, endedBy, reason).Scan(
		&c.ID, &c.ConversationID, &c.InitiatorID, &c.RoomName, &c.CallType, &c.Status,
		&c.StartedAt, &c.AnsweredAt, &c.EndedAt, &c.EndedBy, &c.EndReason, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("finish call: %w", err)
	}
	return c, nil
}
