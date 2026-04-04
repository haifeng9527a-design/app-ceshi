package ws

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"tongxin-go/internal/market"
)

// PriceCallback is called on every price update with symbol and price.
type PriceCallback func(symbol string, price float64)

type MarketHub struct {
	clients       map[*Client]bool
	mu            sync.RWMutex
	polygon       *market.PolygonClient
	polygonWS     *market.PolygonWS
	binance       *market.BinanceIngestor
	done          chan struct{}
	onPriceUpdate PriceCallback
}

func NewMarketHub(polygon *market.PolygonClient, polygonWS *market.PolygonWS, binance *market.BinanceIngestor) *MarketHub {
	return &MarketHub{
		clients:   make(map[*Client]bool),
		polygon:   polygon,
		polygonWS: polygonWS,
		binance:   binance,
		done:      make(chan struct{}),
	}
}

func (h *MarketHub) HandleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[market-ws] upgrade error: %v", err)
		return
	}

	client := NewClient(conn, "anonymous")

	h.mu.Lock()
	h.clients[client] = true
	h.mu.Unlock()

	log.Printf("[market-ws] client connected (total: %d)", len(h.clients))

	client.SendJSON(map[string]string{"type": "connected"})

	go client.WritePump()
	client.ReadPump(h.onMessage)

	h.mu.Lock()
	delete(h.clients, client)
	h.mu.Unlock()

	log.Printf("[market-ws] client disconnected (total: %d)", len(h.clients))
}

type marketWSMsg struct {
	Type    string   `json:"type"`
	Symbols []string `json:"symbols,omitempty"`
}

func (h *MarketHub) onMessage(client *Client, raw []byte) {
	var msg marketWSMsg
	if err := json.Unmarshal(raw, &msg); err != nil {
		return
	}

	switch msg.Type {
	case "subscribe":
		for _, s := range msg.Symbols {
			client.Subscribe(s)
		}
		log.Printf("[market-ws] client subscribed: %v", msg.Symbols)
		client.SendJSON(map[string]any{
			"type":    "subscribed",
			"symbols": msg.Symbols,
		})

		// Forward non-crypto symbols to Polygon WebSocket for real-time streaming
		if h.polygonWS != nil {
			var polygonSyms []string
			for _, s := range msg.Symbols {
				if !isCryptoSymbol(s) {
					polygonSyms = append(polygonSyms, s)
				}
			}
			if len(polygonSyms) > 0 {
				h.polygonWS.Subscribe(polygonSyms)
			}
		}

	case "unsubscribe":
		for _, s := range msg.Symbols {
			client.Unsubscribe(s)
		}
	case "ping":
		client.SendJSON(map[string]string{"type": "pong"})
	}
}

// StartRealtime listens on Binance and Polygon update channels and pushes immediately
// Also runs REST fallback loops for stocks/forex/indices
func (h *MarketHub) StartRealtime() {
	go h.listenBinance()
	go h.listenPolygon()
	go h.restFallbackLoop()
	go h.forexFastLoop()
}

// listenBinance reads crypto price updates and pushes to clients instantly
func (h *MarketHub) listenBinance() {
	for {
		select {
		case <-h.done:
			return
		case cp := <-h.binance.Updates:
			displaySym := binanceToCryptoDisplay(cp.Symbol)
			change := cp.Price - cp.Open24h
			h.pushQuote(displaySym, map[string]any{
				"symbol":         displaySym,
				"price":          cp.Price,
				"close":          cp.Price,
				"open":           cp.Open24h,
				"change":         change,
				"percent_change": cp.Change24h,
				"prev_close":     cp.Open24h,
				"high":           cp.High24h,
				"low":            cp.Low24h,
				"volume":         cp.Volume24h,
			})

			// Drain remaining buffered updates for batch efficiency
		drain:
			for {
				select {
				case cp2 := <-h.binance.Updates:
					ds := binanceToCryptoDisplay(cp2.Symbol)
					ch2 := cp2.Price - cp2.Open24h
					h.pushQuote(ds, map[string]any{
						"symbol":         ds,
						"price":          cp2.Price,
						"close":          cp2.Price,
						"open":           cp2.Open24h,
						"change":         ch2,
						"percent_change": cp2.Change24h,
						"prev_close":     cp2.Open24h,
						"high":           cp2.High24h,
						"low":            cp2.Low24h,
						"volume":         cp2.Volume24h,
					})
				default:
					break drain
				}
			}
		}
	}
}

