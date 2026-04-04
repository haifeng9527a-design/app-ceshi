package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type MessageRepo struct {
	pool *pgxpool.Pool
}

func NewMessageRepo(pool *pgxpool.Pool) *MessageRepo {
	return &MessageRepo{pool: pool}
}

func (r *MessageRepo) Create(ctx context.Context, msg *model.Message) error {
	msgType := msg.MessageType
	if msgType == "" {
		msgType = "text"
	}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, content, message_type, media_url, reply_to_message_id)
		VALUES ($1, $2, $3, $4, $5, NULLIF($6, '')::uuid)
		RETURNING id, created_at
	`, msg.ConversationID, msg.SenderID, msg.Content, msgType, msg.MediaURL, msg.ReplyToMessageID,
	).Scan(&msg.ID, &msg.CreatedAt)
	return err
}

func (r *MessageRepo) ListByConversation(ctx context.Context, conversationID string, limit int, before *time.Time) ([]model.Message, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	var query string
	var args []any

	if before != nil {
		query = `
			SELECT m.id, m.conversation_id, m.sender_id,
			       COALESCE(u.display_name,'') AS sender_name,
			       m.content, m.message_type, COALESCE(m.media_url,''),
			       COALESCE(m.reply_to_message_id::text,''),
			       COALESCE(ru.display_name,'') AS reply_to_sender,
			       COALESCE(rm.content,'') AS reply_to_content,
			       m.created_at
			FROM messages m
			JOIN users u ON u.uid = m.sender_id
			LEFT JOIN messages rm ON rm.id = m.reply_to_message_id
			LEFT JOIN users ru ON ru.uid = rm.sender_id
			WHERE m.conversation_id = $1 AND m.created_at < $2
			ORDER BY m.created_at DESC
			LIMIT $3
		`
		args = []any{conversationID, *before, limit}
	} else {
		query = `
			SELECT m.id, m.conversation_id, m.sender_id,
			       COALESCE(u.display_name,'') AS sender_name,
			       m.content, m.message_type, COALESCE(m.media_url,''),
			       COALESCE(m.reply_to_message_id::text,''),
			       COALESCE(ru.display_name,'') AS reply_to_sender,
			       COALESCE(rm.content,'') AS reply_to_content,
			       m.created_at
			FROM messages m
			JOIN users u ON u.uid = m.sender_id
			LEFT JOIN messages rm ON rm.id = m.reply_to_message_id
			LEFT JOIN users ru ON ru.uid = rm.sender_id
			WHERE m.conversation_id = $1
			ORDER BY m.created_at DESC
			LIMIT $2
		`
		args = []any{conversationID, limit}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var msgs []model.Message
	for rows.Next() {
		var m model.Message
		if err := rows.Scan(&m.ID, &m.ConversationID, &m.SenderID, &m.SenderName,
			&m.Content, &m.MessageType, &m.MediaURL,
			&m.ReplyToMessageID, &m.ReplyToSender, &m.ReplyToContent,
			&m.CreatedAt); err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
	}

	// Reverse to chronological order
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}

	return msgs, nil
}

func (r *MessageRepo) Delete(ctx context.Context, id, senderID string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM messages WHERE id = $1 AND sender_id = $2`, id, senderID)
	return err
}
