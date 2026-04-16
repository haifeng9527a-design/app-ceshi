package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

// NotificationRepo 封装 notifications 表（migration 036）。
type NotificationRepo struct {
	pool *pgxpool.Pool
}

func NewNotificationRepo(pool *pgxpool.Pool) *NotificationRepo {
	return &NotificationRepo{pool: pool}
}

var ErrNotificationNotFound = errors.New("notification not found")

// Create 写一条通知，返回插入后的完整行（含 server-side gen_random_uuid + created_at）。
func (r *NotificationRepo) Create(ctx context.Context, in *model.CreateNotificationInput) (*model.Notification, error) {
	if in == nil || in.UserUID == "" || in.Kind == "" || in.Title == "" {
		return nil, errors.New("user_uid / kind / title required")
	}

	n := &model.Notification{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO notifications (user_uid, kind, title, body, payload)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, user_uid, kind, title, body, payload, read_at, created_at
	`, in.UserUID, in.Kind, in.Title, in.Body, in.Payload).Scan(
		&n.ID, &n.UserUID, &n.Kind, &n.Title, &n.Body, &n.Payload, &n.ReadAt, &n.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("insert notification: %w", err)
	}
	return n, nil
}

// List 列出用户的通知（按 created_at DESC）。unreadOnly=true 时仅未读。
// 同时返回 total（按是否仅未读过滤的总数）和 unreadTotal（始终是未读数，用于 bell badge）。
func (r *NotificationRepo) List(
	ctx context.Context, userUID string, unreadOnly bool, limit, offset int,
) ([]*model.Notification, int, int, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}

	// total（按 unreadOnly 过滤）
	var total int
	if unreadOnly {
		err := r.pool.QueryRow(ctx,
			`SELECT COUNT(*) FROM notifications WHERE user_uid = $1 AND read_at IS NULL`,
			userUID,
		).Scan(&total)
		if err != nil {
			return nil, 0, 0, fmt.Errorf("count unread: %w", err)
		}
	} else {
		err := r.pool.QueryRow(ctx,
			`SELECT COUNT(*) FROM notifications WHERE user_uid = $1`,
			userUID,
		).Scan(&total)
		if err != nil {
			return nil, 0, 0, fmt.Errorf("count all: %w", err)
		}
	}

	// unreadTotal 始终独立计算（前端 bell badge 即使在 unreadOnly=false 时也要看）
	var unreadTotal int
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM notifications WHERE user_uid = $1 AND read_at IS NULL`,
		userUID,
	).Scan(&unreadTotal); err != nil {
		return nil, 0, 0, fmt.Errorf("count unread total: %w", err)
	}

	// 列表
	q := `
		SELECT id, user_uid, kind, title, body, payload, read_at, created_at
		FROM notifications
		WHERE user_uid = $1
	`
	if unreadOnly {
		q += ` AND read_at IS NULL`
	}
	q += ` ORDER BY created_at DESC LIMIT $2 OFFSET $3`

	rows, err := r.pool.Query(ctx, q, userUID, limit, offset)
	if err != nil {
		return nil, 0, 0, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	list := make([]*model.Notification, 0, limit)
	for rows.Next() {
		n := &model.Notification{}
		if err := rows.Scan(
			&n.ID, &n.UserUID, &n.Kind, &n.Title, &n.Body, &n.Payload, &n.ReadAt, &n.CreatedAt,
		); err != nil {
			return nil, 0, 0, fmt.Errorf("scan notification: %w", err)
		}
		list = append(list, n)
	}
	return list, total, unreadTotal, nil
}

// CountUnread 仅返回未读数（前端首屏调用，比 List 轻量）。
func (r *NotificationRepo) CountUnread(ctx context.Context, userUID string) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM notifications WHERE user_uid = $1 AND read_at IS NULL`,
		userUID,
	).Scan(&n)
	return n, err
}

// MarkRead 标记单条已读。返回 ErrNotificationNotFound 若 id 不属于该 user 或已不存在。
func (r *NotificationRepo) MarkRead(ctx context.Context, id, userUID string) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE notifications SET read_at = NOW()
		 WHERE id = $1 AND user_uid = $2 AND read_at IS NULL`,
		id, userUID,
	)
	if err != nil {
		// id 格式错误时（uuid parse fail）pgx 会返回 error，归一为 not found
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotificationNotFound
		}
		return fmt.Errorf("mark read: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotificationNotFound
	}
	return nil
}

// MarkAllRead 把该 user 全部未读标为已读，返回受影响行数。
func (r *NotificationRepo) MarkAllRead(ctx context.Context, userUID string) (int, error) {
	tag, err := r.pool.Exec(ctx,
		`UPDATE notifications SET read_at = NOW()
		 WHERE user_uid = $1 AND read_at IS NULL`,
		userUID,
	)
	if err != nil {
		return 0, fmt.Errorf("mark all read: %w", err)
	}
	return int(tag.RowsAffected()), nil
}
