package model

import "time"

type AssetDepositAddress struct {
	ID          string    `json:"id"`
	AccountType string    `json:"account_type"`
	AssetCode   string    `json:"asset_code"`
	Network     string    `json:"network"`
	Address     string    `json:"address"`
	Memo        string    `json:"memo,omitempty"`
	Provider    string    `json:"provider"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

type AssetDepositCallbackResult struct {
	DepositID     string  `json:"deposit_id,omitempty"`
	AccountType   string  `json:"account_type,omitempty"`
	AssetCode     string  `json:"asset_code,omitempty"`
	Network       string  `json:"network,omitempty"`
	Amount        float64 `json:"amount,omitempty"`
	TxHash        string  `json:"tx_hash,omitempty"`
	Status        string  `json:"status"`
	Credited      bool    `json:"credited"`
	Confirmations int     `json:"confirmations,omitempty"`
}

type AssetDepositRecord struct {
	ID            string     `json:"id"`
	AccountType   string     `json:"account_type"`
	AssetCode     string     `json:"asset_code"`
	Network       string     `json:"network"`
	Address       string     `json:"address"`
	Memo          string     `json:"memo,omitempty"`
	Amount        float64    `json:"amount"`
	Confirmations int        `json:"confirmations"`
	Status        string     `json:"status"`
	TxHash        string     `json:"tx_hash,omitempty"`
	CreditedAt    *time.Time `json:"credited_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
}

type CopySummaryItem struct {
	TraderUID         string    `json:"trader_uid"`
	TraderName        string    `json:"trader_name"`
	TraderAvatar      string    `json:"trader_avatar"`
	Status            string    `json:"status"`
	AllocatedCapital  float64   `json:"allocated_capital"`
	AvailableCapital  float64   `json:"available_capital"`
	FrozenCapital     float64   `json:"frozen_capital"`
	OpenPositionCount int       `json:"open_position_count"`
	UpdatedAt         time.Time `json:"updated_at"`
}

type CopySummaryResponse struct {
	TotalAllocated    float64           `json:"total_allocated"`
	TotalAvailable    float64           `json:"total_available"`
	TotalFrozen       float64           `json:"total_frozen"`
	// TotalUnrealizedPnl 聚合所有跟单仓位（is_copy_trade=true, status=open）的未实现盈亏。
	// 不再被错误地计入合约账户，而是单独展示在跟单账户视图。
	TotalUnrealizedPnl float64          `json:"total_unrealized_pnl"`
	ActiveTraderCount int               `json:"active_trader_count"`
	OpenPositionCount int               `json:"open_position_count"`
	Items             []CopySummaryItem `json:"items"`
}

type CopyAccountOverviewResponse struct {
	// TotalEquity = TotalAvailable + TotalFrozen + UnrealizedPnl。
	TotalEquity       float64 `json:"total_equity"`
	TotalAllocated    float64 `json:"total_allocated"`
	TotalAvailable    float64 `json:"total_available"`
	TotalFrozen       float64 `json:"total_frozen"`
	// UnrealizedPnl 当前所有跟单未平仓的浮盈浮亏之和（原本错误地归到合约账户）。
	UnrealizedPnl     float64 `json:"unrealized_pnl"`
	ActivePoolCount   int     `json:"active_pool_count"`
	CurrentPoolCount  int     `json:"current_pool_count"`
	OpenPositionCount int     `json:"open_position_count"`

	TodayRealizedPnl float64 `json:"today_realized_pnl"`
	TodayProfitShare float64 `json:"today_profit_share"`
	TodayNetPnl      float64 `json:"today_net_pnl"`

	LifetimeRealizedPnl float64 `json:"lifetime_realized_pnl"`
	LifetimeProfitShare float64 `json:"lifetime_profit_share"`
	LifetimeNetPnl      float64 `json:"lifetime_net_pnl"`
}

