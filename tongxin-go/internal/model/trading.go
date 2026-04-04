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
