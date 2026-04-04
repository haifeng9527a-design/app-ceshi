package model

import "time"

// ── Trader Application ──

type TraderApplication struct {
	ID              string     `json:"id"`
	UserID          string     `json:"user_id"`
	Status          string     `json:"status"` // pending, approved, rejected
	RealName        string     `json:"real_name"`
	IDNumber        string     `json:"id_number"`
	Phone           string     `json:"phone"`
	Nationality     string     `json:"nationality"`
	Address         string     `json:"address"`
	ExperienceYears int        `json:"experience_years"`
	Markets         []string   `json:"markets"`
	CapitalSource   string     `json:"capital_source"`
	EstimatedVolume string     `json:"estimated_volume"`
	RiskAgreed      bool       `json:"risk_agreed"`
	TermsAgreed     bool       `json:"terms_agreed"`
	ReviewedBy      *string    `json:"reviewed_by,omitempty"`
	ReviewedAt      *time.Time `json:"reviewed_at,omitempty"`
	RejectionReason string     `json:"rejection_reason,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
	// JOIN fields
	DisplayName string `json:"display_name,omitempty"`
	Email       string `json:"email,omitempty"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

type SubmitApplicationRequest struct {
	RealName        string   `json:"real_name"`
	IDNumber        string   `json:"id_number"`
	Phone           string   `json:"phone"`
	Nationality     string   `json:"nationality"`
	Address         string   `json:"address"`
	ExperienceYears int      `json:"experience_years"`
	Markets         []string `json:"markets"`
	CapitalSource   string   `json:"capital_source"`
	EstimatedVolume string   `json:"estimated_volume"`
	RiskAgreed      bool     `json:"risk_agreed"`
	TermsAgreed     bool     `json:"terms_agreed"`
}

// ── Trader Stats ──

type TraderStats struct {
	UserID         string    `json:"user_id"`
	TotalTrades    int       `json:"total_trades"`
	WinTrades      int       `json:"win_trades"`
	TotalPnl       float64   `json:"total_pnl"`
	WinRate        float64   `json:"win_rate"`
	AvgPnl         float64   `json:"avg_pnl"`
	MaxDrawdown    float64   `json:"max_drawdown"`
	FollowersCount int       `json:"followers_count"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// ── Trader Profile (public) ──

type TraderProfile struct {
	UID              string       `json:"uid"`
	DisplayName      string       `json:"display_name"`
	AvatarURL        string       `json:"avatar_url"`
	IsTrader         bool         `json:"is_trader"`
	AllowCopyTrading bool         `json:"allow_copy_trading"`
	Stats            *TraderStats `json:"stats,omitempty"`
}

// ── Copy Trading ──

type CopyTrading struct {
	ID          string    `json:"id"`
	FollowerID  string    `json:"follower_id"`
	TraderID    string    `json:"trader_id"`
	Status      string    `json:"status"` // active, paused, stopped
	CopyRatio   float64   `json:"copy_ratio"`
	MaxPosition *float64  `json:"max_position,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	// JOIN fields
	TraderName   string `json:"trader_name,omitempty"`
	TraderAvatar string `json:"trader_avatar,omitempty"`
}

type FollowTraderRequest struct {
	CopyRatio   float64  `json:"copy_ratio"`
	MaxPosition *float64 `json:"max_position,omitempty"`
}

type ToggleCopyTradingRequest struct {
	Allow bool `json:"allow"`
}

type RejectApplicationRequest struct {
	Reason string `json:"reason"`
}

// ── Trader Ranking Item ──

type TraderRankingItem struct {
	UID              string  `json:"uid"`
	DisplayName      string  `json:"display_name"`
	AvatarURL        string  `json:"avatar_url"`
	TotalTrades      int     `json:"total_trades"`
	WinRate          float64 `json:"win_rate"`
	TotalPnl         float64 `json:"total_pnl"`
	AvgPnl           float64 `json:"avg_pnl"`
	MaxDrawdown      float64 `json:"max_drawdown"`
	FollowersCount   int     `json:"followers_count"`
	AllowCopyTrading bool    `json:"allow_copy_trading"`
}
