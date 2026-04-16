package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"time"

	"tongxin-go/internal/config"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// ReferralService 邀请返佣 + 代理体系的业务逻辑层。
//
// 设计约束（来自 PRD v2）：
//   - Flag REFERRAL_ENABLED 默认关；关闭时所有写入短路，零 DB 影响
//   - 结算读 event.rate_snapshot（不读 users.my_rebate_rate），避免 admin
//     改 rate 影响已发生的历史 event
//   - 级联 cascade max 10 层，防御性深度限制
//   - 循环邀请检测：BindReferrer 调 GetInviterChain(10) 一次 SQL 跑完
type ReferralService struct {
	cfg  *config.Config
	repo *repository.ReferralRepo
}

func NewReferralService(cfg *config.Config, repo *repository.ReferralRepo) *ReferralService {
	return &ReferralService{cfg: cfg, repo: repo}
}

// maxCascadeDepth: 向上追溯级差时的最大层数。理论上代理链不会超过 4-5 层，
// 10 层是充分的防御性上限，同时让 GetInviterChain 一次 SQL 扫完。
const maxCascadeDepth = 10

// RecordCommissionEvent 在 trading 成功扣 fee 后异步调用：
//
//   input:  invitee 实付 fee；
//   output: 若干条 commission_events（pending or skipped_risk）写入 DB；
//
// 算法完全遵循 PRD §5.2：
//   1. invitee.inviter = Y → 若为 nil，直接 return（根用户，无人可分）
//   2. 写 direct event（rate_snapshot = Y.my_rebate_rate）
//   3. 沿链向上 ≤ 10 层：delta = max(0, cursor.rate - cursor_child_rate)，
//      delta > 0 写一条 override event，cursor_child_rate 单调递增
//   4. 所有 event 一次批量 INSERT（省 N-1 次 RTT）
//
// Flag off 时第一行 return nil，零 DB 操作。
//
// 风控：
//   - 直接 inviter 冻结 → direct event status='skipped_risk' 留存审计，不结算
//   - 链路中某层冻结 → 该层 override event 也标 skipped_risk；但 cursor_child_rate
//     仍然用它的 rate 推进，避免冻结代理的上级意外拿到冻结代理"本该"吃下的级差
func (s *ReferralService) RecordCommissionEvent(
	ctx context.Context,
	inviteeUID string,
	feeBase float64,
	productType string,
	sourceTxID string,
) error {
	if !s.cfg.ReferralEnabled {
		return nil
	}
	if feeBase <= 0 {
		return nil // 没有 fee 不产生 event
	}

	// Step 1: 直接 inviter
	invitee, err := s.repo.GetUserRebateInfo(ctx, inviteeUID)
	if err != nil {
		return fmt.Errorf("record: get invitee: %w", err)
	}
	if invitee.InviterUID == nil || *invitee.InviterUID == "" {
		return nil // 根用户，无人可分
	}

	// 一次查询捞完整条链（invitee 的 inviter → inviter 的 inviter → …）
	// maxCascadeDepth+1 因为 direct 层用不上级差，但 cursor 从 inviter.inviter 开始向上 10 层
	chain, err := s.repo.GetInviterChain(ctx, inviteeUID, maxCascadeDepth+1)
	if err != nil {
		return fmt.Errorf("record: chain: %w", err)
	}
	if len(chain) == 0 {
		return nil // 理论不会发生（inviter_uid 非 nil → 至少有 1 层）
	}

	var txIDPtr *string
	if sourceTxID != "" {
		txIDPtr = &sourceTxID
	}

	events := ComputeCascadeEvents(inviteeUID, chain, feeBase, productType, txIDPtr, maxCascadeDepth)

	// Step 4: 批量写
	if err := s.repo.InsertCommissionEvents(ctx, events); err != nil {
		return fmt.Errorf("record: insert events: %w", err)
	}
	return nil
}

