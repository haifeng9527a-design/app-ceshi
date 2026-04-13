package market

import (
	"encoding/json"
	"log"
	"math"
	"math/rand"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

// PolygonQuote holds a real-time quote from Polygon WebSocket.
type PolygonQuote struct {
	Symbol    string
	Price     float64
	Open      float64
	High      float64
	Low       float64
	Volume    float64
	PrevClose float64
	Change    float64
	ChangePct float64
	Market    string // "stocks", "forex"
}

// ── Connection state ──

type connState int32

const (
	stateDisconnected connState = iota
	stateConnecting
	stateConnected
	stateStopped
)

func (s connState) String() string {
	switch s {
	case stateDisconnected:
		return "disconnected"
	case stateConnecting:
		return "connecting"
	case stateConnected:
		return "connected"
	case stateStopped:
		return "stopped"
	}
	return "unknown"
}

// ── Error classification ──

type errKind int

const (
	errNetwork   errKind = iota // transient
	errRateLimit                // rate/conn limit — longer backoff
	errAuth                     // permanent — stop
	errConnLimit                // account connection limit
)

func classifyError(err error, msg string) errKind {
	s := ""
	if err != nil {
		s = err.Error()
	}
	s += " " + msg
	lower := strings.ToLower(s)
	if strings.Contains(lower, "auth") && strings.Contains(lower, "fail") {
		return errAuth
	}
	if strings.Contains(lower, "connections exceeded") || strings.Contains(lower, "connection limit") || strings.Contains(lower, "1008") {
		return errConnLimit
	}
	if strings.Contains(lower, "429") || strings.Contains(lower, "too many") || strings.Contains(lower, "rate limit") {
		return errRateLimit
	}
	return errNetwork
}

// ── Constants ──

const (
	maxRetries    = 10
	baseBackoff   = 1 * time.Second
	maxBackoff    = 60 * time.Second
	subBatchDelay = 200 * time.Millisecond
	subBatchSize  = 20
)

// ── PolygonWS: Single-Connection Manager ──
//
// Architecture: exactly ONE WebSocket connection to Polygon.
// All subscriptions (stocks T.*, forex C.*) go through this single socket.
// The account only allows 1 concurrent WebSocket connection.

type PolygonWS struct {
	apiKey string
	wsURL  string
	market string // "stocks" or "forex"

	// ── Singleton connection ──
	conn    *websocket.Conn
	writeMu sync.Mutex   // serialize writes
	state   atomic.Int32 // connState

	// Single-flight reconnect
	reconnecting atomic.Bool

	// ── Subscription management ──
	subs     map[string]bool // all subscribed symbols (display format: "AAPL", "EUR/USD")
	subsMu   sync.RWMutex
	subQueue chan string // rate-limited param strings to send

	// ── Retry state ──
	consecutiveFailures int

	// ── Tracking which subscription types were acknowledged ──
	stockSubAcked atomic.Int32
	forexSubAcked atomic.Int32

	// ── Output ──
	Updates chan PolygonQuote
	done    chan struct{}
}

// NewPolygonWS creates a WebSocket manager for a specific Polygon endpoint.
// Use "stocks" or "forex" as market parameter.
func NewPolygonWS(apiKey, market string) *PolygonWS {
	var wsURL string
	switch market {
	case "forex":
		wsURL = "wss://socket.polygon.io/forex"
	default:
		wsURL = "wss://socket.polygon.io/stocks"
		market = "stocks"
	}
	p := &PolygonWS{
		apiKey:   apiKey,
		wsURL:    wsURL,
		market:   market,
		subs:     make(map[string]bool),
		subQueue: make(chan string, 256),
		Updates:  make(chan PolygonQuote, 512),
		done:     make(chan struct{}),
	}
	p.state.Store(int32(stateDisconnected))
	return p
}

func (p *PolygonWS) getState() connState { return connState(p.state.Load()) }
func (p *PolygonWS) setState(s connState) { p.state.Store(int32(s)) }
func (p *PolygonWS) logPrefix() string    { return "[polygon-ws:" + p.market + "]" }

// Start launches the connection loop and subscription queue worker.
func (p *PolygonWS) Start() {
	log.Printf("%s endpoint: %s", p.logPrefix(), p.wsURL)
	go p.subQueueWorker()
	go p.connectionLoop()
}

func (p *PolygonWS) Stop() {
	close(p.done)
	p.writeMu.Lock()
	if p.conn != nil {
		p.conn.Close()
	}
	p.writeMu.Unlock()
}

// ── Subscribe ──

// Subscribe adds symbols to this connection.
// Deduplicates and queues via rate-limited batch sender.
func (p *PolygonWS) Subscribe(symbols []string) {
	var newSyms []string

	p.subsMu.Lock()
	for _, sym := range symbols {
		if IsCryptoSymbol(sym) {
			continue
		}
		if p.subs[sym] {
			continue
		}
		p.subs[sym] = true
		newSyms = append(newSyms, sym)
	}
	p.subsMu.Unlock()

	if len(newSyms) == 0 {
		return
	}

	// Route to the correct builder based on market type
	if p.market == "forex" {
		p.queueBatches(newSyms, buildForexSubParams)
	} else {
		p.queueBatches(newSyms, buildStockSubParams)
	}
}

func (p *PolygonWS) queueBatches(symbols []string, builder func([]string) string) {
	for i := 0; i < len(symbols); i += subBatchSize {
		end := i + subBatchSize
		if end > len(symbols) {
			end = len(symbols)
		}
		params := builder(symbols[i:end])
		select {
		case p.subQueue <- params:
		case <-p.done:
			return
		}
	}
}

// subQueueWorker sends subscription messages with rate limiting.
func (p *PolygonWS) subQueueWorker() {
	for {
		select {
		case <-p.done:
			return
		case params := <-p.subQueue:
			if p.getState() != stateConnected {
				// Not connected — re-queue after delay
				go func(pp string) {
					time.Sleep(1 * time.Second)
					select {
					case p.subQueue <- pp:
					case <-p.done:
					}
				}(params)
				continue
			}

			msg, _ := json.Marshal(map[string]string{
				"action": "subscribe",
				"params": params,
			})
			p.writeMu.Lock()
			err := p.conn.WriteMessage(websocket.TextMessage, msg)
			p.writeMu.Unlock()

			if err != nil {
				log.Printf("[polygon-ws] subscribe send error: %v", err)
			} else {
				log.Printf("[polygon-ws] subscribe sent: %s", params)
			}
			time.Sleep(subBatchDelay)
		}
	}
}

// ── Connection lifecycle ──

func (p *PolygonWS) connectionLoop() {
	for {
		select {
		case <-p.done:
			return
		default:
		}

		if p.getState() == stateStopped {
			log.Println("[polygon-ws] permanently stopped, not reconnecting")
			return
		}

		// Single-flight: prevent concurrent reconnect
		if !p.reconnecting.CompareAndSwap(false, true) {
			log.Println("[polygon-ws] reconnect already in progress, skipping")
			return
		}

		stableConnection := p.connectOnce()
		p.reconnecting.Store(false)

		if p.getState() == stateStopped {
			return
		}

		// If connection was stable (>60s), reset failure counter
		if stableConnection {
			p.consecutiveFailures = 0
		} else {
			p.consecutiveFailures++
		}

		if p.consecutiveFailures >= maxRetries {
			log.Printf("[polygon-ws] FATAL: %d consecutive failures, stopping auto-reconnect", p.consecutiveFailures)
			p.setState(stateStopped)
			return
		}

		kind := errNetwork
		if p.consecutiveFailures > 0 {
			kind = errConnLimit // assume connection-related until proven otherwise
		}
		backoff := p.calcBackoff(p.consecutiveFailures, kind)
		log.Printf("[polygon-ws] reconnecting in %v (attempt %d/%d)", backoff, p.consecutiveFailures+1, maxRetries)

		select {
		case <-time.After(backoff):
		case <-p.done:
			return
		}
	}
}

// connectOnce dials, authenticates, subscribes, and reads until disconnect.
// Returns true if the connection was stable (lasted >60s).
func (p *PolygonWS) connectOnce() bool {
	p.setState(stateConnecting)
	log.Printf("[polygon-ws] connecting to %s ...", p.wsURL)
	log.Printf("[polygon-ws] websocket count: 1 (connecting)")

	// Step 1: Dial
	conn, _, err := websocket.DefaultDialer.Dial(p.wsURL, nil)
	if err != nil {
		p.setState(stateDisconnected)
		log.Printf("[polygon-ws] dial error: %v", err)
		return false
	}

	// Step 2: Read "connected" message
	_, msg, err := conn.ReadMessage()
	if err != nil {
		conn.Close()
		p.setState(stateDisconnected)
		log.Printf("[polygon-ws] read connected error: %v", err)
		return false
	}
	msgStr := string(msg)
	log.Printf("[polygon-ws] server: %s", msgStr)
	if kind := classifyError(nil, msgStr); kind == errConnLimit || kind == errAuth {
		conn.Close()
		p.setState(stateDisconnected)
		log.Printf("[polygon-ws] rejected by server")
		if kind == errAuth {
			p.setState(stateStopped)
		}
		return false
	}

	// Step 3: Auth
	authMsg, _ := json.Marshal(map[string]string{"action": "auth", "params": p.apiKey})
	if err := conn.WriteMessage(websocket.TextMessage, authMsg); err != nil {
		conn.Close()
		p.setState(stateDisconnected)
		log.Printf("[polygon-ws] send auth error: %v", err)
		return false
	}

	_, authResp, err := conn.ReadMessage()
	if err != nil {
		conn.Close()
		p.setState(stateDisconnected)
		log.Printf("[polygon-ws] read auth error: %v", err)
		return false
	}

	var authEvents []struct {
		Status  string `json:"status"`
		Message string `json:"message"`
	}
	json.Unmarshal(authResp, &authEvents)
	authed := false
	for _, r := range authEvents {
		if r.Status == "auth_success" {
			authed = true
			break
		}
	}
	if !authed {
		conn.Close()
		p.setState(stateDisconnected)
		log.Printf("[polygon-ws] FATAL: auth failed: %s — stopping", string(authResp))
		p.setState(stateStopped)
		return false
	}

	log.Println("[polygon-ws] authenticated successfully")
	connectedAt := time.Now()

	// Step 4: Store connection, mark connected
	p.writeMu.Lock()
	p.conn = conn
	p.writeMu.Unlock()
	p.setState(stateConnected)
	p.stockSubAcked.Store(0)
	p.forexSubAcked.Store(0)

	log.Printf("[polygon-ws] websocket count: 1 (connected)")

	// Step 5: Resubscribe all existing symbols
	p.resubscribeAll()

	// Step 6: Read loop (blocks)
	disconnectErr := p.readLoop()

	// Step 7: Cleanup
	p.writeMu.Lock()
	p.conn = nil
	p.writeMu.Unlock()
	conn.Close()
	p.setState(stateDisconnected)

	stable := time.Since(connectedAt) > 60*time.Second
	duration := time.Since(connectedAt).Round(time.Second)
	log.Printf("[polygon-ws] disconnected after %v (stable=%v)", duration, stable)
	log.Printf("[polygon-ws] websocket count: 0 (disconnected)")

	// Log ack summary
	log.Printf("[polygon-ws] session stats: stocks_acked=%d, forex_acked=%d",
		p.stockSubAcked.Load(), p.forexSubAcked.Load())

	if disconnectErr != nil {
		kind := classifyError(disconnectErr, "")
		switch kind {
		case errAuth:
			log.Println("[polygon-ws] FATAL: auth error during read, stopping")
			p.setState(stateStopped)
		case errConnLimit:
			log.Println("[polygon-ws] disconnected due to connection limit")
		default:
			log.Printf("[polygon-ws] read error: %v", disconnectErr)
		}
	}

	return stable
}

// resubscribeAll queues all existing subscriptions in batches.
func (p *PolygonWS) resubscribeAll() {
	p.subsMu.RLock()
	defer p.subsMu.RUnlock()

	var syms []string
	for sym := range p.subs {
		syms = append(syms, sym)
	}

	if len(syms) == 0 {
		return
	}

	log.Printf("%s resubscribing %d symbols", p.logPrefix(), len(syms))

	if p.market == "forex" {
		p.queueBatches(syms, buildForexSubParams)
	} else {
		p.queueBatches(syms, buildStockSubParams)
	}
}

// ── Read loop ──

func (p *PolygonWS) readLoop() error {
	for {
		select {
		case <-p.done:
			return nil
		default:
		}

		_, msg, err := p.conn.ReadMessage()
		if err != nil {
			return err
		}

		var events []json.RawMessage
		if err := json.Unmarshal(msg, &events); err != nil {
			continue
		}

		for _, raw := range events {
			p.handleEvent(raw)
		}
	}
}

// handleEvent dispatches a single event from the WebSocket.
func (p *PolygonWS) handleEvent(raw json.RawMessage) {
	var base struct {
		EV      string `json:"ev"`
		Status  string `json:"status"`
		Message string `json:"message"`
	}
	json.Unmarshal(raw, &base)

	switch base.EV {
	case "T":
		p.handleStockTrade(raw)
	case "A":
		// Stock aggregate per second — same format as AM
		p.handleStockAggregate(raw)
	case "AM":
		p.handleStockAggregate(raw)
	case "C":
		p.handleForexQuote(raw)
	case "CA":
		p.handleForexAggregate(raw)
	case "CAS":
		p.handleForexAggregate(raw)
	case "status":
		if base.Message != "" {
			// Track which subscription types get acknowledged
			if strings.HasPrefix(base.Message, "subscribed to:") {
				channel := strings.TrimPrefix(base.Message, "subscribed to: ")
				if strings.HasPrefix(channel, "T.") || strings.HasPrefix(channel, "AM.") {
					p.stockSubAcked.Add(1)
				} else if strings.HasPrefix(channel, "C.") || strings.HasPrefix(channel, "CA.") {
					p.forexSubAcked.Add(1)
				} else {
					log.Printf("[polygon-ws] ack: %s", base.Message)
				}
			} else {
				log.Printf("[polygon-ws] status: %s", base.Message)
				kind := classifyError(nil, base.Message)
				if kind == errConnLimit || kind == errRateLimit {
					log.Printf("[polygon-ws] ALERT: %s", base.Message)
				}
			}
		}
	}
}

// ── Backoff ──

func (p *PolygonWS) calcBackoff(failures int, kind errKind) time.Duration {
	var base time.Duration
	switch kind {
	case errAuth:
		return 0
	case errConnLimit:
		base = 30 * time.Second
	case errRateLimit:
		base = 10 * time.Second
	default:
		base = baseBackoff
	}
	delay := float64(base) * math.Pow(2, float64(failures))
	if delay > float64(maxBackoff) {
		delay = float64(maxBackoff)
	}
	jitter := delay * 0.25 * (rand.Float64()*2 - 1)
	result := time.Duration(delay + jitter)
	if result < baseBackoff {
		result = baseBackoff
	}
	return result
}

// ── Event handlers ──

func (p *PolygonWS) handleStockTrade(raw json.RawMessage) {
	var t struct {
		Symbol string  `json:"sym"`
		Price  float64 `json:"p"`
	}
	if json.Unmarshal(raw, &t) != nil || t.Price == 0 {
		return
	}
	select {
	case p.Updates <- PolygonQuote{Symbol: t.Symbol, Price: t.Price, Market: "stocks"}:
	default:
	}
}

func (p *PolygonWS) handleStockAggregate(raw json.RawMessage) {
	var a struct {
		Symbol string  `json:"sym"`
		Open   float64 `json:"o"`
		High   float64 `json:"h"`
		Low    float64 `json:"l"`
		Close  float64 `json:"c"`
		Volume float64 `json:"v"`
	}
	if json.Unmarshal(raw, &a) != nil || a.Close == 0 {
		return
	}
	select {
	case p.Updates <- PolygonQuote{
		Symbol: a.Symbol, Price: a.Close, Open: a.Open,
		High: a.High, Low: a.Low, Volume: a.Volume, Market: "stocks",
	}:
	default:
	}
}

func (p *PolygonWS) handleForexQuote(raw json.RawMessage) {
	var q struct {
		Pair string  `json:"p"`
		Ask  float64 `json:"a"`
		Bid  float64 `json:"b"`
	}
	if json.Unmarshal(raw, &q) != nil || (q.Ask == 0 && q.Bid == 0) {
		return
	}
	mid := (q.Ask + q.Bid) / 2
	select {
	case p.Updates <- PolygonQuote{Symbol: polygonForexToDisplay(q.Pair), Price: mid, Market: "forex"}:
	default:
	}
}

func (p *PolygonWS) handleForexAggregate(raw json.RawMessage) {
	var a struct {
		Pair   string  `json:"pair"`
		Open   float64 `json:"o"`
		High   float64 `json:"h"`
		Low    float64 `json:"l"`
		Close  float64 `json:"c"`
		Volume float64 `json:"v"`
	}
	if json.Unmarshal(raw, &a) != nil || a.Close == 0 {
		return
	}
	select {
	case p.Updates <- PolygonQuote{
		Symbol: polygonForexToDisplay(a.Pair), Price: a.Close, Open: a.Open,
		High: a.High, Low: a.Low, Volume: a.Volume, Market: "forex",
	}:
	default:
	}
}

// ── Helpers ──

func buildStockSubParams(symbols []string) string {
	var parts []string
	for _, s := range symbols {
		// T = trades, A = per-second agg, AM = per-minute agg
		parts = append(parts, "T."+s, "A."+s, "AM."+s)
	}
	return strings.Join(parts, ",")
}

func buildForexSubParams(symbols []string) string {
	var parts []string
	for _, s := range symbols {
		// Polygon forex WS uses {from}-{to} format, e.g. "EUR-USD"
		fxTicker := strings.Replace(s, "/", "-", 1)
		// C = quotes (tick-level), CA = per-minute agg, CAS = per-second agg
		parts = append(parts, "C."+fxTicker, "CA."+fxTicker, "CAS."+fxTicker)
	}
	return strings.Join(parts, ",")
}

func polygonForexToDisplay(pair string) string {
	pair = strings.TrimPrefix(pair, "C:")
	// Handle "EUR-USD" format from WS
	if strings.Contains(pair, "-") {
		return strings.Replace(pair, "-", "/", 1)
	}
	// Handle "EURUSD" format (6 chars, no separator)
	if len(pair) == 6 {
		return pair[:3] + "/" + pair[3:]
	}
	return pair
}

// IsCryptoSymbol checks if a symbol is a cryptocurrency pair (handled by Binance).
func IsCryptoSymbol(sym string) bool {
	parts := strings.SplitN(sym, "/", 2)
	if len(parts) != 2 {
		return false
	}
	return cryptoBases[parts[0]]
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
