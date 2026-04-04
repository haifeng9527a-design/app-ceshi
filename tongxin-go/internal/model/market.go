package model

type Snapshot struct {
	Symbol    string  `json:"symbol"`
	Price     float64 `json:"price"`
	Change    float64 `json:"change"`
	ChangePct float64 `json:"change_pct"`
	Open      float64 `json:"open"`
	High      float64 `json:"high"`
	Low       float64 `json:"low"`
	Close     float64 `json:"close"`
	Volume    float64 `json:"volume"`
	PrevClose float64 `json:"prev_close"`
	Name      string  `json:"name,omitempty"`
}

type Candle struct {
	Timestamp int64   `json:"t"`
	Open      float64 `json:"o"`
	High      float64 `json:"h"`
	Low       float64 `json:"l"`
	Close     float64 `json:"c"`
	Volume    float64 `json:"v"`
}

type SearchResult struct {
	Symbol   string `json:"symbol"`
	Name     string `json:"name"`
	Type     string `json:"type"`
	Exchange string `json:"exchange,omitempty"`
}

type CryptoPrice struct {
	Symbol    string  `json:"symbol"`
	Price     float64 `json:"price"`
	Open24h   float64 `json:"open_24h"`
	Change24h float64 `json:"change_24h"`
	Volume24h float64 `json:"volume_24h"`
	High24h   float64 `json:"high_24h"`
	Low24h    float64 `json:"low_24h"`
}
