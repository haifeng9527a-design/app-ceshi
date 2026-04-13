package repository

import (
	"context"
	"fmt"
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
		        admin_reply, replied_by, replied_at, created_at, updated_at
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
			&fb.CreatedAt, &fb.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		list = append(list, fb)
	}
	return list, total, nil
}

func (r *FeedbackRepo) ListAll(ctx context.Context, status string, limit, offset int) ([]model.Feedback, int, error) {
	countQ := `SELECT COUNT(*) FROM feedbacks`
	dataQ := `SELECT f.id, f.user_id, u.display_name, f.content, f.image_urls, f.category, f.status,
	                  f.admin_reply, f.replied_by, f.replied_at, f.created_at, f.updated_at
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
			&fb.RepliedAt, &fb.CreatedAt, &fb.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		list = append(list, fb)
	}
	return list, total, nil
}

func (r *FeedbackRepo) AdminReply(ctx context.Context, id, reply, repliedBy, status string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE feedbacks SET admin_reply = $1, replied_by = $2, replied_at = $3,
		        status = $4, updated_at = $3
		 WHERE id = $5`,
		reply, repliedBy, time.Now(), status, id,
	)
	return err
}

