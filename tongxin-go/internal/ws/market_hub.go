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
	polygonWS     *market.PolygonWS // stocks WebSocket
	forexWS       *market.PolygonWS // forex WebSocket
	binance       *market.BinanceIngestor
	done          chan struct{}
	onPriceUpdate PriceCallback
}

func NewMarketHub(polygon *market.PolygonClient, polygonWS *market.PolygonWS, forexWS *market.PolygonWS, binance *market.BinanceIngestor) *MarketHub {
	return &MarketHub{
		clients:   make(map[*Client]bool),
		polygon:   polygon,
		polygonWS: polygonWS,
		forexWS:   forexWS,
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

		// Forward symbols to appropriate Polygon WebSocket
		var stockSyms, forexSyms []string
		for _, s := range msg.Symbols {
			if isCryptoSymbol(s) {
				continue
			}
			if strings.Contains(s, "/") {
				forexSyms = append(forexSyms, s)
			} else {
				stockSyms = append(stockSyms, s)
			}
		}
		if h.polygonWS != nil && len(stockSyms) > 0 {
			h.polygonWS.Subscribe(stockSyms)
		}
		if h.forexWS != nil && len(forexSyms) > 0 {
			h.forexWS.Subscribe(forexSyms)
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
// Also runs REST fallback loops for stocks/forex/indices/futures
func (h *MarketHub) StartRealtime() {
	go h.safeGo("listenBinance", h.listenBinance)
	go h.safeGo("listenPolygon", h.listenPolygon)
	go h.safeGo("listenForexWS", h.listenForexWS)
	go h.safeGo("restFallbackLoop", h.restFallbackLoop)
	go h.safeGo("forexFallbackLoop", h.forexFallbackLoop)
	go h.safeGo("futuresFallbackLoop", h.futuresFallbackLoop)
}

// safeGo wraps a function with panic recovery to prevent crashing the process.
func (h *MarketHub) safeGo(name string, fn func()) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[market-ws] PANIC in %s recovered: %v", name, r)
		}
	}()
	fn()
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

// buildPolygonQuoteMap constructs a quote payload that only includes fields
// the upstream actually provided. Tick-level messages (T.* trades, C.* forex
// quotes) carry only price, so sending zero for high/low/volume/etc. would
// overwrite the full OHLCV values previously stored by CAS/AM aggregates and
// cause visible flicker on the client.
func buildPolygonQuoteMap(pq market.PolygonQuote) map[string]any {
	q := map[string]any{
		"symbol": pq.Symbol,
		"price":  pq.Price,
		"close":  pq.Price,
	}
	if pq.Open != 0 {
		q["open"] = pq.Open
	}
	if pq.High != 0 {
		q["high"] = pq.High
	}
	if pq.Low != 0 {
		q["low"] = pq.Low
	}
	if pq.Volume != 0 {
		q["volume"] = pq.Volume
	}
	if pq.PrevClose != 0 {
		q["prev_close"] = pq.PrevClose
	}
	if pq.Change != 0 {
		q["change"] = pq.Change
	}
	if pq.ChangePct != 0 {
		q["percent_change"] = pq.ChangePct
	}
	return q
}

// listenPolygon reads stock updates and pushes to clients instantly
func (h *MarketHub) listenPolygon() {
	if h.polygonWS == nil {
		return
	}
	for {
		select {
		case <-h.done:
			return
		case pq := <-h.polygonWS.Updates:
			h.pushQuote(pq.Symbol, buildPolygonQuoteMap(pq))
		}
	}
}

// listenForexWS reads forex updates from the dedicated forex WebSocket
func (h *MarketHub) listenForexWS() {
	if h.forexWS == nil {
		return
	}
	for {
		select {
		case <-h.done:
			return
		case pq := <-h.forexWS.Updates:
			h.pushQuote(pq.Symbol, buildPolygonQuoteMap(pq))
		}
	}
}

// pushQuote sends a single quote to all clients subscribed to that symbol.
// Only fields that have meaningful values are forwarded: tick-level updates
// from Polygon carry price only, so explicitly emitting zero/nil for
// high/low/volume/open/prev_close would overwrite the good OHLCV values the
// client had previously merged from an aggregate (CAS/AM) message, producing
// visible flicker in the chart page's stats bar.
func (h *MarketHub) pushQuote(symbol string, quote map[string]any) {
	// Trigger limit order check callback
	if h.onPriceUpdate != nil {
		if price, ok := quote["price"].(float64); ok && price > 0 {
			h.onPriceUpdate(symbol, price)
		}
	}

	msg := map[string]any{
		"type":   "quote",
		"symbol": symbol,
	}
	// price / close must be a positive number to be meaningful.
	if v, ok := quote["price"]; ok && isPositiveNumber(v) {
		msg["price"] = v
		msg["close"] = v
	}
	// Prices and volume: skip zero / missing so that sparse tick messages
	// don't wipe the aggregate-derived fields on the client.
	for _, k := range []string{"open", "high", "low", "volume", "prev_close"} {
		if v, ok := quote[k]; ok && isPositiveNumber(v) {
			msg[k] = v
		}
	}
	// change / percent_change may legitimately be negative. Skip only when
	// the key is absent entirely (the client recomputes from price - prev_close).
	for _, k := range []string{"change", "percent_change"} {
		if v, ok := quote[k]; ok && isNonZeroNumber(v) {
			msg[k] = v
		}
	}
	// Pass through the market label if provided (stocks/forex/futures/crypto)
	if v, ok := quote["market"]; ok && v != nil {
		msg["market"] = v
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

// futuresFallbackLoop polls Polygon futures REST every 1s for real-time futures quotes.
// Futures use REST only (no WS) to avoid conflicts with the stocks WebSocket.
func (h *MarketHub) futuresFallbackLoop() {
	if h.polygon == nil {
		return
	}
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-h.done:
			return
		case <-ticker.C:
			h.broadcastFutures()
		}
	}
}

// broadcastFutures fetches and pushes futures quotes for all subscribed futures symbols.
func (h *MarketHub) broadcastFutures() {
	futuresSyms := make(map[string]bool)

	h.mu.RLock()
	for client := range h.clients {
		client.subsMu.RLock()
		for sym := range client.subs {
			if !strings.Contains(sym, "/") && market.IsFuturesSymbol(sym) {
				futuresSyms[sym] = true
			}
		}
		client.subsMu.RUnlock()
	}
	h.mu.RUnlock()

	if len(futuresSyms) == 0 {
		return
	}

	syms := mapKeys(futuresSyms)
	snaps, err := h.polygon.GetFuturesQuotes(syms)
	if err != nil {
		return
	}
	for sym, snap := range snaps {
		h.pushQuote(sym, snap)
	}
}

// forexFallbackLoop polls forex REST for real-time updates.
// Polygon forex WS may not push data on all plans, so REST is the primary source.
func (h *MarketHub) forexFallbackLoop() {
	if h.polygon == nil {
		return
	}
	ticker := time.NewTicker(1 * time.Second)
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
			} else if market.IsFuturesSymbol(sym) {
				continue // futures handled by futuresFallbackLoop
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

	// Fetch all forex tickers in one API call instead of one-by-one
	allSnaps, err := h.polygon.GetForexSnapshotAll()
	if err != nil {
		return
	}

	for sym := range forexSyms {
		if snap, ok := allSnaps[sym]; ok {
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

func isCryptoSymbol(sym string) bool {
	return market.IsCryptoSymbol(sym)
}

func mapKeys(m map[string]bool) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// isPositiveNumber returns true when v is a numeric value strictly greater
// than zero (used for prices and volume — zero means "unknown, don't send").
func isPositiveNumber(v any) bool {
	switch x := v.(type) {
	case float64:
		return x > 0
	case float32:
		return x > 0
	case int:
		return x > 0
	case int64:
		return x > 0
	}
	return false
}

// isNonZeroNumber returns true when v is a numeric value not equal to zero
// (used for change / percent_change where negatives are legitimate).
func isNonZeroNumber(v any) bool {
	switch x := v.(type) {
	case float64:
		return x != 0
	case float32:
		return x != 0
	case int:
		return x != 0
	case int64:
		return x != 0
	}
	return false
}

