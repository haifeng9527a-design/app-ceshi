package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type FriendRepo struct {
	pool *pgxpool.Pool
}

func NewFriendRepo(pool *pgxpool.Pool) *FriendRepo {
	return &FriendRepo{pool: pool}
}

func (r *FriendRepo) SendRequest(ctx context.Context, fromUID, toUID, message string) (*model.FriendRequest, error) {
	req := &model.FriendRequest{
		FromUserID: fromUID,
		ToUserID:   toUID,
		Message:    message,
		Status:     "pending",
		CreatedAt:  time.Now(),
	}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO friend_requests (from_user_id, to_user_id, message)
		VALUES ($1, $2, $3)
		RETURNING id, created_at
	`, fromUID, toUID, message).Scan(&req.ID, &req.CreatedAt)
	return req, err
}

// AcceptRequest marks the request accepted and creates friendship rows. Returns from_user_id (requester) for notifications.
func (r *FriendRepo) AcceptRequest(ctx context.Context, requestID, currentUID string) (fromUID string, err error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	var toUID string
	err = tx.QueryRow(ctx, `
		UPDATE friend_requests SET status = 'accepted'
		WHERE id = $1 AND to_user_id = $2 AND status = 'pending'
		RETURNING from_user_id, to_user_id
	`, requestID, currentUID).Scan(&fromUID, &toUID)
	if err != nil {
		return "", err
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO friends (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
		ON CONFLICT DO NOTHING
	`, fromUID, toUID)
	if err != nil {
		return "", err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO friends (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
		ON CONFLICT DO NOTHING
	`, toUID, fromUID)
	if err != nil {
		return "", err
	}

	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	return fromUID, nil
}

func (r *FriendRepo) RejectRequest(ctx context.Context, requestID, currentUID string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE friend_requests SET status = 'rejected'
		WHERE id = $1 AND to_user_id = $2 AND status = 'pending'
	`, requestID, currentUID)
	return err
}

func (r *FriendRepo) GetIncoming(ctx context.Context, uid string) ([]model.FriendRequest, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT fr.id, fr.from_user_id, fr.to_user_id, fr.status, COALESCE(fr.message,''), fr.created_at
		FROM friend_requests fr
		WHERE fr.to_user_id = $1 AND fr.status = 'pending'
		ORDER BY fr.created_at DESC
	`, uid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var reqs []model.FriendRequest
	for rows.Next() {
		var r model.FriendRequest
		if err := rows.Scan(&r.ID, &r.FromUserID, &r.ToUserID, &r.Status, &r.Message, &r.CreatedAt); err != nil {
			return nil, err
		}
		reqs = append(reqs, r)
	}
	return reqs, nil
}

func (r *FriendRepo) GetOutgoing(ctx context.Context, uid string) ([]model.FriendRequest, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, from_user_id, to_user_id, status, COALESCE(message,''), created_at
		FROM friend_requests
		WHERE from_user_id = $1 AND status = 'pending'
		ORDER BY created_at DESC
	`, uid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var reqs []model.FriendRequest
	for rows.Next() {
		var r model.FriendRequest
		if err := rows.Scan(&r.ID, &r.FromUserID, &r.ToUserID, &r.Status, &r.Message, &r.CreatedAt); err != nil {
			return nil, err
		}
		reqs = append(reqs, r)
	}
	return reqs, nil
}

func (r *FriendRepo) ListFriends(ctx context.Context, uid string) ([]model.FriendProfile, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT u.uid, u.email, u.display_name, COALESCE(u.avatar_url,''),
		       COALESCE(u.role,'user'), COALESCE(u.status,'active'), COALESCE(u.short_id,'')
		FROM friends f
		JOIN users u ON u.uid = f.friend_id
		WHERE f.user_id = $1 AND f.status = 'accepted'
		ORDER BY u.display_name
	`, uid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var friends []model.FriendProfile
	for rows.Next() {
		var p model.FriendProfile
		if err := rows.Scan(&p.UserID, &p.Email, &p.DisplayName, &p.AvatarURL, &p.Role, &p.Status, &p.ShortID); err != nil {
			return nil, err
		}
		friends = append(friends, p)
	}
	return friends, nil
}

func (r *FriendRepo) GetRelationship(ctx context.Context, viewerUID, targetUID string) (status model.ChatRelationshipStatus, requestID string, err error) {
	if viewerUID == targetUID {
		return model.ChatRelationshipSelf, "", nil
	}

	var (
		isFriend        bool
		hasOutgoing     bool
		hasIncoming     bool
		incomingRequest string
	)
	err = r.pool.QueryRow(ctx, `
		SELECT
			EXISTS(
				SELECT 1 FROM friends
				WHERE user_id = $1 AND friend_id = $2 AND status = 'accepted'
			),
			EXISTS(
				SELECT 1 FROM friend_requests
				WHERE from_user_id = $1 AND to_user_id = $2 AND status = 'pending'
			),
			EXISTS(
				SELECT 1 FROM friend_requests
				WHERE from_user_id = $2 AND to_user_id = $1 AND status = 'pending'
			),
			COALESCE((
				SELECT id::text FROM friend_requests
				WHERE from_user_id = $2 AND to_user_id = $1 AND status = 'pending'
				ORDER BY created_at DESC
				LIMIT 1
			), '')
	`, viewerUID, targetUID).Scan(&isFriend, &hasOutgoing, &hasIncoming, &incomingRequest)
	if err != nil {
		return "", "", err
	}

	switch {
	case isFriend:
		return model.ChatRelationshipFriend, "", nil
	case hasOutgoing:
		return model.ChatRelationshipPendingOutgoing, "", nil
	case hasIncoming:
		return model.ChatRelationshipPendingIncoming, incomingRequest, nil
	default:
		return model.ChatRelationshipNotFriend, "", nil
	}
}

func (r *FriendRepo) DeleteFriend(ctx context.Context, uid, friendID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `DELETE FROM friends WHERE user_id = $1 AND friend_id = $2`, uid, friendID)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `DELETE FROM friends WHERE user_id = $1 AND friend_id = $2`, friendID, uid)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *FriendRepo) BlockUser(ctx context.Context, uid, targetID string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO friends (user_id, friend_id, status) VALUES ($1, $2, 'blocked')
		ON CONFLICT (user_id, friend_id) DO UPDATE SET status = 'blocked'
	`, uid, targetID)
	return err
}