// ComputeCascadeEvents 是 RecordCommissionEvent 的纯函数核心：
//   给定 invitee + 祖先链 + fee + productType，计算应该写入的所有 events。
//   不做任何 DB 调用，便于单测 6 个算法分支。
//   chain[0] = 直接 inviter；chain[1] = inviter 的 inviter；…
func ComputeCascadeEvents(
	inviteeUID string,
	chain []repository.UserRebateInfo,
	feeBase float64,
	productType string,
	sourceTxID *string,
	maxDepth int,
) []repository.InsertableEvent {
	if len(chain) == 0 || feeBase <= 0 {
		return nil
	}
	events := make([]repository.InsertableEvent, 0, len(chain))

	// Step 2: direct event
	direct := chain[0]
	directStatus := model.CommissionEventStatusPending
	if direct.IsFrozenReferral {
		directStatus = model.CommissionEventStatusSkippedRisk
	}
	events = append(events, repository.InsertableEvent{
		InviteeUID:          inviteeUID,
		InviterUID:          direct.UID,
		SourceInviterUID:    nil,
		Kind:                model.CommissionKindDirect,
		ProductType:         productType,
		FeeBase:             feeBase,
		RateSnapshot:        direct.MyRebateRate,
		CommissionAmount:    roundTo8(feeBase * direct.MyRebateRate),
		SourceTransactionID: sourceTxID,
		Status:              directStatus,
	})

	// Step 3: 向上级联（只走代理链）
	cursorChildRate := direct.MyRebateRate
	for i := 1; i < len(chain) && i <= maxDepth; i++ {
		parent := chain[i]
		if !parent.IsAgent {
			// 非代理：级差链断。根用户上面是 admin，本来就不发 event。
			break
		}
		delta := parent.MyRebateRate - cursorChildRate
		if delta > 0 {
			// source_inviter = 级差从哪个下级身上拿的（审计用）
			sourceInviter := direct.UID
			if i >= 2 {
				sourceInviter = chain[i-1].UID
			}
			status := model.CommissionEventStatusPending
			if parent.IsFrozenReferral {
				status = model.CommissionEventStatusSkippedRisk
			}
			events = append(events, repository.InsertableEvent{
				InviteeUID:          inviteeUID,
				InviterUID:          parent.UID,
				SourceInviterUID:    &sourceInviter,
				Kind:                model.CommissionKindOverride,
				ProductType:         productType,
				FeeBase:             feeBase,
				RateSnapshot:        delta,
				CommissionAmount:    roundTo8(feeBase * delta),
				SourceTransactionID: sourceTxID,
				Status:              status,
			})
		}
		if parent.MyRebateRate > cursorChildRate {
			cursorChildRate = parent.MyRebateRate
		}
	}

	return events
}

// RecordCommissionEventAsync 异步版：在独立 goroutine 里带 3 次重试 + DLQ。
// trading_service.go 的埋点应该调用此方法（非阻塞）。
//
// 策略：
//   - 最多 3 次，指数退避 200ms / 500ms / 1.2s
//   - 每次重试用独立 context（不继承请求 ctx，避免请求结束后 ctx 被取消）
//   - 3 次失败 → WriteToDLQ，留人工排查
func (s *ReferralService) RecordCommissionEventAsync(
	inviteeUID string,
	feeBase float64,
	productType string,
	sourceTxID string,
) {
	if !s.cfg.ReferralEnabled {
		return
	}

	go func() {
		backoffs := []time.Duration{200 * time.Millisecond, 500 * time.Millisecond, 1200 * time.Millisecond}
		var lastErr error
		for i := 0; i < len(backoffs); i++ {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			err := s.RecordCommissionEvent(ctx, inviteeUID, feeBase, productType, sourceTxID)
			cancel()
			if err == nil {
				return
			}
			lastErr = err
			if i < len(backoffs)-1 {
				time.Sleep(backoffs[i])
			}
		}

		// 3 次失败 → DLQ
		dlqCtx, dlqCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer dlqCancel()
		var txIDPtr *string
		if sourceTxID != "" {
			txIDPtr = &sourceTxID
		}
		payload, _ := json.Marshal(map[string]interface{}{
			"invitee_uid":  inviteeUID,
			"fee_base":     feeBase,
			"product_type": productType,
		})
		if dlqErr := s.repo.WriteToDLQ(dlqCtx, inviteeUID, feeBase, productType, txIDPtr, payload, lastErr.Error(), len(backoffs)); dlqErr != nil {
			log.Printf("[referral] record failed 3x, DLQ write also failed: record=%v dlq=%v", lastErr, dlqErr)
			return
		}
		log.Printf("[referral] record failed 3x, moved to DLQ: %v", lastErr)
	}()
}

