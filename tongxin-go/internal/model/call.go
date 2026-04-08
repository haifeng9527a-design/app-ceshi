package model

import "time"

type Call struct {
	ID             string     `json:"id"`
	ConversationID string     `json:"conversation_id"`
	InitiatorID    string     `json:"initiator_id"`
	RoomName       string     `json:"room_name"`
	CallType       string     `json:"call_type"`
	Status         string     `json:"status"`
	StartedAt      time.Time  `json:"started_at"`
	AnsweredAt     *time.Time `json:"answered_at,omitempty"`
	EndedAt        *time.Time `json:"ended_at,omitempty"`
	EndedBy        string     `json:"ended_by,omitempty"`
	EndReason      string     `json:"end_reason,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

type StartCallRequest struct {
	ConversationID string `json:"conversation_id"`
	CallType       string `json:"call_type,omitempty"`
}

type EndCallRequest struct {
	Reason string `json:"reason,omitempty"`
}

type LiveKitTokenResponse struct {
	ServerURL string `json:"server_url"`
	RoomName  string `json:"room_name"`
	Token     string `json:"token"`
	Identity  string `json:"identity"`
}
