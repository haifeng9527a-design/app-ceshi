package model

import (
	"encoding/json"
	"time"
)

// Notification 站内通知（migration 036）。
//
// 实时推送复用 ChatHub.BroadcastToUser，持久化保证用户离线后再上线
// 仍能在 Bell drawer 看到未读消息。
type Notification struct {
	ID        string          `json:"id"`
	UserUID   string          `json:"user_uid"`
	Kind      string          `json:"kind"` // 'risk_alert' | 'commission_settled' | 'weekly_report' | ...
	Title     string          `json:"title"`
	Body      string          `json:"body"`
	Payload   json.RawMessage `json:"payload,omitempty"`  // 关联 invitee_uid / event_id / png_url 等
	ReadAt    *time.Time      `json:"read_at,omitempty"`
	CreatedAt time.Time       `json:"created_at"`
}

// CreateNotificationInput 内部使用：service 层调用 NotificationService.Create 时的入参。
type CreateNotificationInput struct {
	UserUID string
	Kind    string
	Title   string
	Body    string
	Payload json.RawMessage // 可为 nil
}

// NotificationListResponse handler 层返回给前端的分页结构。
type NotificationListResponse struct {
	Notifications []*Notification `json:"notifications"`
	Total         int             `json:"total"`
	UnreadTotal   int             `json:"unread_total"`
	Limit         int             `json:"limit"`
	Offset        int             `json:"offset"`
}