// SettleDailyCommission 日结入口（scheduler 调用）：
//   对 target_date (UTC 日历日) 扫所有 pending events → 按 (inviter, kind) 聚合
//   → 逐组原子结算（applyCap 在此层统一应用）。
//
// Flag off：return 不做事。
func (s *ReferralService) SettleDailyCommission(ctx context.Context, targetDate time.Time) error {
	if !s.cfg.ReferralEnabled {
		return nil
	}

	// 固化到 UTC 日历日
	targetDate = time.Date(targetDate.Year(), targetDate.Month(), targetDate.Day(), 0, 0, 0, 0, time.UTC)

	groups, err := s.repo.ListPendingEventsForDate(ctx, targetDate)
	if err != nil {
		return fmt.Errorf("settle list: %w", err)
	}

	var settledCount, cappedCount, errorCount int
	for _, g := range groups {
		_, err := s.repo.SettleDailyForInviter(
			ctx,
			g.InviterUID,
			g.Kind,
			targetDate,
			g.EventIDs,
			g.TotalCommission,
			g.TotalFeeBase,
			s.cfg.DailyCommissionCapUSD,
		)
		if err != nil {
			if err == repository.ErrAlreadySettled {
				// 幂等：已经结过了，跳过
				continue
			}
			errorCount++
			log.Printf("[referral][settle] inviter=%s kind=%s date=%s FAILED: %v",
				g.InviterUID, g.Kind, targetDate.Format("2006-01-02"), err)
			continue
		}
		settledCount++
		if s.cfg.DailyCommissionCapUSD > 0 && g.TotalCommission > s.cfg.DailyCommissionCapUSD {
			cappedCount++
		}
	}

	log.Printf("[referral][settle] date=%s groups=%d settled=%d capped=%d errors=%d",
		targetDate.Format("2006-01-02"), len(groups), settledCount, cappedCount, errorCount)
	if errorCount > 0 {
		return fmt.Errorf("settle: %d groups failed", errorCount)
	}
	return nil
}

// BindReferrer 注册成功后绑定 inviter。
//
// 校验：
//   1. invite_code 非空且对应 invite_link is_active
//   2. inviter != self（DB CHECK 兜底，这里预检给更友好的错）
//   3. 不存在循环：inviter 的祖先链中不能出现 self（用 GetInviterChain 一次跑完）
//   4. 用户尚未绑定（SetUserInviter 的 WHERE inviter_uid IS NULL 兜底）
//
// 失败返回具体 error；handler 根据情况映射到 400 或 409；**不阻断注册**。
func (s *ReferralService) BindReferrer(ctx context.Context, newUID, inviteCode string) error {
	if !s.cfg.ReferralEnabled {
		return nil
	}
	if inviteCode == "" {
		return nil
	}

	link, err := s.repo.GetLinkByCode(ctx, inviteCode)
	if err != nil {
		return err // ErrInviteCodeNotFound / fmt error
	}
	if !link.IsActive {
		return repository.ErrInviteCodeNotFound
	}
	if link.OwnerUID == newUID {
		return repository.ErrSelfInvite
	}

	// 循环检测：跑 inviter 的祖先链，看看 self 是否出现
	chain, err := s.repo.GetInviterChain(ctx, link.OwnerUID, maxCascadeDepth)
	if err != nil {
		return fmt.Errorf("bind: chain check: %w", err)
	}
	for _, node := range chain {
		if node.UID == newUID {
			return repository.ErrCircularInvite
		}
	}

	if err := s.repo.SetUserInviter(ctx, newUID, link.OwnerUID); err != nil {
		return err
	}
	// 异步 +1 registration_count，失败不阻断
	_ = s.repo.IncrementRegistrationCount(ctx, inviteCode)
	return nil
}

// ValidateInviteCode 注册前校验（前端先调这条确认 code 可用）。
func (s *ReferralService) ValidateInviteCode(ctx context.Context, code string) error {
	if !s.cfg.ReferralEnabled {
		return nil // flag off 时静默通过，不报错
	}
	link, err := s.repo.GetLinkByCode(ctx, code)
	if err != nil {
		return err
	}
	if !link.IsActive {
		return repository.ErrInviteCodeNotFound
	}
	return nil
}

