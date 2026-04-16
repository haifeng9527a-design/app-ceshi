package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"time"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// ThresholdService 代理自定义阈值告警（Sprint 2）。
//
// 职责边界：
//   - CRUD：Upsert / List / Delete（handler 直接用）
//   - Scan：ScanAndFire(ctx) —— cron 每 10 分钟调用一次。
//     扫全部 enabled=true 阈值，计算当前指标值；命中则 notification.Create
//     （走 DB + WS 完整路径），并写 last_triggered_at 做 24h 防抖。
//
// 指标计算完全复用 ReferralRepo.GetRiskMetrics —— 避免同一个 metric 写两份 SQL。
// 唯一新增的是 lifetime_commission：直接从 users 表单行读取。
//
// 设计取舍：
//   - Evaluator 放在 service 层而不是 repo：因为业务语义（换算 drop 百分比 /
//     活跃人数减法）不属于纯 DB 访问
//   - 防抖窗口 = 24h：避免代理在 10 分钟刻度上被同一告警反复打扰
//   - 未命中时不重置 last_triggered_at：代理解除告警再触发会立即推送
type ThresholdService struct {
	repo         *repository.ThresholdRepo
	referralRepo *repository.ReferralRepo
	notificationSvc *NotificationService
}

func NewThresholdService(
	repo *repository.ThresholdRepo,
	referralRepo *repository.ReferralRepo,
	notificationSvc *NotificationService,
) *ThresholdService {
	return &ThresholdService{
		repo:            repo,
		referralRepo:    referralRepo,
		notificationSvc: notificationSvc,
	}
}

// dedupWindow 同一阈值两次触发的最小间隔。超过这个时间才会再次推送通知。
const dedupWindow = 24 * time.Hour

// Upsert 创建或更新阈值。校验 metric / op 合法性。
func (s *ThresholdService) Upsert(ctx context.Context, in *model.UpsertThresholdInput) (*model.AgentThreshold, error) {
	if !isSupportedMetric(in.Metric) {
		return nil, repository.ErrThresholdInvalidMetric
	}
	if in.Op != "lt" && in.Op != "gt" {
		return nil, repository.ErrThresholdInvalidOp
	}
	return s.repo.Upsert(ctx, in)
}

// List 当前 agent 的全部阈值规则。
func (s *ThresholdService) List(ctx context.Context, agentUID string) ([]*model.AgentThreshold, error) {
	return s.repo.ListByAgent(ctx, agentUID)
}

// Delete 删除阈值；若 id 不属于该 agent 返回 ErrThresholdNotFound。
func (s *ThresholdService) Delete(ctx context.Context, id, agentUID string) error {
	return s.repo.Delete(ctx, id, agentUID)
}

// ScanAndFire 供 cron 调用：扫全部 enabled 阈值，命中且未在防抖窗口内则推送通知。
//
// 返回 (scanned, fired, errors)。上层 log，不 abort 整个扫描。
func (s *ThresholdService) ScanAndFire(ctx context.Context) (int, int, []error) {
	all, err := s.repo.ListAllEnabled(ctx)
	if err != nil {
		return 0, 0, []error{fmt.Errorf("list enabled thresholds: %w", err)}
	}

	// 按 agentUID 分组缓存指标，避免同一 agent 多个 metric 走多次 SQL
	cache := make(map[string]*metricSnapshot)
	now := time.Now()
	fired := 0
	errs := make([]error, 0)

	for _, t := range all {
		// 防抖：24h 内已触发则跳过
		if t.LastTriggeredAt != nil && now.Sub(*t.LastTriggeredAt) < dedupWindow {
			continue
		}

		snap, cerr := s.getOrLoadSnapshot(ctx, t.AgentUID, cache)
		if cerr != nil {
			errs = append(errs, fmt.Errorf("load metrics uid=%s: %w", t.AgentUID, cerr))
			continue
		}

		value, ok := snap.metricValue(t.Metric)
		if !ok {
			// 未实现的 metric 或数据不可用 → 跳过，不当做错误
			continue
		}
		if !hit(t.Op, value, t.ThresholdValue) {
			continue
		}

		// 命中：推一条 notification，走完整 DB+WS 路径
		title, body, actionURL := renderThresholdAlert(t, value)
		payload, _ := json.Marshal(map[string]any{
			"threshold_id":    t.ID,
			"metric":          t.Metric,
			"op":              t.Op,
			"threshold_value": t.ThresholdValue,
			"actual_value":    value,
			"action_url":      actionURL,
		})

		if _, cerr := s.notificationSvc.Create(ctx, &model.CreateNotificationInput{
			UserUID: t.AgentUID,
			Kind:    "risk_alert",
			Title:   title,
			Body:    body,
			Payload: payload,
		}); cerr != nil {
			errs = append(errs, fmt.Errorf("create notification uid=%s metric=%s: %w", t.AgentUID, t.Metric, cerr))
			continue
		}

		if merr := s.repo.MarkTriggered(ctx, t.ID, now); merr != nil {
			errs = append(errs, fmt.Errorf("mark triggered id=%s: %w", t.ID, merr))
			// 不阻止计 fired：通知已经发出去了
		}
		fired++
	}

	return len(all), fired, errs
}

