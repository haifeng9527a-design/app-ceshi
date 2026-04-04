package market

import (
	"encoding/json"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// PolygonQuote holds a real-time quote from Polygon WebSocket
type PolygonQuote struct {
	Symbol       string
	Price        float64
	Open         float64
	High         float64
	Low          float64
	Volume       float64
	PrevClose    float64
	Change       float64
	ChangePct    float64
	Market       string // "stocks", "forex", "indices"
}

// PolygonWS connects to Polygon.io WebSocket for real-time stock/forex/index data
type PolygonWS struct {
	apiKey     string
	mu         sync.RWMutex
	stockConn  *websocket.Conn
	forexConn  *websocket.Conn
	subs       map[string]bool // currently subscribed symbols
	subsMu     sync.RWMutex
	Updates    chan PolygonQuote
	done       chan struct{}
}

func NewPolygonWS(apiKey string) *PolygonWS {
	return &PolygonWS{
		apiKey:  apiKey,
		subs:    make(map[string]bool),
		Updates: make(chan PolygonQuote, 512),
		done:    make(chan struct{}),
	}
}

func (p *PolygonWS) Start() {
	go p.connectLoop("stocks", "wss://delayed.polygon.io/stocks")
	go p.connectLoop("forex", "wss://socket.polygon.io/forex")
}

func (p *PolygonWS) Stop() {
	close(p.done)
}

// Subscribe dynamically subscribes to symbols on the active connections
func (p *PolygonWS) Subscribe(symbols []string) {
	p.subsMu.Lock()
	var stockSubs, forexSubs []string
	for _, sym := range symbols {
		if p.subs[sym] {
			continue
		}
		p.subs[sym] = true
		if strings.Contains(sym, "/") {
			// Forex: EUR/USD -> C.EURUSD
			forexSubs = append(forexSubs, sym)
		} else {
			stockSubs = append(stockSubs, sym)
		}
	}
	p.subsMu.Unlock()

	// Send subscription messages to active connections
	p.mu.RLock()
	if len(stockSubs) > 0 && p.stockConn != nil {
		params := buildStockSubParams(stockSubs)
		p.sendSub(p.stockConn, params)
		log.Printf("[polygon-ws-stocks] subscribing: %s", params)
	}
	if len(forexSubs) > 0 && p.forexConn != nil {
		params := buildForexSubParams(forexSubs)
		p.sendSub(p.forexConn, params)
		log.Printf("[polygon-ws-forex] subscribing: %s", params)
	}
	p.mu.RUnlock()
}

func (p *PolygonWS) connectLoop(market, url string) {
	for {
		select {
		case <-p.done:
			return
		default:
		}

		conn, _, err := websocket.DefaultDialer.Dial(url, nil)
		if err != nil {
			log.Printf("[polygon-ws-%s] connect error: %v, retrying in 5s", market, err)
			time.Sleep(5 * time.Second)
			continue
		}

		// Step 1: Wait for "connected" status message
		_, connMsg, err := conn.ReadMessage()
		if err != nil {
			log.Printf("[polygon-ws-%s] connect read error: %v", market, err)
			conn.Close()
			time.Sleep(5 * time.Second)
			continue
		}
		log.Printf("[polygon-ws-%s] server: %s", market, string(connMsg))

		// Step 2: Send auth
		authMsg, _ := json.Marshal(map[string]string{
			"action": "auth",
			"params": p.apiKey,
		})
		conn.WriteMessage(websocket.TextMessage, authMsg)

		// Step 3: Wait for auth response
		_, msg, err := conn.ReadMessage()
		if err != nil {
			log.Printf("[polygon-ws-%s] auth read error: %v", market, err)
			conn.Close()
			time.Sleep(5 * time.Second)
			continue
		}

		var authResp []struct {
			EV      string `json:"ev"`
			Status  string `json:"status"`
			Message string `json:"message"`
		}
		json.Unmarshal(msg, &authResp)

		authed := false
		for _, r := range authResp {
			if r.Status == "auth_success" {
				authed = true
				break
			}
		}
		if !authed {
			log.Printf("[polygon-ws-%s] auth failed: %s", market, string(msg))
			conn.Close()
			time.Sleep(10 * time.Second)
			continue
		}

		log.Printf("[polygon-ws-%s] authenticated", market)

		// Store connection
		p.mu.Lock()
		if market == "stocks" {
			p.stockConn = conn
		} else {
			p.forexConn = conn
		}
		p.mu.Unlock()

		// Re-subscribe all existing symbols for this market
		p.resubscribe(conn, market)

		// Read loop
		p.readMessages(conn, market)

		p.mu.Lock()
		if market == "stocks" {
			p.stockConn = nil
		} else {
			p.forexConn = nil
		}
		p.mu.Unlock()

		conn.Close()
		log.Printf("[polygon-ws-%s] disconnected, reconnecting in 3s", market)
		time.Sleep(3 * time.Second)
	}
}

func (p *PolygonWS) resubscribe(conn *websocket.Conn, market string) {
	p.subsMu.RLock()
	defer p.subsMu.RUnlock()

	var params []string
	for sym := range p.subs {
		isForex := strings.Contains(sym, "/")
		if market == "stocks" && !isForex {
			// Subscribe to trades: T.AAPL and aggregates: AM.AAPL
			params = append(params, "T."+sym, "AM."+sym)
		} else if market == "forex" && isForex {
			polygonSym := "C:" + strings.Replace(sym, "/", "", 1)
			params = append(params, "C."+polygonSym, "CA."+polygonSym)
		}
	}

	if len(params) > 0 {
		p.sendSub(conn, strings.Join(params, ","))
		log.Printf("[polygon-ws-%s] subscribed: %s", market, strings.Join(params, ","))
	}
}

func (p *PolygonWS) readMessages(conn *websocket.Conn, market string) {
	for {
		select {
		case <-p.done:
			return
		default:
		}

		_, msg, err := conn.ReadMessage()
		if err != nil {
			log.Printf("[polygon-ws-%s] read error: %v", market, err)
			return
		}

		var events []json.RawMessage
		if err := json.Unmarshal(msg, &events); err != nil {
			log.Printf("[polygon-ws-%s] unmarshal error: %v", market, err)
			continue
		}

		for _, raw := range events {
			var base struct {
				EV      string `json:"ev"`
				Status  string `json:"status"`
				Message string `json:"message"`
			}
			json.Unmarshal(raw, &base)

			switch base.EV {
			case "T": // Stock trade
				p.handleStockTrade(raw)
			case "AM": // Stock per-minute aggregate
				p.handleStockAggregate(raw)
			case "C": // Forex real-time quote (bid/ask tick)
				p.handleForexQuote(raw)
			case "CA": // Forex aggregate
				p.handleForexAggregate(raw)
			case "status":
				if base.Message != "" {
					log.Printf("[polygon-ws-%s] status: %s", market, base.Message)
				}
			default:
				log.Printf("[polygon-ws-%s] unknown event: %s", market, string(raw))
			}
		}
	}
}

// Stock trade event: immediate price update
func (p *PolygonWS) handleStockTrade(raw json.RawMessage) {
	var t struct {
		Symbol string  `json:"sym"`
		Price  float64 `json:"p"`
		Size   float64 `json:"s"`
	}
	if json.Unmarshal(raw, &t) != nil || t.Price == 0 {
		return
	}

	select {
	case p.Updates <- PolygonQuote{
		Symbol: t.Symbol,
		Price:  t.Price,
		Market: "stocks",
	}:
	default:
	}
}

// Stock per-minute aggregate: OHLCV
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
		Symbol: a.Symbol,
		Price:  a.Close,
		Open:   a.Open,
		High:   a.High,
		Low:    a.Low,
		Volume: a.Volume,
		Market: "stocks",
	}:
	default:
	}
}

