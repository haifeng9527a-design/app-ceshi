package model

import (
	"encoding/json"
	"time"
)

// ── 枚举常量 ──

// CommissionKind: commission_events.kind / commission_records.kind
const (
	CommissionKindDirect   = "direct"   // 直接返佣（invitee 的直接 inviter）
	CommissionKindOverride = "override" // 级差返佣（代理链上级拿的 delta）
)

// CommissionEventStatus: commission_events.status
const (
	CommissionEventStatusPending     = "pending"      // 等待日结
	CommissionEventStatusSettled     = "settled"      // 已入账
	CommissionEventStatusSkippedRisk = "skipped_risk" // 冻结代理，不结算
	CommissionEventStatusSkippedZero = "skipped_zero" // 级差 = 0，理论上不写，但保留字段
)

// CommissionRecordStatus: commission_records.status
const (
	CommissionRecordStatusSettled = "settled" // 全额入账
	CommissionRecordStatusCapped  = "capped"  // 触发日上限，部分入账
)

// ProductType: commission_events.product_type
const (
	ProductTypeFuturesOpen    = "futures_open"
	ProductTypeFuturesClose   = "futures_close"
	ProductTypeFuturesPartial = "futures_partial"
	ProductTypeFuturesTpsl    = "futures_tpsl"
	ProductTypeCopyOpen       = "copy_open"
	ProductTypeCopyClose      = "copy_close"
	ProductTypeSpot           = "spot"
	ProductTypeFunding        = "funding"
)

// AgentApplicationStatus: agent_applications.status
const (
	AgentApplicationStatusPending   = "pending"
	AgentApplicationStatusApproved  = "approved"
	AgentApplicationStatusRejected  = "rejected"
	AgentApplicationStatusCancelled = "cancelled"
)

// ── 数据模型 ──