// listenPolygon reads stock/forex updates and pushes to clients instantly
func (h *MarketHub) listenPolygon() {
	if h.polygonWS == nil {
		return
	}
	for {
		select {
		case <-h.done:
			return
		case pq := <-h.polygonWS.Updates:
			h.pushQuote(pq.Symbol, map[string]any{
				"symbol":         pq.Symbol,
				"price":          pq.Price,
				"close":          pq.Price,
				"open":           pq.Open,
				"high":           pq.High,
				"low":            pq.Low,
				"volume":         pq.Volume,
				"change":         pq.Change,
				"percent_change": pq.ChangePct,
				"prev_close":     pq.PrevClose,
			})
		}
	}
}

// pushQuote sends a single quote to all clients subscribed to that symbol
func (h *MarketHub) pushQuote(symbol string, quote map[string]any) {
	// Trigger limit order check callback
	if h.onPriceUpdate != nil {
		if price, ok := quote["price"].(float64); ok && price > 0 {
			h.onPriceUpdate(symbol, price)
		}
	}

	msg := map[string]any{
		"type":           "quote",
		"symbol":         symbol,
		"price":          quote["price"],
		"close":          quote["price"],
		"open":           quote["open"],
		"high":           quote["high"],
		"low":            quote["low"],
		"volume":         quote["volume"],
		"change":         quote["change"],
		"percent_change": quote["percent_change"],
		"prev_close":     quote["prev_close"],
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	for client := range h.clients {
		if client.IsSubscribed(symbol) {
			client.Send(data)
		}
	}
}

// restFallbackLoop polls Polygon REST every 10s for stocks/indices
// This ensures data is available even when Polygon WS has no events (e.g. after-hours)
func (h *MarketHub) restFallbackLoop() {
	if h.polygon == nil {
		return
	}
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-h.done:
			return
		case <-ticker.C:
			h.broadcastStocksAndIndices()
		}
	}
}

// forexFastLoop polls forex every 3s for near real-time updates (forex is 24/5)
func (h *MarketHub) forexFastLoop() {
	if h.polygon == nil {
		return
	}
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-h.done:
			return
		case <-ticker.C:
			h.broadcastForex()
		}
	}
}

func (h *MarketHub) broadcastStocksAndIndices() {
	stockSyms := make(map[string]bool)
	indexSyms := make(map[string]bool)

	indexTickers := map[string]string{
		"DJI": "I:DJI", "SPX": "I:SPX", "IXIC": "I:COMP", "VIX": "I:VIX",
	}

	h.mu.RLock()
	for client := range h.clients {
		client.subsMu.RLock()
		for sym := range client.subs {
			if strings.Contains(sym, "/") {
				continue // forex/crypto handled separately
			} else if _, isIdx := indexTickers[sym]; isIdx {
				indexSyms[sym] = true
			} else if len(sym) > 0 && sym[0] >= 'A' && sym[0] <= 'Z' {
				stockSyms[sym] = true
			}
		}
		client.subsMu.RUnlock()
	}
	h.mu.RUnlock()

	if len(stockSyms) == 0 && len(indexSyms) == 0 {
		return
	}

	// Stocks batch
	if len(stockSyms) > 0 {
		syms := mapKeys(stockSyms)
		snaps, err := h.polygon.GetSnapshotParsed(syms)
		if err == nil {
			for sym, snap := range snaps {
				h.pushQuote(sym, snap)
			}
		}
	}

	// Indices
	for sym := range indexSyms {
		ticker := indexTickers[sym]
		snap, err := h.polygon.GetIndexSnapshot(ticker)
		if err == nil && snap != nil {
			snap["symbol"] = sym
			h.pushQuote(sym, snap)
		}
	}
}

