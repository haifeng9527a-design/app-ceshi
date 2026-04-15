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
	UID                    string       `json:"uid"`
	DisplayName            string       `json:"display_name"`
	AvatarURL              string       `json:"avatar_url"`
	IsTrader               bool         `json:"is_trader"`
	AllowCopyTrading       bool         `json:"allow_copy_trading"`
	DefaultProfitShareRate float64      `json:"default_profit_share_rate"`
	Stats                  *TraderStats `json:"stats,omitempty"`
	IsFollowed             bool         `json:"is_followed"`
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
	// 跟单分配本金（虚拟子账户）
	// allocated = available + frozen - 累计 realized_pnl + 累计 fee
	// 详见 migrations/025_copy_trading_allocated_capital.sql
	AllocatedCapital float64 `json:"allocated_capital" db:"allocated_capital"`
	AvailableCapital float64 `json:"available_capital" db:"available_capital"`
	FrozenCapital    float64 `json:"frozen_capital"    db:"frozen_capital"`
	// 跟单分润（HWM 高水位线算法）
	// 详见 migrations/027_copy_trading_profit_share.sql
	// profit_share_rate 在 FollowTrader 时从 trader 默认比例 snapshot 锁定，
	// trader 后续修改默认比例不影响存量 follower。
	ProfitShareRate        float64 `json:"profit_share_rate"        db:"profit_share_rate"`
	HighWaterMark          float64 `json:"high_water_mark"          db:"high_water_mark"`
	CumulativeNetDeposit   float64 `json:"cumulative_net_deposit"   db:"cumulative_net_deposit"`
	CumulativeProfitShared float64 `json:"cumulative_profit_shared" db:"cumulative_profit_shared"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
	// JOIN fields
	TraderName   string `json:"trader_name,omitempty"`
	TraderAvatar string `json:"trader_avatar,omitempty"`
}

type FollowTraderRequest struct {
	AllocatedCapital float64  `json:"allocated_capital"` // 必填，跟单分配本金（USDT）
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

// AdjustAllocatedCapitalRequest 用户追加 / 赎回跟单本金（delta>0 为追加，<0 为赎回）
type AdjustAllocatedCapitalRequest struct {
	Delta float64 `json:"delta"`
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
	UID                    string  `json:"uid"`
	DisplayName            string  `json:"display_name"`
	AvatarURL              string  `json:"avatar_url"`
	TotalTrades            int     `json:"total_trades"`
	WinRate                float64 `json:"win_rate"`
	TotalPnl               float64 `json:"total_pnl"`
	AvgPnl                 float64 `json:"avg_pnl"`
	MaxDrawdown            float64 `json:"max_drawdown"`
	FollowersCount         int     `json:"followers_count"`
	AllowCopyTrading       bool    `json:"allow_copy_trading"`
	DefaultProfitShareRate float64 `json:"default_profit_share_rate"`
}

// ── Profit Share (跟单分润) ──

// ProfitShareRecord 一条分润审计记录：每次平仓都写一条（包括 skip）。
type ProfitShareRecord struct {
	ID             string    `json:"id"`
	CreatedAt      time.Time `json:"created_at"`
	CopyTradingID  string    `json:"copy_trading_id"`
	FollowerUserID string    `json:"follower_user_id"`
	TraderUserID   string    `json:"trader_user_id"`
	PositionID     string    `json:"position_id"`
	GrossPnl       float64   `json:"gross_pnl"`
	CloseFee       float64   `json:"close_fee"`
	NetPnl         float64   `json:"net_pnl"`
	EquityBefore   float64   `json:"equity_before"`
	EquityAfter    float64   `json:"equity_after"`
	HwmBefore      float64   `json:"hwm_before"`
	HwmAfter       float64   `json:"hwm_after"`
	RateApplied    float64   `json:"rate_applied"`
	ShareAmount    float64   `json:"share_amount"`
	Status         string    `json:"status"` // settled / skipped_below_hwm / skipped_loss / skipped_zero_rate
	// JOIN fields (dashboard 用)
	FollowerName  string `json:"follower_name,omitempty"`
	PositionInfo  string `json:"position_info,omitempty"` // e.g. "BTCUSDT close"
}

// ProfitShareSummary 交易员 dashboard 顶部三卡片汇总。
type ProfitShareSummary struct {
	Lifetime         float64 `json:"lifetime"`           // 累计已收分润
	ThisMonth        float64 `json:"this_month"`         // 本月已收分润
	ActiveFollowers  int     `json:"active_followers"`   // 活跃跟随者人数
	DefaultShareRate float64 `json:"default_share_rate"` // 当前默认分润比例
}

// UpdateDefaultShareRateRequest trader 修改默认分润比例的入参。
type UpdateDefaultShareRateRequest struct {
	Rate float64 `json:"rate"` // 0.0000 ~ 0.2000
}
