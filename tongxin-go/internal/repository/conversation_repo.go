package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type ConversationRepo struct {
	pool *pgxpool.Pool
}

var ErrForbidden = errors.New("forbidden")

func NewConversationRepo(pool *pgxpool.Pool) *ConversationRepo {
	return &ConversationRepo{pool: pool}
}

func (r *ConversationRepo) ListByUser(ctx context.Context, uid string) ([]model.Conversation, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT c.id, c.type, COALESCE(c.title,''),
		       CASE WHEN c.type = 'direct' THEN COALESCE(NULLIF(u_peer.avatar_url,''), c.avatar_url, '')
		            ELSE COALESCE(c.avatar_url,'') END,
		       COALESCE(c.created_by,''), c.created_at,
		       COALESCE(m.content,'') AS last_message,
		       COALESCE(u2.display_name,'') AS last_sender_name,
		       COALESCE(m.created_at, c.created_at) AS last_time,
		       COALESCE(
		         (SELECT COUNT(*) FROM messages m2
		          WHERE m2.conversation_id = c.id
		            AND m2.created_at > COALESCE(
		              (SELECT last_read_at FROM message_reads mr WHERE mr.user_id = $1 AND mr.conversation_id = c.id),
		              '1970-01-01'::timestamptz
		            )
		            AND m2.sender_id != $1
		         ), 0
		       ) AS unread_count,
		       COALESCE(peer.peer_uid,'') AS peer_id,
		       (c.type = 'direct' AND COALESCE(u_peer.is_trader, false)) AS peer_is_trader
		FROM conversations c
		JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $1
		LEFT JOIN LATERAL (
		  SELECT cm2.user_id AS peer_uid
		  FROM conversation_members cm2
		  WHERE cm2.conversation_id = c.id AND cm2.user_id <> $1
		  LIMIT 1
		) peer ON true
		LEFT JOIN users u_peer ON u_peer.uid = peer.peer_uid
		LEFT JOIN LATERAL (
		  SELECT content, sender_id, created_at FROM messages
		  WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1
		) m ON true
		LEFT JOIN users u2 ON u2.uid = m.sender_id
		ORDER BY COALESCE(m.created_at, c.created_at) DESC
	`, uid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var convos []model.Conversation
	for rows.Next() {
		var c model.Conversation
		var lastTime time.Time
		if err := rows.Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedBy, &c.CreatedAt,
			&c.LastMessage, &c.LastSenderName, &lastTime, &c.UnreadCount, &c.PeerID, &c.PeerIsTrader); err != nil {
			return nil, err
		}
		c.LastTime = lastTime.Format(time.RFC3339)
		convos = append(convos, c)
	}
	return convos, nil
}

func (r *ConversationRepo) GetByID(ctx context.Context, id string) (*model.Conversation, error) {
	c := &model.Conversation{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, type, COALESCE(title,''), COALESCE(avatar_url,''), COALESCE(created_by,''), created_at
		FROM conversations WHERE id = $1
	`, id).Scan(&c.ID, &c.Type, &c.Title, &c.AvatarURL, &c.CreatedBy, &c.CreatedAt)
	return c, err
}

func (r *ConversationRepo) CreateDirect(ctx context.Context, uid, peerID string) (*model.Conversation, bool, error) {
	// Check if direct conversation already exists
	var existingID string
	err := r.pool.QueryRow(ctx, `
		SELECT cm1.conversation_id
		FROM conversation_members cm1
		JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
		JOIN conversations c ON c.id = cm1.conversation_id
		WHERE cm1.user_id = $1 AND cm2.user_id = $2 AND c.type = 'direct'
		LIMIT 1
	`, uid, peerID).Scan(&existingID)

	if err == nil {
		c, err := r.GetByID(ctx, existingID)
		return c, false, err
	}

	// Create new
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	var convID string
	err = tx.QueryRow(ctx, `
		INSERT INTO conversations (type, created_by) VALUES ('direct', $1) RETURNING id
	`, uid).Scan(&convID)
	if err != nil {
		return nil, false, err
	}

	_, err = tx.Exec(ctx, `INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'member'), ($1, $3, 'member')`, convID, uid, peerID)
	if err != nil {
		return nil, false, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, false, err
	}

	c, err := r.GetByID(ctx, convID)
	return c, true, err
}

