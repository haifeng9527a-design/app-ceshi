package model

import "time"

type Wallet struct {
	UserID       string    `json:"user_id"`
	Balance      float64   `json:"balance"`
	Frozen       float64   `json:"frozen"`
	TotalDeposit float64   `json:"total_deposit"`
	UpdatedAt    time.Time `json:"updated_at"`
	CreatedAt    time.Time `json:"created_at"`
}

type Order struct {
	ID           string     `json:"id"`
	UserID       string     `json:"user_id"`
	Symbol       string     `json:"symbol"`
	Side         string     `json:"side"`
	OrderType    string     `json:"order_type"`
	Qty          float64    `json:"qty"`
	Price        *float64   `json:"price,omitempty"`
	FilledPrice  *float64   `json:"filled_price,omitempty"`
	Leverage     int        `json:"leverage"`
	MarginMode   string     `json:"margin_mode"`
	MarginAmount float64    `json:"margin_amount"`
	Status       string     `json:"status"`
	RejectReason string     `json:"reject_reason,omitempty"`
	Fee          float64    `json:"fee"`
	// Copy trade lineage
	IsCopyTrade    bool    `json:"is_copy_trade"`
	SourceOrderID  *string `json:"source_order_id,omitempty"`
	SourceTraderID *string `json:"source_trader_id,omitempty"`
	CopyTradingID  *string `json:"copy_trading_id,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	FilledAt     *time.Time `json:"filled_at,omitempty"`
	CancelledAt  *time.Time `json:"cancelled_at,omitempty"`
}

type Position struct {
	ID           string     `json:"id"`
	UserID       string     `json:"user_id"`
	Symbol       string     `json:"symbol"`
	Side         string     `json:"side"`
	Qty          float64    `json:"qty"`
	EntryPrice   float64    `json:"entry_price"`
	Leverage     int        `json:"leverage"`
	MarginMode   string     `json:"margin_mode"`
	MarginAmount float64    `json:"margin_amount"`
	LiqPrice     *float64   `json:"liq_price,omitempty"`
	TpPrice      *float64   `json:"tp_price,omitempty"`
	SlPrice      *float64   `json:"sl_price,omitempty"`
	Status       string     `json:"status"`
	RealizedPnl  float64    `json:"realized_pnl"`
	ClosePrice   float64    `json:"close_price,omitempty"`
	OpenFee      float64    `json:"open_fee"`
	CloseFee     float64    `json:"close_fee"`
	// Copy trade lineage
	IsCopyTrade      bool    `json:"is_copy_trade"`
	SourcePositionID *string `json:"source_position_id,omitempty"`
	SourceTraderID   *string `json:"source_trader_id,omitempty"`
	CopyTradingID    *string `json:"copy_trading_id,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	ClosedAt     *time.Time `json:"closed_at,omitempty"`
	// Computed fields (not stored in DB)
	UnrealizedPnl float64 `json:"unrealized_pnl"`
	CurrentPrice  float64 `json:"current_price"`
	ROE           float64 `json:"roe"`
}

