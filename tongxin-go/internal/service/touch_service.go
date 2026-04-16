package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strings"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// TouchService「一键触达」业务层（Sprint 2）。
//
// 4 个渠道：
//   - internal：调 notification.Create，DB + WS 完整路径
//   - email：    stub（log），后期接 SMTP / Mailgun
//   - sms：      stub（log），后期接运营商网关
//   - wechat：   stub（log），后期接企业微信推送
//
// 同一次请求可以同时勾选多个渠道。service 会顺序执行每个渠道，
// 把每个渠道的结果拼成 TouchChannelResult，再根据成功/失败分布算整体 status：
//   - 全成功 → 'success'
//   - 全失败 → 'failed'
//   - 部分成功 → 'partial'
//
// touch_history 始终落一行——包括全失败的场景——以便运营回查。
type TouchService struct {
	repo            *repository.TouchRepo
	notificationSvc *NotificationService
	referralRepo    *repository.ReferralRepo
}

func NewTouchService(
	repo *repository.TouchRepo,
	notificationSvc *NotificationService,
	referralRepo *repository.ReferralRepo,
) *TouchService {
	return &TouchService{
		repo:            repo,
		notificationSvc: notificationSvc,
		referralRepo:    referralRepo,
	}
}

// validChannels / validTemplates：service 层白名单。
var validChannels = map[string]bool{
	"internal": true, "email": true, "sms": true, "wechat": true,
}

func isValidTemplate(t string) bool {
	for _, tmpl := range model.SupportedTouchTemplates {
		if tmpl.Key == t {
			return true
		}
	}
	return false
}

// Send 对一批下级、通过指定的多个渠道，按模板发送触达。
// agentUID 来自 JWT；service 会校验 invitee 必须是 agent 的直接下级（防越权）。
func (s *TouchService) Send(
	ctx context.Context,
	agentUID string,
	req *model.TouchRequest,
	channels []string,
) (*model.TouchResponse, error) {
	if agentUID == "" {
		return nil, errors.New("agent_uid required")
	}
	if req == nil || len(req.InviteeUIDs) == 0 {
		return nil, errors.New("invitee_uids required")
	}
	if !isValidTemplate(req.Template) {
		return nil, fmt.Errorf("unknown template: %s", req.Template)
	}
	if len(channels) == 0 {
		return nil, errors.New("at least one channel required")
	}
	for _, ch := range channels {
		if !validChannels[ch] {
			return nil, fmt.Errorf("invalid channel: %s", ch)
		}
	}

	// 防越权：所有 invitee 必须是 agent 的直接下级
	validUIDs, err := s.referralRepo.FilterDirectInvitees(ctx, agentUID, req.InviteeUIDs)
	if err != nil {
		return nil, fmt.Errorf("validate invitees: %w", err)
	}
	if len(validUIDs) == 0 {
		return nil, errors.New("no valid direct invitees in request")
	}

	tmpl := resolveTemplate(req.Template)
	body := req.CustomBody
	if body == "" {
		body = tmpl.DefaultBody
	}

	results := make([]model.TouchChannelResult, 0, len(channels))
	for _, ch := range channels {
		results = append(results, s.dispatch(ctx, ch, agentUID, validUIDs, tmpl, body))
	}

	status := aggregateStatus(results)

	payload, _ := json.Marshal(map[string]any{
		"custom_body":     req.CustomBody,
		"resolved_body":   body,
		"channel_results": results,
	})

	hist, err := s.repo.Insert(ctx, agentUID, validUIDs, req.Template, channels, payload, status)
	if err != nil {
		// 通知已经发出去了，只是历史写入失败——log 并返回部分响应
		log.Printf("[touch] history insert failed agent=%s: %v", agentUID, err)
		return &model.TouchResponse{
			HistoryID:      "",
			Status:         status,
			ChannelResults: results,
		}, nil
	}

	return &model.TouchResponse{
		HistoryID:      hist.ID,
		Status:         status,
		ChannelResults: results,
	}, nil
}

