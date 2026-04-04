package market

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"tongxin-go/internal/model"
)

type BinanceIngestor struct {
	prices   map[string]*model.CryptoPrice
	mu       sync.RWMutex
	done     chan struct{}
	watchSet map[string]bool // symbols to track (uppercase, e.g. "BTCUSDT")
	// Real-time update channel — MarketHub listens on this
	Updates chan model.CryptoPrice
}

func NewBinanceIngestor() *BinanceIngestor {
	return &BinanceIngestor{
		prices:   make(map[string]*model.CryptoPrice),
		done:     make(chan struct{}),
		watchSet: make(map[string]bool),
		Updates:  make(chan model.CryptoPrice, 256),
	}
}

func (b *BinanceIngestor) Start(symbols []string) {
	for _, s := range symbols {
		b.watchSet[strings.ToUpper(s)] = true
	}
	go b.connect()
}

func (b *BinanceIngestor) Stop() {
	close(b.done)
}

func (b *BinanceIngestor) GetPrices() []model.CryptoPrice {
	b.mu.RLock()
	defer b.mu.RUnlock()
	result := make([]model.CryptoPrice, 0, len(b.prices))
	for _, p := range b.prices {
		result = append(result, *p)
	}
	return result
}

func (b *BinanceIngestor) connect() {
	url := "wss://fstream.binance.com/stream?streams=!miniTicker@arr"

	for {
		select {
		case <-b.done:
			return
		default:
		}

		conn, _, err := websocket.DefaultDialer.Dial(url, nil)
		if err != nil {
			log.Printf("[binance-ws] connect error: %v, retrying in 5s", err)
			time.Sleep(5 * time.Second)
			continue
		}

		log.Printf("[binance-ws] connected to miniTicker stream, watching %d symbols", len(b.watchSet))
		b.readLoop(conn)
		conn.Close()
		log.Println("[binance-ws] disconnected, reconnecting in 3s")
		time.Sleep(3 * time.Second)
	}
}

type streamWrapper struct {
	Stream string            `json:"stream"`
	Data   []miniTickerEvent `json:"data"`
}

type miniTickerEvent struct {
	Symbol string `json:"s"`
	Close  string `json:"c"`
	Open   string `json:"o"`
	High   string `json:"h"`
	Low    string `json:"l"`
	Volume string `json:"v"`
}

func (b *BinanceIngestor) readLoop(conn *websocket.Conn) {
	for {
		select {
		case <-b.done:
			return
		default:
		}

		_, msg, err := conn.ReadMessage()
		if err != nil {
			return
		}

		var wrapper streamWrapper
		if err := json.Unmarshal(msg, &wrapper); err != nil {
			continue
		}

		b.mu.Lock()
		for _, t := range wrapper.Data {
			sym := strings.ToUpper(t.Symbol)
			if !b.watchSet[sym] {
				continue
			}

			price := parseFloat(t.Close)
			open := parseFloat(t.Open)
			high := parseFloat(t.High)
			low := parseFloat(t.Low)
			volume := parseFloat(t.Volume)

			var changePct float64
			if open > 0 {
				changePct = ((price - open) / open) * 100
			}

			cp := model.CryptoPrice{
				Symbol:    sym,
				Price:     price,
				Open24h:   open,
				Change24h: changePct,
				Volume24h: volume,
				High24h:   high,
				Low24h:    low,
			}
			b.prices[sym] = &cp

			// Non-blocking send to update channel
			select {
			case b.Updates <- cp:
			default:
				// channel full, skip (hub is slow)
			}
		}
		b.mu.Unlock()
	}
}

func parseFloat(s string) float64 {
	var f float64
	json.Unmarshal([]byte(s), &f)
	return f
}

// GetKlines fetches K-line/candlestick data from Binance REST API
// symbol: display format like "BTC/USD" → converted to "BTCUSDT"
// interval: "1m","5m","15m","30m","1h","4h","1d","1w","1M"
func (b *BinanceIngestor) GetKlines(symbol, interval string, from, to int64, limit int) ([]map[string]any, error) {
	binanceSym := displayToBinanceSymbol(symbol)
	if limit <= 0 {
		limit = 500
	}

	binanceInterval := convertToBinanceInterval(interval)
	url := fmt.Sprintf("https://fapi.binance.com/fapi/v1/klines?symbol=%s&interval=%s&limit=%d",
		binanceSym, binanceInterval, limit)
	if from > 0 {
		url += fmt.Sprintf("&startTime=%d", from)
	}
	if to > 0 {
		url += fmt.Sprintf("&endTime=%d", to)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, fmt.Errorf("binance klines request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("binance klines read error: %w", err)
	}

	// Binance returns: [[openTime, open, high, low, close, volume, closeTime, ...], ...]
	var raw [][]json.RawMessage
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, fmt.Errorf("binance klines parse error: %w", err)
	}

	bars := make([]map[string]any, 0, len(raw))
	for _, k := range raw {
		if len(k) < 6 {
			continue
		}
		var t int64
		var oStr, hStr, lStr, cStr, vStr string
		json.Unmarshal(k[0], &t)
		json.Unmarshal(k[1], &oStr)
		json.Unmarshal(k[2], &hStr)
		json.Unmarshal(k[3], &lStr)
		json.Unmarshal(k[4], &cStr)
		json.Unmarshal(k[5], &vStr)

		bars = append(bars, map[string]any{
			"t": t,
			"o": parseFloat(oStr),
			"h": parseFloat(hStr),
			"l": parseFloat(lStr),
			"c": parseFloat(cStr),
			"v": parseFloat(vStr),
		})
	}

	return bars, nil
}

// GetPrice returns the latest price for a display symbol like "BTC/USD"
func (b *BinanceIngestor) GetPrice(displaySymbol string) (float64, error) {
	binanceSym := displayToBinanceSymbol(displaySymbol)
	b.mu.RLock()
	defer b.mu.RUnlock()
	p, ok := b.prices[binanceSym]
	if !ok || p.Price <= 0 {
		return 0, fmt.Errorf("price not available for %s", displaySymbol)
	}
	return p.Price, nil
}

// displayToBinanceSymbol converts "BTC/USD" → "BTCUSDT"
func displayToBinanceSymbol(sym string) string {
	parts := strings.SplitN(sym, "/", 2)
	if len(parts) == 2 {
		base := strings.ToUpper(parts[0])
		return base + "USDT"
	}
	return strings.ToUpper(sym) + "USDT"
}

// convertToBinanceInterval maps common timeframe strings to Binance interval format
func convertToBinanceInterval(tf string) string {
	tf = strings.ToLower(tf)
	switch tf {
	case "1min", "1m":
		return "1m"
	case "3min", "3m":
		return "3m"
	case "5min", "5m":
		return "5m"
	case "15min", "15m":
		return "15m"
	case "30min", "30m":
		return "30m"
	case "1h", "1hour", "60min":
		return "1h"
	case "2h", "2hour":
		return "2h"
	case "4h", "4hour":
		return "4h"
	case "6h", "6hour":
		return "6h"
	case "12h", "12hour":
		return "12h"
	case "1d", "1day", "day":
		return "1d"
	case "3d", "3day":
		return "3d"
	case "1w", "1week", "week":
		return "1w"
	case "1month", "month":
		return "1M"
	default:
		return tf
	}
}