func (r *ConversationRepo) CreateGroup(ctx context.Context, uid string, req *model.CreateGroupRequest) (*model.Conversation, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var convID string
	err = tx.QueryRow(ctx, `
		INSERT INTO conversations (type, title, created_by) VALUES ('group', $1, $2) RETURNING id
	`, req.Title, uid).Scan(&convID)
	if err != nil {
		return nil, err
	}

	// Add creator as admin
	_, err = tx.Exec(ctx, `INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'admin')`, convID, uid)
	if err != nil {
		return nil, err
	}

	// Add members
	for _, memberID := range req.MemberIDs {
		if memberID == uid {
			continue
		}
		_, err = tx.Exec(ctx, `INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'member')`, convID, memberID)
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return r.GetByID(ctx, convID)
}

func (r *ConversationRepo) MarkAsRead(ctx context.Context, uid, conversationID string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO message_reads (user_id, conversation_id, last_read_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (user_id, conversation_id) DO UPDATE SET last_read_at = NOW()
	`, uid, conversationID)
	return err
}

func (r *ConversationRepo) GetUnreadCount(ctx context.Context, uid string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(cnt), 0) FROM (
		  SELECT COUNT(*) AS cnt
		  FROM messages m
		  JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = $1
		  LEFT JOIN message_reads mr ON mr.user_id = $1 AND mr.conversation_id = m.conversation_id
		  WHERE m.sender_id != $1
		    AND m.created_at > COALESCE(mr.last_read_at, '1970-01-01'::timestamptz)
		  GROUP BY m.conversation_id
		) sub
	`, uid).Scan(&count)
	return count, err
}

func (r *ConversationRepo) GetGroupInfo(ctx context.Context, conversationID string) (*model.Conversation, []model.ConversationMember, error) {
	c, err := r.GetByID(ctx, conversationID)
	if err != nil {
		return nil, nil, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT cm.conversation_id, cm.user_id, cm.role,
		       COALESCE(u.display_name,''), COALESCE(u.avatar_url,''), COALESCE(u.short_id,''),
		       cm.joined_at
		FROM conversation_members cm
		LEFT JOIN users u ON u.uid = cm.user_id
		WHERE cm.conversation_id = $1
		ORDER BY CASE WHEN cm.role = 'admin' THEN 0 ELSE 1 END, cm.joined_at ASC
	`, conversationID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var members []model.ConversationMember
	for rows.Next() {
		var m model.ConversationMember
		if err := rows.Scan(&m.ConversationID, &m.UserID, &m.Role, &m.DisplayName, &m.AvatarURL, &m.ShortID, &m.JoinedAt); err != nil {
			return nil, nil, err
		}
		members = append(members, m)
	}
	return c, members, nil
}

func (r *ConversationRepo) UpdateGroupInfo(ctx context.Context, requesterUID, conversationID string, req *model.UpdateGroupRequest) error {
	ok, err := r.isGroupAdmin(ctx, requesterUID, conversationID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrForbidden
	}
	_, err = r.pool.Exec(ctx, `
		UPDATE conversations
		SET title = COALESCE(NULLIF($2, ''), title),
		    avatar_url = COALESCE($3, avatar_url)
		WHERE id = $1 AND type = 'group'
	`, conversationID, strings.TrimSpace(req.Title), strings.TrimSpace(req.AvatarURL))
	return err
}

func (r *ConversationRepo) AddGroupMembers(ctx context.Context, requesterUID, conversationID string, memberIDs []string) error {
	ok, err := r.isGroupAdmin(ctx, requesterUID, conversationID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrForbidden
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for _, memberID := range memberIDs {
		memberID = strings.TrimSpace(memberID)
		if memberID == "" || memberID == requesterUID {
			continue
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, role)
			VALUES ($1, $2, 'member')
			ON CONFLICT (conversation_id, user_id) DO NOTHING
		`, conversationID, memberID); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *ConversationRepo) RemoveGroupMember(ctx context.Context, requesterUID, conversationID, memberUID string) error {
	ok, err := r.isGroupAdmin(ctx, requesterUID, conversationID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrForbidden
	}
	memberUID = strings.TrimSpace(memberUID)
	if memberUID == "" {
		return errors.New("member uid is required")
	}

	var role string
	err = r.pool.QueryRow(ctx, `
		SELECT role FROM conversation_members
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, memberUID).Scan(&role)
	if err != nil {
		return err
	}
	if role == "admin" {
		var adminCount int
		if err := r.pool.QueryRow(ctx, `
			SELECT COUNT(*) FROM conversation_members
			WHERE conversation_id = $1 AND role = 'admin'
		`, conversationID).Scan(&adminCount); err != nil {
			return err
		}
		if adminCount <= 1 {
			return errors.New("cannot remove the last admin")
		}
	}

	_, err = r.pool.Exec(ctx, `
		DELETE FROM conversation_members
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, memberUID)
	return err
}

func (r *ConversationRepo) UpdateGroupMemberRole(ctx context.Context, requesterUID, conversationID, memberUID, role string) error {
	ok, err := r.isGroupOwner(ctx, requesterUID, conversationID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrForbidden
	}

	memberUID = strings.TrimSpace(memberUID)
	role = strings.TrimSpace(strings.ToLower(role))
	if memberUID == "" {
		return errors.New("member uid is required")
	}
	if memberUID == requesterUID {
		return errors.New("owner role cannot be changed")
	}
	if role != "admin" && role != "member" {
		return errors.New("invalid role")
	}

	tag, err := r.pool.Exec(ctx, `
		UPDATE conversation_members
		SET role = $3
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, memberUID, role)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("member not found")
	}
	return nil
}

func (r *ConversationRepo) DissolveGroup(ctx context.Context, requesterUID, conversationID string) error {
	ok, err := r.isGroupAdmin(ctx, requesterUID, conversationID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrForbidden
	}
	_, err = r.pool.Exec(ctx, `DELETE FROM conversations WHERE id = $1 AND type = 'group'`, conversationID)
	return err
}

func (r *ConversationRepo) isGroupAdmin(ctx context.Context, uid, conversationID string) (bool, error) {
	var ok bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1
			FROM conversation_members cm
			JOIN conversations c ON c.id = cm.conversation_id
			WHERE cm.conversation_id = $1
			  AND cm.user_id = $2
			  AND cm.role = 'admin'
			  AND c.type = 'group'
		)
	`, conversationID, uid).Scan(&ok)
	return ok, err
}

func (r *ConversationRepo) isGroupOwner(ctx context.Context, uid, conversationID string) (bool, error) {
	var ok bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1
			FROM conversations c
			WHERE c.id = $1
			  AND c.type = 'group'
			  AND c.created_by = $2
		)
	`, conversationID, uid).Scan(&ok)
	return ok, err
}

func (r *ConversationRepo) IsUserInConversation(ctx context.Context, uid, conversationID string) (bool, error) {
	var ok bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM conversation_members
			WHERE conversation_id = $1 AND user_id = $2
		)
	`, conversationID, uid).Scan(&ok)
	return ok, err
}

func (r *ConversationRepo) GetMemberIDs(ctx context.Context, conversationID string) ([]string, error) {
	rows, err := r.pool.Query(ctx, `SELECT user_id FROM conversation_members WHERE conversation_id = $1`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}