// Forex real-time quote: bid/ask tick → mid price for instant updates
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
	displaySym := polygonForexToDisplay(q.Pair)

	select {
	case p.Updates <- PolygonQuote{
		Symbol: displaySym,
		Price:  mid,
		Market: "forex",
	}:
	default:
	}
}

// Forex aggregate
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

	// C:EURUSD -> EUR/USD
	displaySym := polygonForexToDisplay(a.Pair)

	select {
	case p.Updates <- PolygonQuote{
		Symbol: displaySym,
		Price:  a.Close,
		Open:   a.Open,
		High:   a.High,
		Low:    a.Low,
		Volume: a.Volume,
		Market: "forex",
	}:
	default:
	}
}

func (p *PolygonWS) sendSub(conn *websocket.Conn, params string) {
	msg, _ := json.Marshal(map[string]string{
		"action": "subscribe",
		"params": params,
	})
	conn.WriteMessage(websocket.TextMessage, msg)
}

func buildStockSubParams(symbols []string) string {
	var parts []string
	for _, s := range symbols {
		parts = append(parts, "T."+s, "AM."+s)
	}
	return strings.Join(parts, ",")
}

func buildForexSubParams(symbols []string) string {
	var parts []string
	for _, s := range symbols {
		polygonSym := "C:" + strings.Replace(s, "/", "", 1)
		parts = append(parts, "C."+polygonSym, "CA."+polygonSym)
	}
	return strings.Join(parts, ",")
}

func polygonForexToDisplay(pair string) string {
	// C:EURUSD -> EUR/USD, EURUSD -> EUR/USD
	pair = strings.TrimPrefix(pair, "C:")
	if len(pair) == 6 {
		return pair[:3] + "/" + pair[3:]
	}
	return pair
}