type CopyAccountPoolItem struct {
	CopyTradingID string `json:"copy_trading_id"`
	TraderUID     string `json:"trader_uid"`
	TraderName    string `json:"trader_name"`
	TraderAvatar  string `json:"trader_avatar"`
	Status        string `json:"status"`

	AllocatedCapital float64 `json:"allocated_capital"`
	AvailableCapital float64 `json:"available_capital"`
	FrozenCapital    float64 `json:"frozen_capital"`
	CurrentEquity    float64 `json:"current_equity"`

	OpenPositionCount int     `json:"open_position_count"`
	CurrentNetPnl     float64 `json:"current_net_pnl"`
	CurrentReturnRate float64 `json:"current_return_rate"`

	LifetimeRealizedPnl float64 `json:"lifetime_realized_pnl"`
	LifetimeProfitShare float64 `json:"lifetime_profit_share"`
	LifetimeNetPnl      float64 `json:"lifetime_net_pnl"`

	UpdatedAt time.Time `json:"updated_at"`
}

type CopyAccountPoolsResponse struct {
	Items       []CopyAccountPoolItem `json:"items"`
	TotalCount  int                   `json:"total_count"`
	ActiveCount int                   `json:"active_count"`
}

type CopyAccountOpenPositionItem struct {
	PositionID    string    `json:"position_id"`
	CopyTradingID string    `json:"copy_trading_id"`
	TraderUID     string    `json:"trader_uid"`
	TraderName    string    `json:"trader_name"`
	TraderAvatar  string    `json:"trader_avatar"`
	Symbol        string    `json:"symbol"`
	Side          string    `json:"side"`
	Qty           float64   `json:"qty"`
	EntryPrice    float64   `json:"entry_price"`
	CurrentPrice  float64   `json:"current_price"`
	MarginAmount  float64   `json:"margin_amount"`
	UnrealizedPnl float64   `json:"unrealized_pnl"`
	ROE           float64   `json:"roe"`
	Leverage      int       `json:"leverage"`
	OpenedAt      time.Time `json:"opened_at"`
}

type CopyAccountOpenPositionsResponse struct {
	Items      []CopyAccountOpenPositionItem `json:"items"`
	TotalCount int                           `json:"total_count"`
}

type CopyAccountHistoryItem struct {
	PositionID    string     `json:"position_id"`
	CopyTradingID string     `json:"copy_trading_id"`
	TraderUID     string     `json:"trader_uid"`
	TraderName    string     `json:"trader_name"`
	TraderAvatar  string     `json:"trader_avatar"`
	Symbol        string     `json:"symbol"`
	Side          string     `json:"side"`
	Qty           float64    `json:"qty"`
	EntryPrice    float64    `json:"entry_price"`
	ClosePrice    float64    `json:"close_price"`
	MarginAmount  float64    `json:"margin_amount"`
	GrossPnl      float64    `json:"gross_pnl"`
	OpenFee       float64    `json:"open_fee"`
	CloseFee      float64    `json:"close_fee"`
	ProfitShared  float64    `json:"profit_shared"`
	NetPnl        float64    `json:"net_pnl"`
	Result        string     `json:"result"`
	OpenedAt      time.Time  `json:"opened_at"`
	ClosedAt      *time.Time `json:"closed_at,omitempty"`
}

type CopyAccountHistoryResponse struct {
	Items      []CopyAccountHistoryItem `json:"items"`
	TotalCount int                      `json:"total_count"`
}

type AssetOverviewAccount struct {
	AccountType   string  `json:"account_type"`
	DisplayName   string  `json:"display_name"`
	Equity        float64 `json:"equity"`
	Available     float64 `json:"available"`
	Frozen        float64 `json:"frozen"`
	UnrealizedPnl float64 `json:"unrealized_pnl,omitempty"`
	MarginUsed    float64 `json:"margin_used,omitempty"`
	IsVirtual     bool    `json:"is_virtual,omitempty"`
}

type AssetTransaction struct {
	ID                  string    `json:"id"`
	Type                string    `json:"type"`
	Direction           string    `json:"direction"`
	Amount              float64   `json:"amount"`
	NetAmount           float64   `json:"net_amount"`
	BalanceAfter        float64   `json:"balance_after"`
	AccountType         string    `json:"account_type"`
	CounterpartyAccount string    `json:"counterparty_account_type,omitempty"`
	Status              string    `json:"status,omitempty"`
	Note                string    `json:"note,omitempty"`
	CreatedAt           time.Time `json:"created_at"`
}

