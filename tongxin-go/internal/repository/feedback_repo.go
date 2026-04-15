package repository

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type FeedbackRepo struct {
	pool *pgxpool.Pool
}

func NewFeedbackRepo(pool *pgxpool.Pool) *FeedbackRepo {
	return &FeedbackRepo{pool: pool}
}

func (r *FeedbackRepo) Create(ctx context.Context, fb *model.Feedback) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO feedbacks (user_id, content, image_urls, category)
		 VALUES ($1, $2, $3, $4)`,
		fb.UserID, fb.Content, fb.ImageURLs, fb.Category,
	)
	return err
}

func (r *FeedbackRepo) ListByUser(ctx context.Context, userID string, limit, offset int) ([]model.Feedback, int, error) {
	var total int
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM feedbacks WHERE user_id = $1`, userID,
	).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, content, image_urls, category, status,
		        COALESCE(admin_reply, ''), COALESCE(replied_by, ''),
		        replied_at, user_unread, created_at, updated_at
		 FROM feedbacks WHERE user_id = $1
		 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
		userID, limit, offset,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var list []model.Feedback
	for rows.Next() {
		var fb model.Feedback
		if err := rows.Scan(
			&fb.ID, &fb.UserID, &fb.Content, &fb.ImageURLs, &fb.Category,
			&fb.Status, &fb.AdminReply, &fb.RepliedBy, &fb.RepliedAt,
			&fb.UserUnread, &fb.CreatedAt, &fb.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		list = append(list, fb)
	}
	return list, total, nil
}

// GetByIDForUser returns a single feedback row if it belongs to the given user; pgx.ErrNoRows otherwise.
func (r *FeedbackRepo) GetByIDForUser(ctx context.Context, id, userID string) (*model.Feedback, error) {
	var fb model.Feedback
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, content, image_urls, category, status,
		        COALESCE(admin_reply, ''), COALESCE(replied_by, ''),
		        replied_at, user_unread, created_at, updated_at
		 FROM feedbacks WHERE id = $1 AND user_id = $2`,
		id, userID,
	).Scan(
		&fb.ID, &fb.UserID, &fb.Content, &fb.ImageURLs, &fb.Category,
		&fb.Status, &fb.AdminReply, &fb.RepliedBy, &fb.RepliedAt,
		&fb.UserUnread, &fb.CreatedAt, &fb.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &fb, nil
}

// MarkRead clears the user_unread flag. Returns nil even if nothing matched (idempotent).
func (r *FeedbackRepo) MarkRead(ctx context.Context, id, userID string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE feedbacks SET user_unread = FALSE, updated_at = NOW()
		 WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	return err
}

// CountUserUnread returns how many feedbacks of this user still have user_unread = TRUE.
func (r *FeedbackRepo) CountUserUnread(ctx context.Context, userID string) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM feedbacks WHERE user_id = $1 AND user_unread = TRUE`,
		userID,
	).Scan(&n)
	return n, err
}

func (r *FeedbackRepo) ListAll(ctx context.Context, status string, limit, offset int) ([]model.Feedback, int, error) {
	countQ := `SELECT COUNT(*) FROM feedbacks`
	dataQ := `SELECT f.id, f.user_id, COALESCE(u.display_name, ''), f.content, f.image_urls, f.category, f.status,
	                  COALESCE(f.admin_reply, ''), COALESCE(f.replied_by, ''),
	                  f.replied_at, f.user_unread, f.created_at, f.updated_at
	           FROM feedbacks f LEFT JOIN users u ON f.user_id = u.uid`

	args := []any{}
	if status != "" && status != "all" {
		countQ += ` WHERE status = $1`
		dataQ += ` WHERE f.status = $1`
		args = append(args, status)
	}
	dataQ += ` ORDER BY f.created_at DESC`

	var total int
	if err := r.pool.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	idx := len(args) + 1
	dataQ += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, idx, idx+1)
	args = append(args, limit, offset)

	rows, err := r.pool.Query(ctx, dataQ, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var list []model.Feedback
	for rows.Next() {
		var fb model.Feedback
		if err := rows.Scan(
			&fb.ID, &fb.UserID, &fb.DisplayName, &fb.Content, &fb.ImageURLs,
			&fb.Category, &fb.Status, &fb.AdminReply, &fb.RepliedBy,
			&fb.RepliedAt, &fb.UserUnread, &fb.CreatedAt, &fb.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		list = append(list, fb)
	}
	return list, total, nil
}

func (r *FeedbackRepo) AdminReply(ctx context.Context, id, reply, repliedBy, status string) error {
	// 只要管理员写了回复正文，就置 user_unread=TRUE，让用户在 App 端看到红点。
	// 空回复（仅改状态）不触发未读，避免误红点。
	unread := strings.TrimSpace(reply) != ""
	_, err := r.pool.Exec(ctx,
		`UPDATE feedbacks SET admin_reply = $1, replied_by = $2, replied_at = $3,
		        status = $4, user_unread = CASE WHEN $6 THEN TRUE ELSE user_unread END,
		        updated_at = $3
		 WHERE id = $5`,
		reply, repliedBy, time.Now(), status, id, unread,
	)
	return err
}

