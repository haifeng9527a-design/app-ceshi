package model

import "time"

type Conversation struct {
	ID             string    `json:"id"`
	Type           string    `json:"type"` // "direct" or "group"
	Title          string    `json:"title,omitempty"`
	AvatarURL      string    `json:"avatar_url,omitempty"`
	CreatedBy      string    `json:"created_by,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	LastMessage    string    `json:"last_message,omitempty"`
	LastSenderName string    `json:"last_sender_name,omitempty"`
	LastTime       string    `json:"last_time,omitempty"`
	UnreadCount    int       `json:"unread_count"`
	PeerID         string    `json:"peer_id,omitempty"`
	PeerIsTrader   bool      `json:"peer_is_trader"`
}

type ConversationMember struct {
	ConversationID string    `json:"conversation_id"`
	UserID         string    `json:"user_id"`
	Role           string    `json:"role,omitempty"` // "admin", "member"
	JoinedAt       time.Time `json:"joined_at"`
}

type CreateDirectRequest struct {
	PeerID string `json:"peer_id"`
}

type CreateGroupRequest struct {
	Title     string   `json:"title"`
	MemberIDs []string `json:"member_ids"`
}
