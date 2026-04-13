package model

import "time"

// ── Equity Curve ──

type EquityPoint struct {
	Date          string  `json:"date"`
	DailyPnl      float64 `json:"daily_pnl"`
	CumulativePnl float64 `json:"cumulative_pnl"`
}

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
	IsFollowed       bool         `json:"is_followed"`
}

// ── User Follow (lightweight, independent of copy trading) ──

type UserFollow struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	TraderID  string    `json:"trader_id"`
	CreatedAt time.Time `json:"created_at"`
}

type FollowedTrader struct {
	UID              string       `json:"uid"`
	DisplayName      string       `json:"display_name"`
	AvatarURL        string       `json:"avatar_url"`
	IsTrader         bool         `json:"is_trader"`
	AllowCopyTrading bool         `json:"allow_copy_trading"`
	Stats            *TraderStats `json:"stats"`
	FollowedAt       time.Time    `json:"followed_at"`
	IsCopying        bool         `json:"is_copying"`
	CopyStatus       string       `json:"copy_status"`
}

// ── Copy Trading ──

type CopyTrading struct {
	ID              string    `json:"id"`
	FollowerID      string    `json:"follower_id"`
	TraderID        string    `json:"trader_id"`
	Status          string    `json:"status"` // active, paused, stopped
	CopyMode        string    `json:"copy_mode"`          // "fixed" or "ratio"
	CopyRatio       float64   `json:"copy_ratio"`
	FixedAmount     *float64  `json:"fixed_amount,omitempty"`
	MaxPosition     *float64  `json:"max_position,omitempty"`
	MaxSingleMargin *float64  `json:"max_single_margin,omitempty"`
	FollowSymbols   []string  `json:"follow_symbols"`     // empty = all
	LeverageMode    string    `json:"leverage_mode"`       // "trader" or "custom"
	CustomLeverage  *int      `json:"custom_leverage,omitempty"`
	TpSlMode        string    `json:"tp_sl_mode"`          // "trader" or "custom"
	CustomTpRatio   *float64  `json:"custom_tp_ratio,omitempty"`
	CustomSlRatio   *float64  `json:"custom_sl_ratio,omitempty"`
	FollowDirection string    `json:"follow_direction"`    // "both", "long", "short"
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
	// JOIN fields
	TraderName   string `json:"trader_name,omitempty"`
	TraderAvatar string `json:"trader_avatar,omitempty"`
}

type FollowTraderRequest struct {
	CopyMode        string   `json:"copy_mode"`
	CopyRatio       float64  `json:"copy_ratio"`
	FixedAmount     *float64 `json:"fixed_amount,omitempty"`
	MaxPosition     *float64 `json:"max_position,omitempty"`
	MaxSingleMargin *float64 `json:"max_single_margin,omitempty"`
	FollowSymbols   []string `json:"follow_symbols,omitempty"`
	LeverageMode    string   `json:"leverage_mode,omitempty"`
	CustomLeverage  *int     `json:"custom_leverage,omitempty"`
	TpSlMode        string   `json:"tp_sl_mode,omitempty"`
	CustomTpRatio   *float64 `json:"custom_tp_ratio,omitempty"`
	CustomSlRatio   *float64 `json:"custom_sl_ratio,omitempty"`
	FollowDirection string   `json:"follow_direction,omitempty"`
}

type CopyTradeLog struct {
	ID                 string    `json:"id"`
	CopyTradingID      string    `json:"copy_trading_id"`
	FollowerID         string    `json:"follower_id"`
	TraderID           string    `json:"trader_id"`
	Action             string    `json:"action"` // open, close, partial_close, skip
	SourceOrderID      *string   `json:"source_order_id,omitempty"`
	SourcePositionID   *string   `json:"source_position_id,omitempty"`
	FollowerOrderID    *string   `json:"follower_order_id,omitempty"`
	FollowerPositionID *string   `json:"follower_position_id,omitempty"`
	Symbol             string    `json:"symbol"`
	Side               string    `json:"side"`
	TraderQty          float64   `json:"trader_qty"`
	FollowerQty        float64   `json:"follower_qty"`
	TraderMargin       float64   `json:"trader_margin"`
	FollowerMargin     float64   `json:"follower_margin"`
	FollowerLeverage   int       `json:"follower_leverage"`
	RealizedPnl        float64   `json:"realized_pnl"`
	SkipReason         string    `json:"skip_reason,omitempty"`
	CreatedAt          time.Time `json:"created_at"`
	// JOIN fields
	TraderName   string `json:"trader_name,omitempty"`
	TraderAvatar string `json:"trader_avatar,omitempty"`
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
