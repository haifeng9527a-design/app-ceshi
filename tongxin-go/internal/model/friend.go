package model

import "time"

type Friend struct {
	UserID    string    `json:"user_id"`
	FriendID  string    `json:"friend_id"`
	Status    string    `json:"status"` // pending, accepted, blocked
	CreatedAt time.Time `json:"created_at"`
}

type FriendRequest struct {
	ID         string    `json:"id"`
	FromUserID string    `json:"from_user_id"`
	ToUserID   string    `json:"to_user_id"`
	Status     string    `json:"status"` // pending, accepted, rejected
	Message    string    `json:"message,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type FriendProfile struct {
	UID         string `json:"uid"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	AvatarURL   string `json:"avatar_url,omitempty"`
	Role        string `json:"role,omitempty"`
	Status      string `json:"status,omitempty"`
	ShortID     string `json:"short_id,omitempty"`
}

type FriendRequestBody struct {
	ToUserID string `json:"to_user_id"`
	Message  string `json:"message,omitempty"`
}

type AcceptRejectBody struct {
	RequestID string `json:"request_id"`
}
