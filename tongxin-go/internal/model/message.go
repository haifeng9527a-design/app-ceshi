package model

import (
	"encoding/json"
	"time"
)

type Message struct {
	ID               string          `json:"id"`
	ConversationID   string          `json:"conversation_id"`
	SenderID         string          `json:"sender_id"`
	SenderName       string          `json:"sender_name"`
	Content          string          `json:"content"`
	MessageType      string          `json:"message_type"` // text, image, video, audio, system_join, system_leave, teacher_share
	MediaURL         string          `json:"media_url,omitempty"`
	Metadata         json.RawMessage `json:"metadata,omitempty"` // JSON object: strategy cards, AI payloads
	ReplyToMessageID string          `json:"reply_to_message_id,omitempty"`
	ReplyToSender    string          `json:"reply_to_sender_name,omitempty"`
	ReplyToContent   string          `json:"reply_to_content,omitempty"`
	CreatedAt        time.Time       `json:"created_at"`
}

type SendMessageRequest struct {
	ConversationID string          `json:"conversation_id"`
	Content        string          `json:"content"`
	MessageType    string          `json:"message_type,omitempty"` // defaults to "text"
	MediaURL       string          `json:"media_url,omitempty"`
	Metadata       json.RawMessage `json:"metadata,omitempty"`
	ReplyToID      string          `json:"reply_to_message_id,omitempty"`
}