// List 代理自己触达历史（倒序）。
func (s *TouchService) List(ctx context.Context, agentUID string, limit int) ([]*model.TouchHistory, error) {
	return s.repo.List(ctx, agentUID, limit)
}

// ─── internals ───

func resolveTemplate(key string) *model.TouchTemplate {
	for i := range model.SupportedTouchTemplates {
		if model.SupportedTouchTemplates[i].Key == key {
			return &model.SupportedTouchTemplates[i]
		}
	}
	// 理论走不到（上面 isValidTemplate 已检）
	return &model.TouchTemplate{Title: "通知", DefaultBody: ""}
}

// dispatch 把一个渠道的实际发送收敛到一个方法，便于未来替换各 stub 为真实实现。
func (s *TouchService) dispatch(
	ctx context.Context,
	channel, agentUID string,
	inviteeUIDs []string,
	tmpl *model.TouchTemplate,
	body string,
) model.TouchChannelResult {
	switch channel {
	case "internal":
		return s.dispatchInternal(ctx, inviteeUIDs, tmpl, body)
	case "email":
		return dispatchStub("email", inviteeUIDs, tmpl.Title, body)
	case "sms":
		return dispatchStub("sms", inviteeUIDs, tmpl.Title, body)
	case "wechat":
		return dispatchStub("wechat", inviteeUIDs, tmpl.Title, body)
	default:
		return model.TouchChannelResult{Channel: channel, Success: false, ErrMessage: "unknown channel"}
	}
}

// dispatchInternal 站内通知：对每个 invitee 调 NotificationService.Create。
// 任意 1 人失败不影响其他人——分别计数。
func (s *TouchService) dispatchInternal(
	ctx context.Context, inviteeUIDs []string, tmpl *model.TouchTemplate, body string,
) model.TouchChannelResult {
	if s.notificationSvc == nil {
		return model.TouchChannelResult{
			Channel: "internal", Success: false, ErrMessage: "notification service not configured",
		}
	}
	succ := 0
	var lastErr error
	for _, uid := range inviteeUIDs {
		payload, _ := json.Marshal(map[string]any{
			"template":      tmpl.Key,
			"target_suffix": tmpl.TargetSuffix,
		})
		_, err := s.notificationSvc.Create(ctx, &model.CreateNotificationInput{
			UserUID: uid,
			Kind:    "touch_" + tmpl.Key,
			Title:   tmpl.Title,
			Body:    body,
			Payload: payload,
		})
		if err != nil {
			lastErr = err
			log.Printf("[touch-internal] send uid=%s: %v", uid, err)
			continue
		}
		succ++
	}
	res := model.TouchChannelResult{
		Channel: "internal",
		Success: succ > 0,
		Count:   succ,
	}
	if succ == 0 && lastErr != nil {
		res.ErrMessage = lastErr.Error()
	}
	return res
}

// dispatchStub 记录日志模拟发送；真实接入网关时替换此函数。
// 为了便于 demo 演示"成功"回执，这里永远 Success=true。
func dispatchStub(channel string, inviteeUIDs []string, title, body string) model.TouchChannelResult {
	log.Printf("[touch-%s] stub send to %d invitees title=%q body=%q targets=%s",
		channel, len(inviteeUIDs), title, truncate(body, 64), strings.Join(inviteeUIDs, ","))
	return model.TouchChannelResult{
		Channel: channel,
		Success: true,
		Count:   len(inviteeUIDs),
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

func aggregateStatus(results []model.TouchChannelResult) string {
	success, failed := 0, 0
	for _, r := range results {
		if r.Success {
			success++
		} else {
			failed++
		}
	}
	switch {
	case failed == 0:
		return "success"
	case success == 0:
		return "failed"
	default:
		return "partial"
	}
}