type AssetPendingWithdrawal struct {
	ID             string    `json:"id"`
	Network        string    `json:"network"`
	Address        string    `json:"address"`
	Amount         float64   `json:"amount"`
	Status         string    `json:"status"`
	ProviderStatus string    `json:"provider_status,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

type AssetChangePoint struct {
	Date      string  `json:"date"`
	Label     string  `json:"label"`
	NetChange float64 `json:"net_change"`
	Equity    float64 `json:"equity"`
}

type AssetPnlCalendarDay struct {
	Date    string  `json:"date"`
	Day     int     `json:"day"`
	NetPnl  float64 `json:"net_pnl"`
	HasData bool    `json:"has_data"`
	IsToday bool    `json:"is_today"`
}

type AssetPnlCalendarResponse struct {
	Year         int                   `json:"year"`
	Month        int                   `json:"month"`
	MonthLabel   string                `json:"month_label"`
	Days         []AssetPnlCalendarDay `json:"days"`
	PositiveDays int                   `json:"positive_days"`
	NegativeDays int                   `json:"negative_days"`
	FlatDays     int                   `json:"flat_days"`
	NetPnl       float64               `json:"net_pnl"`
}

type AssetsOverviewResponse struct {
	Currency                string                   `json:"currency"`
	TotalEquity             float64                  `json:"total_equity"`
	TodayPnl                float64                  `json:"today_pnl"`
	TodayPnlRate            float64                  `json:"today_pnl_rate"`
	Accounts                []AssetOverviewAccount   `json:"accounts"`
	CopySummary             *CopySummaryResponse     `json:"copy_summary,omitempty"`
	PendingWithdrawals      []AssetPendingWithdrawal `json:"pending_withdrawals,omitempty"`
	PendingWithdrawalCount  int                      `json:"pending_withdrawal_count,omitempty"`
	PendingWithdrawalAmount float64                  `json:"pending_withdrawal_amount,omitempty"`
	RecentTransactions      []AssetTransaction       `json:"recent_transactions"`
	ChangeSeries            []AssetChangePoint       `json:"change_series"`
}

type AssetTransferRequest struct {
	FromAccount string  `json:"from_account"`
	ToAccount   string  `json:"to_account"`
	Amount      float64 `json:"amount"`
}

type AssetDepositRequest struct {
	Amount float64 `json:"amount"`
}

type AssetDepositAddressRequest struct {
	AssetCode string `json:"asset_code"`
	Network   string `json:"network"`
}

type AssetDepositNetworkOption struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

type AssetDepositAssetOption struct {
	AssetCode string                      `json:"asset_code"`
	Label     string                      `json:"label"`
	Networks  []AssetDepositNetworkOption `json:"networks"`
}

type AssetDepositResponse struct {
	AccountType   string  `json:"account_type"`
	Amount        float64 `json:"amount"`
	SpotAvailable float64 `json:"spot_available"`
	SpotFrozen    float64 `json:"spot_frozen"`
}

type AssetWithdrawRequest struct {
	Amount  float64 `json:"amount"`
	Address string  `json:"address"`
	Network string  `json:"network"`
}

type AssetWithdrawResponse struct {
	WithdrawalID  string  `json:"withdrawal_id"`
	AccountType   string  `json:"account_type"`
	Amount        float64 `json:"amount"`
	Address       string  `json:"address"`
	Network       string  `json:"network"`
	SpotAvailable float64 `json:"spot_available"`
	SpotFrozen    float64 `json:"spot_frozen"`
	Status        string  `json:"status"`
}

type AdminAssetWithdrawal struct {
	ID                    string     `json:"id"`
	UserID                string     `json:"user_id"`
	DisplayName           string     `json:"display_name"`
	Email                 string     `json:"email"`
	AssetCode             string     `json:"asset_code"`
	Network               string     `json:"network"`
	Address               string     `json:"address"`
	Amount                float64    `json:"amount"`
	Fee                   float64    `json:"fee"`
	Status                string     `json:"status"`
	Provider              string     `json:"provider,omitempty"`
	ProviderTradeID       string     `json:"provider_trade_id,omitempty"`
	ProviderTxID          string     `json:"provider_tx_id,omitempty"`
	ProviderStatus        string     `json:"provider_status,omitempty"`
	RejectReason          string     `json:"reject_reason,omitempty"`
	TxHash                string     `json:"tx_hash,omitempty"`
	ReviewedBy            string     `json:"reviewed_by,omitempty"`
	ReviewedAt            *time.Time `json:"reviewed_at,omitempty"`
	SubmittedToProviderAt *time.Time `json:"submitted_to_provider_at,omitempty"`
	CompletedAt           *time.Time `json:"completed_at,omitempty"`
	FailedAt              *time.Time `json:"failed_at,omitempty"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
}

