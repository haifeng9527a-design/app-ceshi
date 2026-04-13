package model

import "time"

type Feedback struct {
	ID          string     `json:"id"`
	UserID      string     `json:"user_id"`
	DisplayName string     `json:"display_name,omitempty"`
	Content     string     `json:"content"`
	ImageURLs   []string   `json:"image_urls"`
	Category    string     `json:"category"`
	Status      string     `json:"status"`
	AdminReply  string     `json:"admin_reply"`
	RepliedBy   string     `json:"replied_by,omitempty"`
	RepliedAt   *time.Time `json:"replied_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

type CreateFeedbackRequest struct {
	Content   string   `json:"content"`
	ImageURLs []string `json:"image_urls"`
	Category  string   `json:"category"`
}

type AdminReplyRequest struct {
	Reply  string `json:"reply"`
	Status string `json:"status"`
}
