package model

import "time"

type User struct {
	UID              string     `json:"uid"`
	Email            string     `json:"email"`
	DisplayName      string     `json:"display_name"`
	AvatarURL        string     `json:"avatar_url,omitempty"`
	Role             string     `json:"role,omitempty"`
	Status           string     `json:"status,omitempty"`
	ShortID          string     `json:"short_id,omitempty"`
	Phone            string     `json:"phone,omitempty"`
	Bio              string     `json:"bio,omitempty"`
	IsTrader         bool       `json:"is_trader"`
	IsSupportAgent   bool       `json:"is_support_agent"`
	AllowCopyTrading bool       `json:"allow_copy_trading"`
	TraderApprovedAt *time.Time `json:"trader_approved_at,omitempty"`
	VipLevel         int        `json:"vip_level"`
	// 跟单分润（trader 视角）
	// default_profit_share_rate：trader 设置的默认分润比例，新 follower 跟单时 snapshot 到 copy_trading 行
	// lifetime_profit_shared_in：trader 累计已收的分润总额（dashboard 直接读）
	DefaultProfitShareRate float64 `json:"default_profit_share_rate"`
	LifetimeProfitSharedIn float64 `json:"lifetime_profit_shared_in"`

	// 邀请返佣 + 代理体系（migration 031）
	// InviterUID                : 注册时绑定，终身不可改；nil 代表无邀请人
	// MyRebateRate              : 自己的返佣率；普通用户 ≤ 0.20，代理 ≤ 1.0
	// IsAgent                   : 是否代理身份
	// AgentApprovedAt           : 首次成为代理的时间
	// LifetimeCommissionEarned  : 累计返佣（UI 直接读）
	// IsFrozenReferral          : 风控冻结；冻结后新事件进入 skipped_risk，不结算
	InviterUID               *string    `json:"inviter_uid,omitempty"`
	MyRebateRate             float64    `json:"my_rebate_rate"`
	IsAgent                  bool       `json:"is_agent"`
	AgentApprovedAt          *time.Time `json:"agent_approved_at,omitempty"`
	LifetimeCommissionEarned float64    `json:"lifetime_commission_earned"`
	IsFrozenReferral         bool       `json:"is_frozen_referral"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type RegisterRequest struct {
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	Password    string `json:"password"`
	// InviteCode 可选；由前端注册表单传入或 deep-link `?ref=xxx` 自动填充。
	// 用指针以保持向后兼容（老客户端不传则为 nil，服务端跳过绑定）。
	InviteCode *string `json:"invite_code,omitempty"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AuthResponse struct {
	Token string `json:"token"`
	User  *User  `json:"user"`
}

type UpdateProfileRequest struct {
	DisplayName string `json:"display_name,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
	Bio         string `json:"bio,omitempty"`
	Phone       string `json:"phone,omitempty"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

type ChangeEmailRequest struct {
	NewEmail        string `json:"new_email"`
	CurrentPassword string `json:"current_password"`
}

type DeleteAccountCheckResponse struct {
	CanDelete bool     `json:"can_delete"`
	Reasons   []string `json:"reasons"`
}

type DeleteAccountRequest struct {
	CurrentPassword string `json:"current_password"`
}
