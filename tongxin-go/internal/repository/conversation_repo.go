package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type ConversationRepo struct {
	pool *pgxpool.Pool
}

func NewConversationRepo(pool *pgxpool.Pool) *ConversationRepo {
	return &ConversationRepo{pool: pool}
}

func (r *ConversationRepo) ListByUser(ctx context.Context, uid string) ([]model.Conversation, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT c.id, c.type, COALESCE(c.title,''), COALESCE(c.avatar_url,''),
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
		SELECT conversation_id, user_id, role, joined_at
		FROM conversation_members WHERE conversation_id = $1
	`, conversationID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var members []model.ConversationMember
	for rows.Next() {
		var m model.ConversationMember
		if err := rows.Scan(&m.ConversationID, &m.UserID, &m.Role, &m.JoinedAt); err != nil {
			return nil, nil, err
		}
		members = append(members, m)
	}
	return c, members, nil
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