// InviteLink 对应 invite_links 表。
// 每个用户注册后都有一条默认链接（code = short_id）；代理可以创建多条。
type InviteLink struct {
	ID                string    `json:"id"`
	OwnerUID          string    `json:"owner_uid"`
	Code              string    `json:"code"` // 邀请码，^[a-zA-Z0-9_]{3,20}$
	LandingPage       *string   `json:"landing_page,omitempty"`
	Name              string    `json:"name"`                // 展示名，例如 "Telegram 渠道"
	IsActive          bool      `json:"is_active"`           // 禁用后新注册拒绝
	RegistrationCount int       `json:"registration_count"`  // 通过此链接成功注册的用户数（异步聚合）
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

// CommissionEvent 对应 commission_events 表。
// 每笔 fee 扣除后异步产生 1 条 direct + 0..N 条 override。
type CommissionEvent struct {
	EventID             string     `json:"event_id"`
	InviteeUID          string     `json:"invitee_uid"`
	InviterUID          string     `json:"inviter_uid"`
	SourceInviterUID    *string    `json:"source_inviter_uid,omitempty"` // override 场景：级差从哪个下级身上拿
	Kind                string     `json:"kind"`                         // direct / override
	ProductType         string     `json:"product_type"`
	FeeBase             float64    `json:"fee_base"`              // invitee 实付手续费
	RateSnapshot        float64    `json:"rate_snapshot"`         // 事件产生时锁定的比例（direct=inviter.rate, override=delta）
	CommissionAmount    float64    `json:"commission_amount"`     // = fee_base × rate_snapshot
	SourceTransactionID *string    `json:"source_transaction_id,omitempty"` // wallet_transactions.id
	Status              string     `json:"status"`                // pending/settled/skipped_risk/skipped_zero
	CreatedAt           time.Time  `json:"created_at"`
	SettledAt           *time.Time `json:"settled_at,omitempty"`
}

// CommissionRecord 对应 commission_records 表。日结聚合审计。
type CommissionRecord struct {
	ID               string    `json:"id"`
	InviterUID       string    `json:"inviter_uid"`
	PeriodDate       time.Time `json:"period_date"` // DATE 类型，用 time.Time 接收（0 time zone）
	Kind             string    `json:"kind"`
	TotalFeeBase     float64   `json:"total_fee_base"`
	CommissionAmount float64   `json:"commission_amount"`
	EventCount       int       `json:"event_count"`
	Status           string    `json:"status"` // settled / capped
	CreatedAt        time.Time `json:"created_at"`
}

// AgentApplication 对应 agent_applications 表。
type AgentApplication struct {
	ID                  string          `json:"id"`
	ApplicantUID        string          `json:"applicant_uid"`
	Status              string          `json:"status"`
	ChannelDescription  string          `json:"channel_description"`
	AudienceSize        *int            `json:"audience_size,omitempty"`
	ContactInfo         json.RawMessage `json:"contact_info"` // JSONB：{telegram, email, ...}
	ProposedRate        *float64        `json:"proposed_rate,omitempty"`
	ReviewNote          string          `json:"review_note"`
	SubmittedAt         time.Time       `json:"submitted_at"`
	ReviewedAt          *time.Time      `json:"reviewed_at,omitempty"`
	ReviewedBy          *string         `json:"reviewed_by,omitempty"`
}

// ── Request / Response DTOs（handler 层用）──

// CreateInviteLinkRequest 代理创建新邀请链接。
type CreateInviteLinkRequest struct {
	Code        string  `json:"code"`
	Name        string  `json:"name"`
	LandingPage *string `json:"landing_page,omitempty"`
}

// ApplyAgentRequest 用户申请成为代理。
type ApplyAgentRequest struct {
	ChannelDescription string          `json:"channel_description"`
	AudienceSize       *int            `json:"audience_size,omitempty"`
	ContactInfo        json.RawMessage `json:"contact_info,omitempty"` // 原样透传到 JSONB
}

// ApproveAgentRequest admin 批准代理申请时填入初始 rate。
type ApproveAgentRequest struct {
	ProposedRate float64 `json:"proposed_rate"` // 0 ~ 1.0
	Note         string  `json:"note,omitempty"`
}

// SetRateRequest 通用改 rate（admin 改任意用户 / 代理改下级）。
type SetRateRequest struct {
	Rate float64 `json:"rate"` // 0 ~ 1.0
}

// ReferralOverview 用户端「我的邀请」首页概览。
type ReferralOverview struct {
	UID                      string  `json:"uid"`
	MyRebateRate             float64 `json:"my_rebate_rate"`
	IsAgent                  bool    `json:"is_agent"`
	LifetimeCommissionEarned float64 `json:"lifetime_commission_earned"`
	ThisMonthCommission      float64 `json:"this_month_commission"`
	TotalInvitees            int     `json:"total_invitees"`
	DefaultInviteCode        string  `json:"invite_code"` // 用户注册时就有的那一条
	// Feature flag 透传给前端决定是否显示入口
	FeatureFlagReferralEnabled bool `json:"feature_flag_referral_enabled"`
}

// AgentDashboardSummary 代理后台首页数据。
type AgentDashboardSummary struct {
	UID                      string  `json:"uid"`
	MyRebateRate             float64 `json:"my_rebate_rate"`
	LifetimeCommissionEarned float64 `json:"lifetime_commission_earned"`
	ThisMonthDirect          float64 `json:"this_month_direct"`
	ThisMonthOverride        float64 `json:"this_month_override"`
	DirectInvitees           int     `json:"direct_invitees"`
	SubAgentsCount           int     `json:"sub_agents_count"`
	IsFrozen                 bool    `json:"is_frozen"`
}

// SubAgentRow 代理的子代理列表一行。
type SubAgentRow struct {
	UID              string  `json:"uid"`
	DisplayName      string  `json:"display_name"`
	Email            string  `json:"email"`
	MyRebateRate     float64 `json:"my_rebate_rate"`
	IsAgent          bool    `json:"is_agent"`
	ThisMonthVolume  float64 `json:"this_month_volume"` // 本月总 fee base
	ContribToParent  float64 `json:"contrib_to_parent"` // 本月该子代理帮我产出的 override
	IsFrozenReferral bool    `json:"is_frozen_referral"`
}
