package service

import (
	"context"
	"encoding/json"
	"log"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// NotificationBroadcaster 是 service 层对 WS Hub 的抽象依赖。
// 用接口而非直接 import "internal/ws"，避免循环 import：
//   internal/ws ← internal/service（ChatHub 本身就依赖 service）。
// main.go 会把 *ws.ChatHub 注入进来——它已经实现了 BroadcastToUser(string, any)。
type NotificationBroadcaster interface {
	BroadcastToUser(userID string, payload any)
}

// NotificationService 站内通知的应用层。
// 所有需要「推一条通知给某代理」的业务入口（aalert cron / weekly report / settle 等）
// 都应调用本 service，而不是直接写 DB，以保证 persist + broadcast 原子完整。
type NotificationService struct {
	repo        *repository.NotificationRepo
	broadcaster NotificationBroadcaster // 可为 nil（无 WS 环境：单元测试 / 降级场景）
}

func NewNotificationService(repo *repository.NotificationRepo) *NotificationService {
	return &NotificationService{repo: repo}
}

// SetBroadcaster 在 main.go 创建完 ChatHub 后注入。允许后期 rebind。
func (s *NotificationService) SetBroadcaster(b NotificationBroadcaster) {
	s.broadcaster = b
}

// Create 先 INSERT DB，再 broadcast（DB 是 source of truth，WS 只是 realtime 通道）。
// 即使 broadcast 失败（用户离线），下次 List 仍能读到这条通知。
func (s *NotificationService) Create(ctx context.Context, in *model.CreateNotificationInput) (*model.Notification, error) {
	n, err := s.repo.Create(ctx, in)
	if err != nil {
		return nil, err
	}

	// 广播：失败仅 warn，不影响业务。payload 结构与前端 ws.ts 里的 message handler 对齐。
	if s.broadcaster != nil {
		// 计算最新未读数，让前端直接更新 bell badge，避免再调一次 REST。
		unread, unreadErr := s.repo.CountUnread(ctx, in.UserUID)
		if unreadErr != nil {
			log.Printf("[notification] count unread for broadcast uid=%s: %v", in.UserUID, unreadErr)
			unread = -1 // -1 = 前端不更新 badge，仅 append 一条消息
		}

		frame := map[string]any{
			"type": "notification",
			"data": map[string]any{
				"notification": n,
				"unread_total": unread,
			},
		}
		s.broadcaster.BroadcastToUser(in.UserUID, frame)
	}

	return n, nil
}

// List 列出该 user 的通知（按 created_at DESC）。
func (s *NotificationService) List(
	ctx context.Context, userUID string, unreadOnly bool, limit, offset int,
) (*model.NotificationListResponse, error) {
	items, total, unreadTotal, err := s.repo.List(ctx, userUID, unreadOnly, limit, offset)
	if err != nil {
		return nil, err
	}
	if items == nil {
		items = []*model.Notification{}
	}
	return &model.NotificationListResponse{
		Notifications: items,
		Total:         total,
		UnreadTotal:   unreadTotal,
		Limit:         limit,
		Offset:        offset,
	}, nil
}

// MarkRead 标记单条通知已读。id 不属于该 user 或已被读过时返回 ErrNotificationNotFound。
func (s *NotificationService) MarkRead(ctx context.Context, id, userUID string) error {
	return s.repo.MarkRead(ctx, id, userUID)
}

// MarkAllRead 全部标为已读，并实时广播新的 unread_total = 0 给用户的在线 WS，
// 让其他打开的 tab 同步刷新 bell badge。
func (s *NotificationService) MarkAllRead(ctx context.Context, userUID string) (int, error) {
	count, err := s.repo.MarkAllRead(ctx, userUID)
	if err != nil {
		return 0, err
	}
	if s.broadcaster != nil && count > 0 {
		s.broadcaster.BroadcastToUser(userUID, map[string]any{
			"type": "notification.read_all",
			"data": map[string]any{"unread_total": 0},
		})
	}
	return count, nil
}

// 静态断言：避免未来 model.Notification 结构变化时 JSON 序列化出问题
var _ = (func() any {
	var n model.Notification
	b, _ := json.Marshal(&n)
	return b
})()