type WalletTransaction struct {
	ID           string    `json:"id"`
	UserID       string    `json:"user_id"`
	Type         string    `json:"type"`
	Amount       float64   `json:"amount"`
	BalanceAfter float64   `json:"balance_after"`
	RefID        string    `json:"ref_id,omitempty"`
	Note         string    `json:"note,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

type AccountInfo struct {
	Balance       float64 `json:"balance"`
	Frozen        float64 `json:"frozen"`
	Equity        float64 `json:"equity"`
	MarginUsed    float64 `json:"margin_used"`
	Available     float64 `json:"available"`
	UnrealizedPnl float64 `json:"unrealized_pnl"`
}

type PlaceOrderRequest struct {
	Symbol     string   `json:"symbol"`
	Side       string   `json:"side"`
	Type       string   `json:"type"`
	Qty        float64  `json:"qty"`
	Price      *float64 `json:"price,omitempty"`
	Leverage   int      `json:"leverage"`
	MarginMode string   `json:"margin_mode"`
	TpPrice    *float64 `json:"tp_price,omitempty"`
	SlPrice    *float64 `json:"sl_price,omitempty"`
}

type DepositRequest struct {
	Amount float64 `json:"amount"`
}

type VipFeeRate struct {
	Level    int     `json:"level"`
	MakerFee float64 `json:"maker_fee"`
	TakerFee float64 `json:"taker_fee"`
}

type VipInfo struct {
	VipLevel int     `json:"vip_level"`
	MakerFee float64 `json:"maker_fee"`
	TakerFee float64 `json:"taker_fee"`
}

type FeeTier struct {
	ID        int       `json:"id"`
	VipLevel  int       `json:"vip_level"`
	MakerFee  float64   `json:"maker_fee"`
	TakerFee  float64   `json:"taker_fee"`
	MinVolume float64   `json:"min_volume"`
	UpdatedAt time.Time `json:"updated_at"`
	UpdatedBy string    `json:"updated_by,omitempty"`
}

type FeeStats struct {
	TodayFees float64 `json:"today_fees"`
	WeekFees  float64 `json:"week_fees"`
	MonthFees float64 `json:"month_fees"`
	TotalFees float64 `json:"total_fees"`
}

type PositionSummary struct {
	TotalOpen      int              `json:"total_open"`
	TotalMargin    float64          `json:"total_margin"`
	TotalUnrealPnl float64          `json:"total_unrealized_pnl"`
	BySymbol       []SymbolSummary  `json:"by_symbol"`
}

type SymbolSummary struct {
	Symbol      string  `json:"symbol"`
	Count       int     `json:"count"`
	TotalMargin float64 `json:"total_margin"`
}

type LiquidationStats struct {
	TotalCount int     `json:"total_count"`
	TotalLoss  float64 `json:"total_loss"`
	TodayCount int     `json:"today_count"`
	TodayLoss  float64 `json:"today_loss"`
}

type DailyRevenue struct {
	Date              string  `json:"date"`
	FeeIncome         float64 `json:"fee_income"`
	LiquidationIncome float64 `json:"liquidation_income"`
	TotalIncome       float64 `json:"total_income"`
	TradeCount        int     `json:"trade_count"`
	LiquidationCount  int     `json:"liquidation_count"`
	ActiveUsers       int     `json:"active_users"`
}

type RevenueSummary struct {
	Today   RevenueItem `json:"today"`
	Week    RevenueItem `json:"week"`
	Month   RevenueItem `json:"month"`
	AllTime RevenueItem `json:"all_time"`
}

type RevenueItem struct {
	FeeIncome         float64 `json:"fee_income"`
	LiquidationIncome float64 `json:"liquidation_income"`
	TotalIncome       float64 `json:"total_income"`
}

type ThirdPartyApi struct {
	ID             int        `json:"id"`
	ServiceName    string     `json:"service_name"`
	DisplayName    string     `json:"display_name"`
	Category       string     `json:"category"`
	BaseURL        string     `json:"base_url"`
	WsURL          string     `json:"ws_url"`
	ApiKey         string     `json:"api_key"`
	ApiSecret      string     `json:"api_secret"`
	ExtraConfig    any        `json:"extra_config"`
	IsActive       bool       `json:"is_active"`
	Description    string     `json:"description"`
	LastVerifiedAt *time.Time `json:"last_verified_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	UpdatedBy      string     `json:"updated_by,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
}

type ApiKeyHistoryEntry struct {
	ID           int       `json:"id"`
	ServiceName  string    `json:"service_name"`
	OldKeyMasked string    `json:"old_key_masked"`
	NewKeyMasked string    `json:"new_key_masked"`
	ChangedBy    string    `json:"changed_by"`
	ChangedAt    time.Time `json:"changed_at"`
	Reason       string    `json:"reason"`
}

type TradingOverview struct {
	OpenPositions     int     `json:"open_positions"`
	TodayVolume       float64 `json:"today_volume"`
	TodayFees         float64 `json:"today_fees"`
	TodayLiquidations int     `json:"today_liquidations"`
	ActiveTraders     int     `json:"active_traders"`
}

type AdminPosition struct {
	Position
	DisplayName string `json:"display_name"`
}

type AdminOrder struct {
	Order
	DisplayName string `json:"display_name"`
}

type AdminWallet struct {
	Wallet
	DisplayName string `json:"display_name"`
	Email       string `json:"email"`
}