type AssetTransferResponse struct {
	TransferID       string  `json:"transfer_id"`
	FromAccount      string  `json:"from_account"`
	ToAccount        string  `json:"to_account"`
	Amount           float64 `json:"amount"`
	MainAvailable    float64 `json:"main_available"`
	FuturesAvailable float64 `json:"futures_available"`
}

type SpotHoldingItem struct {
	Key                 string  `json:"key"`
	Category            string  `json:"category"`
	AssetCode           string  `json:"asset_code"`
	AssetName           string  `json:"asset_name"`
	IconURL             string  `json:"icon_url,omitempty"`
	BalanceTotal        float64 `json:"balance_total"`
	BalanceAvailable    float64 `json:"balance_available"`
	BalanceFrozen       float64 `json:"balance_frozen"`
	Price               float64 `json:"price"`
	AvgCost             float64 `json:"avg_cost"`
	CostEstimated       bool    `json:"cost_estimated"`
	Valuation           float64 `json:"valuation"`
	DailyChangeRate     float64 `json:"daily_change_rate"`
	UnrealizedPnl       float64 `json:"unrealized_pnl"`
	UnrealizedPnlRate   float64 `json:"unrealized_pnl_rate"`
	TodayRealizedPnl    float64 `json:"today_realized_pnl"`
	LifetimeRealizedPnl float64 `json:"lifetime_realized_pnl"`
	CurrentTotalPnl     float64 `json:"current_total_pnl"`
	IsDust              bool    `json:"is_dust"`
	CanDeposit          bool    `json:"can_deposit"`
	CanWithdraw         bool    `json:"can_withdraw"`
	CanTransfer         bool    `json:"can_transfer"`
}

type SpotHoldingsResponse struct {
	Items        []SpotHoldingItem `json:"items"`
	TotalCount   int               `json:"total_count"`
	VisibleCount int               `json:"visible_count"`
	OwnedCount   int               `json:"owned_count"`
}

type AssetIcon struct {
	ID          string    `json:"id,omitempty"`
	Category    string    `json:"category"`
	AssetCode   string    `json:"asset_code"`
	DisplayName string    `json:"display_name"`
	Source      string    `json:"source"`
	SourceID    string    `json:"source_id,omitempty"`
	RemoteURL   string    `json:"remote_url,omitempty"`
	LocalPath   string    `json:"local_path,omitempty"`
	ContentType string    `json:"content_type,omitempty"`
	ContentHash string    `json:"content_hash,omitempty"`
	Status      string    `json:"status"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type AssetIconTarget struct {
	Category    string `json:"category"`
	AssetCode   string `json:"asset_code"`
	DisplayName string `json:"display_name"`
}

type SpotTradeFill struct {
	AssetCode  string    `json:"asset_code"`
	AssetName  string    `json:"asset_name"`
	Category   string    `json:"category"`
	Symbol     string    `json:"symbol"`
	Side       string    `json:"side"`
	BaseQty    float64   `json:"base_qty"`
	QuoteQty   float64   `json:"quote_qty"`
	QuoteAsset string    `json:"quote_asset"`
	Fee        float64   `json:"fee"`
	FeeAsset   string    `json:"fee_asset"`
	FilledAt   time.Time `json:"filled_at"`
}