// ══════════════════════════════════════════════════════════════
// Agent application flow
// ══════════════════════════════════════════════════════════════

// ApplyForAgent 用户申请成为代理（可多次 retry，但同时只能有 1 条 pending）。
func (s *ReferralService) ApplyForAgent(
	ctx context.Context,
	applicantUID string,
	req *model.ApplyAgentRequest,
) (*model.AgentApplication, error) {
	if !s.cfg.ReferralEnabled {
		return nil, fmt.Errorf("referral feature disabled")
	}
	return s.repo.CreateAgentApplication(ctx, applicantUID, req.ChannelDescription, req.AudienceSize, req.ContactInfo)
}

// GetMyApplicationStatus 用户查自己的最新申请状态（pending > approved > rejected > none）。
func (s *ReferralService) GetMyApplicationStatus(ctx context.Context, uid string) (*model.AgentApplication, error) {
	// 优先返回 pending；没有则返回最新一条
	if pending, err := s.repo.GetActivePendingApplication(ctx, uid); err != nil {
		return nil, err
	} else if pending != nil {
		return pending, nil
	}
	apps, err := s.repo.ListAgentApplications(ctx, "", 1, 0)
	if err != nil {
		return nil, err
	}
	for _, a := range apps {
		if a.ApplicantUID == uid {
			return a, nil
		}
	}
	return nil, nil
}

// ApproveAgent admin 批准 + 填入初始 rate。
func (s *ReferralService) ApproveAgent(
	ctx context.Context,
	appID, reviewerUID string,
	proposedRate float64,
	note string,
) (*model.AgentApplication, error) {
	if !s.cfg.ReferralEnabled {
		return nil, fmt.Errorf("referral feature disabled")
	}
	if proposedRate < 0 || proposedRate > s.cfg.PlatformAgentMaxRate {
		return nil, repository.ErrRateOutOfBounds
	}
	return s.repo.ApproveApplication(ctx, appID, reviewerUID, proposedRate, note)
}

// RejectApplication admin 驳回。
func (s *ReferralService) RejectApplication(ctx context.Context, appID, reviewerUID, note string) error {
	if !s.cfg.ReferralEnabled {
		return fmt.Errorf("referral feature disabled")
	}
	return s.repo.RejectApplication(ctx, appID, reviewerUID, note)
}

// ══════════════════════════════════════════════════════════════
// Rate 管理
// ══════════════════════════════════════════════════════════════

// AdminSetUserRate admin 专用：改任意用户 rate。校验：
//   - 普通用户 rate > PlatformUserMaxRate 则拒绝（避免破坏"普通 ≤ 20%"不变量）
//     若 admin 想给 25% 必须先走代理批准流程
//   - 代理 rate ≤ PlatformAgentMaxRate（默认 1.0）
func (s *ReferralService) AdminSetUserRate(ctx context.Context, uid string, rate float64) error {
	if !s.cfg.ReferralEnabled {
		return fmt.Errorf("referral feature disabled")
	}
	if rate < 0 || rate > 1.0 {
		return repository.ErrRateOutOfBounds
	}
	// 读用户当前 is_agent 判断是否为普通用户
	info, err := s.repo.GetUserRebateInfo(ctx, uid)
	if err != nil {
		return err
	}
	if !info.IsAgent && rate > s.cfg.PlatformUserMaxRate {
		return fmt.Errorf("普通用户 rate 不能超过 %.0f%%，请先批准为代理：%w",
			s.cfg.PlatformUserMaxRate*100, repository.ErrRateOutOfBounds)
	}
	if info.IsAgent && rate > s.cfg.PlatformAgentMaxRate {
		return repository.ErrRateOutOfBounds
	}
	return s.repo.SetUserRate(ctx, uid, rate)
}

// AgentSetSubRate 代理给直接下级改 rate（必须 ≤ 自己 rate，repo 层 WHERE 校验）。
func (s *ReferralService) AgentSetSubRate(ctx context.Context, parentUID, targetUID string, rate float64) error {
	if !s.cfg.ReferralEnabled {
		return fmt.Errorf("referral feature disabled")
	}
	return s.repo.SetSubAgentRate(ctx, parentUID, targetUID, rate)
}

