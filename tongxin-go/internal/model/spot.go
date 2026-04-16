package model

import "time"

// ── 枚举常量 ──

// SpotOrderSide
const (
	SpotSideBuy  = "buy"
	SpotSideSell = "sell"
)

// SpotOrderType
const (
	SpotOrderTypeMarket = "market"
	SpotOrderTypeLimit  = "limit"
)

// SpotOrderStatus
const (
	SpotOrderStatusPending   = "pending"
	SpotOrderStatusFilled    = "filled"
	SpotOrderStatusCancelled = "cancelled"
	SpotOrderStatusRejected  = "rejected"
)

// SpotSymbolCategory
const (
	SpotCategoryCrypto = "crypto"
	SpotCategoryStocks = "stocks"
)

// ── 数据模型 ──

// SpotOrder 对应 spot_orders 表。
type SpotOrder struct {
	ID            string     `json:"id"`
	UserID        string     `json:"user_id"`
	Symbol        string     `json:"symbol"`          // BTC/USDT, AAPL/USD
	BaseAsset     string     `json:"base_asset"`      // BTC, AAPL
	QuoteAsset    string     `json:"quote_asset"`     // USDT, USD
	Side          string     `json:"side"`            // buy / sell
	OrderType     string     `json:"order_type"`      // market / limit
	Qty           float64    `json:"qty"`             // 下单数量（基础资产）
	Price         *float64   `json:"price,omitempty"` // 限价价格
	FilledPrice   *float64   `json:"filled_price,omitempty"`
	FilledQty     float64    `json:"filled_qty"`
	QuoteQty      float64    `json:"quote_qty"` // = filled_qty × filled_price
	FrozenAmount  float64    `json:"frozen_amount"`
	Status        string     `json:"status"`
	Fee           float64    `json:"fee"`
	FeeAsset      string     `json:"fee_asset"`
	FeeRate       float64    `json:"fee_rate"`
	IsMaker       bool       `json:"is_maker"`
	RejectReason  string     `json:"reject_reason,omitempty"`
	ClientOrderID *string    `json:"client_order_id,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	FilledAt      *time.Time `json:"filled_at,omitempty"`
	CancelledAt   *time.Time `json:"cancelled_at,omitempty"`
}

// SpotFeeTier 对应 spot_fee_schedule 表。
type SpotFeeTier struct {
	VipLevel  int       `json:"vip_level"`
	MakerFee  float64   `json:"maker_fee"`
	TakerFee  float64   `json:"taker_fee"`
	UpdatedAt time.Time `json:"updated_at"`
}

// SpotSupportedSymbol 对应 spot_supported_symbols 表。
type SpotSupportedSymbol struct {
	Symbol         string  `json:"symbol"`
	BaseAsset      string  `json:"base_asset"`
	QuoteAsset     string  `json:"quote_asset"`
	Category       string  `json:"category"` // crypto / stocks
	DisplayName    string  `json:"display_name"`
	MinQty         float64 `json:"min_qty"`
	QtyPrecision   int     `json:"qty_precision"`
	PricePrecision int     `json:"price_precision"`
	IsActive       bool    `json:"is_active"`
	SortOrder      int     `json:"sort_order"`
}

// ── Request / Response DTOs ──

// SpotPlaceOrderRequest POST /api/spot/orders
type SpotPlaceOrderRequest struct {
	Symbol        string   `json:"symbol"`              // BTC/USDT
	Side          string   `json:"side"`                // buy / sell
	OrderType     string   `json:"order_type"`          // market / limit
	Qty           *float64 `json:"qty,omitempty"`       // 按数量下单（base asset）
	QuoteQty      *float64 `json:"quote_qty,omitempty"` // 按金额下单（quote asset），仅市价
	Price         *float64 `json:"price,omitempty"`     // 限价价格
	ClientOrderID *string  `json:"client_order_id,omitempty"`
}

// SpotAccountHolding 现货账户单个币种持仓
type SpotAccountHolding struct {
	Asset            string  `json:"asset"`
	Available        float64 `json:"available"`
	Frozen           float64 `json:"frozen"`
	ValuationUSDT    float64 `json:"valuation_usdt"` // 该币种估值（USDT）
	AvgBuyPrice      float64 `json:"avg_buy_price,omitempty"`
	UnrealizedPnL    float64 `json:"unrealized_pnl,omitempty"`
	UnrealizedPnLPct float64 `json:"unrealized_pnl_pct,omitempty"`
}

// SpotAccountInfo GET /api/spot/account
type SpotAccountInfo struct {
	UserID             string               `json:"user_id"`
	TotalValuationUSDT float64              `json:"total_valuation_usdt"`
	Holdings           []SpotAccountHolding `json:"holdings"`
}

type SpotAssetSnapshot struct {
	AssetCode       string  `json:"asset_code"`
	AssetName       string  `json:"asset_name"`
	Category        string  `json:"category"`
	Symbol          string  `json:"symbol"`
	QuoteAsset      string  `json:"quote_asset"`
	Price           float64 `json:"price"`
	DailyChangeRate float64 `json:"daily_change_rate"`
}

// SpotOrderListResponse GET /api/spot/orders
type SpotOrderListResponse struct {
	Orders []*SpotOrder `json:"orders"`
	Total  int          `json:"total"`
	Limit  int          `json:"limit"`
	Offset int          `json:"offset"`
}
