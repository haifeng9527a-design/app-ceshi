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
	DefaultProfitShareRate float64    `json:"default_profit_share_rate"`
	LifetimeProfitSharedIn float64    `json:"lifetime_profit_shared_in"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

type RegisterRequest struct {
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	Password    string `json:"password"`
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