// AgentPromoteSub 代理把直接下级升级为子代理（is_agent=true + 设 rate）。
func (s *ReferralService) AgentPromoteSub(ctx context.Context, parentUID, targetUID string, rate float64) error {
	if !s.cfg.ReferralEnabled {
		return fmt.Errorf("referral feature disabled")
	}
	return s.repo.PromoteSubAgent(ctx, parentUID, targetUID, rate)
}

// AdminFreeze / AdminUnfreeze 代理冻结/解冻。
func (s *ReferralService) AdminSetFrozen(ctx context.Context, uid string, frozen bool) error {
	if !s.cfg.ReferralEnabled {
		return fmt.Errorf("referral feature disabled")
	}
	return s.repo.SetFrozenReferral(ctx, uid, frozen)
}

// ══════════════════════════════════════════════════════════════
// Dashboard / 读 API
// ══════════════════════════════════════════════════════════════

// GetOverview 所有用户「我的邀请」首页。
func (s *ReferralService) GetOverview(ctx context.Context, uid string) (*model.ReferralOverview, error) {
	lifetime, thisMonth, invCount, err := s.repo.GetOverviewMetrics(ctx, uid)
	if err != nil {
		return nil, err
	}
	info, err := s.repo.GetUserRebateInfo(ctx, uid)
	if err != nil {
		return nil, err
	}
	// 默认 invite_link（懒生成）
	link, err := s.repo.EnsureDefaultLink(ctx, uid)
	if err != nil {
		return nil, err
	}
	return &model.ReferralOverview{
		UID:                        uid,
		MyRebateRate:               info.MyRebateRate,
		IsAgent:                    info.IsAgent,
		LifetimeCommissionEarned:   lifetime,
		ThisMonthCommission:        thisMonth,
		TotalInvitees:              invCount,
		DefaultInviteCode:          link.Code,
		FeatureFlagReferralEnabled: s.cfg.ReferralEnabled,
	}, nil
}

// GetAgentDashboard 代理后台首页。
func (s *ReferralService) GetAgentDashboard(ctx context.Context, uid string) (*model.AgentDashboardSummary, error) {
	return s.repo.GetAgentDashboard(ctx, uid)
}

// ListMyInvitees 用户侧「我邀请的人」。
func (s *ReferralService) ListMyInvitees(ctx context.Context, uid string, limit, offset int) ([]repository.InviteeRow, int, error) {
	return s.repo.ListInvitees(ctx, uid, limit, offset)
}

// ListMyCommissionRecords 用户侧「返佣明细」分页。
func (s *ReferralService) ListMyCommissionRecords(
	ctx context.Context, uid, kind string, limit, offset int,
) ([]*model.CommissionRecord, int, error) {
	return s.repo.ListCommissionRecords(ctx, uid, kind, limit, offset)
}

// ListSubAgents 代理的下级列表（含本月贡献）。
func (s *ReferralService) ListSubAgents(ctx context.Context, parentUID string) ([]model.SubAgentRow, error) {
	return s.repo.ListSubAgents(ctx, parentUID)
}

// ListMyInviteLinks 邀请链接列表。
func (s *ReferralService) ListMyInviteLinks(ctx context.Context, ownerUID string) ([]*model.InviteLink, error) {
	return s.repo.ListLinksByOwner(ctx, ownerUID)
}

// CreateMyInviteLink 代理创建新邀请链接。
func (s *ReferralService) CreateMyInviteLink(
	ctx context.Context, ownerUID string, req *model.CreateInviteLinkRequest,
) (*model.InviteLink, error) {
	if !s.cfg.ReferralEnabled {
		return nil, fmt.Errorf("referral feature disabled")
	}
	return s.repo.CreateInviteLink(ctx, ownerUID, req.Code, req.Name, req.LandingPage)
}

// DisableMyInviteLink 代理禁用自己的邀请链接。
func (s *ReferralService) DisableMyInviteLink(ctx context.Context, ownerUID, linkID string) error {
	if !s.cfg.ReferralEnabled {
		return fmt.Errorf("referral feature disabled")
	}
	return s.repo.DisableLink(ctx, ownerUID, linkID)
}

// ══════════════════════════════════════════════════════════════
// helpers
// ══════════════════════════════════════════════════════════════

// roundTo8 按 8 位小数四舍五入（和 wallet 计算精度一致）。
func roundTo8(v float64) float64 {
	return math.Round(v*1e8) / 1e8
}