// ─── internals ───

// metricSnapshot 同一 agent 的一套指标缓存，供同一次 Scan 内的多个 threshold 复用。
type metricSnapshot struct {
	risk               *repository.RiskMetrics
	lifetimeCommission float64
}

// metricValue 把 threshold.metric 映射成当前可比较的数值。
// 未知 metric 返回 (_, false)，由调用方跳过。
func (m *metricSnapshot) metricValue(metric string) (float64, bool) {
	switch metric {
	case "active_invitees_7d":
		// 活跃下级人数 = 总下级 - 未活跃。ReferralRepo.RiskMetrics 给的是未活跃。
		return float64(m.risk.TotalInviteeCount - m.risk.InactiveInviteeCount), true
	case "pending_commission":
		return m.risk.PendingSelfRebateAmount, true
	case "month_volume_drop_pct":
		if m.risk.LastMonthCommission <= 0 {
			// 上月没数据不能算跌幅，返回 0（gt N 永远不命中）
			return 0, true
		}
		diff := m.risk.LastMonthCommission - m.risk.ThisMonthCommission
		if diff <= 0 {
			return 0, true // 本月已追平或超过，无跌幅
		}
		return diff / m.risk.LastMonthCommission * 100, true
	case "lifetime_commission":
		return m.lifetimeCommission, true
	default:
		return 0, false
	}
}

func (s *ThresholdService) getOrLoadSnapshot(
	ctx context.Context, agentUID string, cache map[string]*metricSnapshot,
) (*metricSnapshot, error) {
	if snap, ok := cache[agentUID]; ok {
		return snap, nil
	}
	risk, err := s.referralRepo.GetRiskMetrics(ctx, agentUID)
	if err != nil {
		return nil, err
	}
	// lifetime_commission 从 users 表直接读
	lifetime, err := s.referralRepo.GetLifetimeCommissionEarned(ctx, agentUID)
	if err != nil {
		// 非阻塞：读失败就 0，其他 metric 仍可评估
		log.Printf("[threshold-scan] load lifetime uid=%s: %v", agentUID, err)
		lifetime = 0
	}
	snap := &metricSnapshot{risk: risk, lifetimeCommission: lifetime}
	cache[agentUID] = snap
	return snap, nil
}

func hit(op string, actual, threshold float64) bool {
	switch op {
	case "lt":
		return actual < threshold
	case "gt":
		return actual > threshold
	default:
		return false
	}
}

func isSupportedMetric(m string) bool {
	for _, t := range model.SupportedThresholdMetrics {
		if t.Metric == m {
			return true
		}
	}
	return false
}

// renderThresholdAlert 把命中的阈值 + 当前值转成通知的 title / body / action_url。
// 中文文案贴合各 metric 语义。
func renderThresholdAlert(t *model.AgentThreshold, actual float64) (title, body, actionURL string) {
	switch t.Metric {
	case "active_invitees_7d":
		title = "7 天活跃下级告警"
		body = fmt.Sprintf("当前 7 天活跃下级 %d 人（阈值 %s %d）。建议一键触达激活。",
			int(actual), opText(t.Op), int(t.ThresholdValue))
		actionURL = "/sub-agents?filter=inactive_7d"
	case "pending_commission":
		title = "待结算返佣提醒"
		body = fmt.Sprintf("当前待结算返佣 %.2f USDT（阈值 %s %.2f），请留意日结。",
			actual, opText(t.Op), t.ThresholdValue)
		actionURL = "/commission-records?status=pending"
	case "month_volume_drop_pct":
		title = "月返佣环比下跌告警"
		body = fmt.Sprintf("本月返佣环比下跌 %.1f%%（阈值 %s %.1f%%）。建议分析团队活跃情况。",
			actual, opText(t.Op), t.ThresholdValue)
		actionURL = "/data-center"
	case "lifetime_commission":
		title = "累计返佣达成里程碑 🎉"
		body = fmt.Sprintf("累计返佣已到 %.2f USDT（阈值 %s %.2f）。",
			actual, opText(t.Op), t.ThresholdValue)
		actionURL = "/commission-records"
	default:
		title = "告警"
		body = fmt.Sprintf("指标 %s 当前值 %.2f 触发阈值 %s %.2f", t.Metric, actual, t.Op, t.ThresholdValue)
	}
	return
}

func opText(op string) string {
	switch op {
	case "lt":
		return "<"
	case "gt":
		return ">"
	default:
		return op
	}
}

// 静态断言：保留 errors 依赖，未来接入 multi-error 时保护
var _ = errors.New