func (h *MarketHub) broadcastForex() {
	forexSyms := make(map[string]bool)

	h.mu.RLock()
	for client := range h.clients {
		client.subsMu.RLock()
		for sym := range client.subs {
			if strings.Contains(sym, "/") && !isCryptoSymbol(sym) {
				forexSyms[sym] = true
			}
		}
		client.subsMu.RUnlock()
	}
	h.mu.RUnlock()

	if len(forexSyms) == 0 {
		return
	}

	for sym := range forexSyms {
		snap, err := h.polygon.GetForexSnapshot(sym)
		if err == nil && snap != nil {
			h.pushQuote(sym, snap)
		}
	}
}

// SetOnPriceUpdate sets a callback that is invoked on every price update.
func (h *MarketHub) SetOnPriceUpdate(cb PriceCallback) {
	h.onPriceUpdate = cb
}

func (h *MarketHub) Stop() {
	close(h.done)
}

// ─── Helpers ─────────────────────────────────

func binanceToCryptoDisplay(sym string) string {
	sym = strings.ToUpper(sym)
	if strings.HasSuffix(sym, "USDT") {
		return strings.TrimSuffix(sym, "USDT") + "/USD"
	}
	return sym
}

var cryptoBases = map[string]bool{
	"BTC": true, "ETH": true, "BNB": true, "SOL": true, "XRP": true,
	"DOGE": true, "ADA": true, "AVAX": true, "DOT": true, "MATIC": true,
	"LINK": true, "UNI": true, "SHIB": true, "LTC": true, "TRX": true,
	"ATOM": true, "NEAR": true, "APT": true, "ARB": true, "OP": true,
	"FIL": true, "ICP": true, "AAVE": true, "GRT": true, "MKR": true,
	"IMX": true, "INJ": true, "RUNE": true, "FTM": true, "ALGO": true,
	"XLM": true, "VET": true, "SAND": true, "MANA": true, "AXS": true,
	"THETA": true, "EOS": true, "IOTA": true, "XTZ": true, "FLOW": true,
	"CHZ": true, "CRV": true, "LDO": true, "SNX": true, "COMP": true,
	"ZEC": true, "DASH": true, "ENJ": true, "BAT": true, "1INCH": true,
	"SUSHI": true, "YFI": true, "ZRX": true, "KSM": true, "CELO": true,
	"QTUM": true, "ICX": true, "ONT": true, "ZIL": true, "WAVES": true,
	"ANKR": true, "SKL": true, "REN": true, "SRM": true, "DYDX": true,
	"MASK": true, "API3": true, "BAND": true, "OCEAN": true, "STORJ": true,
	"NKN": true, "SUI": true, "SEI": true, "TIA": true, "JUP": true,
	"WIF": true, "BONK": true, "PEPE": true, "FLOKI": true, "ORDI": true,
	"STX": true, "PYTH": true, "JTO": true, "BLUR": true, "STRK": true,
	"MEME": true, "WLD": true, "CYBER": true, "ARKM": true, "PENDLE": true,
	"GMX": true, "SSV": true, "RPL": true, "FXS": true, "OSMO": true,
	"KAVA": true, "CFX": true, "AGIX": true, "FET": true, "RNDR": true,
	"AR": true, "HNT": true, "ROSE": true, "USDT": true, "USDC": true,
	"DAI": true, "BCH": true, "ETC": true,
}

func isCryptoSymbol(sym string) bool {
	parts := strings.SplitN(sym, "/", 2)
	if len(parts) != 2 {
		return false
	}
	return cryptoBases[parts[0]]
}

func mapKeys(m map[string]bool) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

