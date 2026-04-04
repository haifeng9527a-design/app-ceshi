package handler

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"tongxin-go/internal/market"
	"tongxin-go/internal/model"
)

type MarketHandler struct {
	polygon    *market.PolygonClient
	binance    *market.BinanceIngestor
	httpClient *http.Client
}

func NewMarketHandler(polygon *market.PolygonClient, binance *market.BinanceIngestor) *MarketHandler {
	return &MarketHandler{
		polygon:    polygon,
		binance:    binance,
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

// GET /api/market/snapshot?symbols=AAPL,MSFT
// GET /api/quotes?symbols=AAPL,MSFT (alias)
func (h *MarketHandler) Snapshot(w http.ResponseWriter, r *http.Request) {
	symbolsStr := r.URL.Query().Get("symbols")
	if symbolsStr == "" {
		writeError(w, http.StatusBadRequest, "symbols parameter required")
		return
	}
	symbols := strings.Split(symbolsStr, ",")

	data, err := h.polygon.GetSnapshot(symbols)
	if err != nil {
		writeError(w, http.StatusBadGateway, "polygon request failed")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(data)
}

// GET /api/quotes?symbols=AAPL,DJI,SPX
// Returns: { "AAPL": { symbol, price, change, percent_change, ... } }
func (h *MarketHandler) Quotes(w http.ResponseWriter, r *http.Request) {
	symbolsStr := r.URL.Query().Get("symbols")
	if symbolsStr == "" {
		writeJSON(w, http.StatusOK, map[string]any{})
		return
	}
	symbols := strings.Split(symbolsStr, ",")

	// Index symbols → Polygon I: tickers (paid plan)
	indexTickers := map[string]string{
		"DJI":  "I:DJI",
		"SPX":  "I:SPX",
		"IXIC": "I:COMP",
		"VIX":  "I:VIX",
	}

	result := make(map[string]any)
	var stockSymbols []string

	for _, sym := range symbols {
		sym = strings.TrimSpace(sym)
		if sym == "" {
			continue
		}
		if polyTicker, isIndex := indexTickers[sym]; isIndex {
			// Fetch index via snapshot/indices endpoint
			snap, err := h.polygon.GetIndexSnapshot(polyTicker)
			if err != nil {
				log.Printf("[quotes] GetIndexSnapshot(%s) error: %v", polyTicker, err)
			} else if snap != nil {
				snap["symbol"] = sym
				result[sym] = snap
			}
		} else {
			stockSymbols = append(stockSymbols, sym)
		}
	}

	// Batch fetch stock snapshots
	if len(stockSymbols) > 0 && h.polygon != nil {
		snaps, err := h.polygon.GetSnapshotParsed(stockSymbols)
		if err != nil {
			log.Printf("[quotes] GetSnapshotParsed error: %v", err)
		} else {
			for _, sym := range stockSymbols {
				if snap, ok := snaps[sym]; ok {
					result[sym] = snap
				}
			}
		}
	}

	writeJSON(w, http.StatusOK, result)
}

// GET /api/market/candles?symbol=AAPL&timeframe=1D&from=2024-01-01&to=2024-12-31
// GET /api/candles?symbol=AAPL&interval=1day (alias)
func (h *MarketHandler) Candles(w http.ResponseWriter, r *http.Request) {
	symbol := r.URL.Query().Get("symbol")
	timeframe := r.URL.Query().Get("timeframe")
	if timeframe == "" {
		timeframe = r.URL.Query().Get("interval")
	}
	from := r.URL.Query().Get("from")
	to := r.URL.Query().Get("to")
	fromMs := r.URL.Query().Get("fromMs")
	toMs := r.URL.Query().Get("toMs")

	if symbol == "" {
		writeError(w, http.StatusBadRequest, "symbol parameter required")
		return
	}
	if timeframe == "" {
		timeframe = "1D"
	}

	// Convert ms timestamps to date strings if provided
	if from == "" && fromMs != "" {
		from = msToDate(fromMs)
	}
	if to == "" && toMs != "" {
		to = msToDate(toMs)
	}

	// Route crypto symbols to Binance, everything else to Polygon
	if isCryptoDisplaySymbol(symbol) {
		data, err := h.binance.GetKlines(symbol, timeframe, 0, 0, 500)
		if err != nil {
			log.Printf("[candles] binance error for %s: %v", symbol, err)
			writeError(w, http.StatusBadGateway, "binance request failed")
			return
		}
		writeJSON(w, http.StatusOK, data)
		return
	}

	// Non-crypto: use Polygon
	if from == "" {
		from = time.Now().AddDate(-1, 0, 0).Format("2006-01-02")
	}
	if to == "" {
		to = time.Now().Format("2006-01-02")
	}

	data, err := h.polygon.GetCandlesParsed(symbol, timeframe, from, to)
	if err != nil {
		writeError(w, http.StatusBadGateway, "polygon request failed")
		return
	}

	writeJSON(w, http.StatusOK, data)
}

// GET /api/market/search?q=apple
// GET /api/search?q=apple (alias)
func (h *MarketHandler) Search(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	if query == "" {
		writeJSON(w, http.StatusOK, []any{})
		return
	}

	data, err := h.polygon.SearchParsed(query)
	if err != nil {
		writeError(w, http.StatusBadGateway, "search failed")
		return
	}

	writeJSON(w, http.StatusOK, data)
}

// GET /api/market/gainers
// GET /api/gainers (alias)
func (h *MarketHandler) Gainers(w http.ResponseWriter, r *http.Request) {
	data, err := h.polygon.GetGainersParsed()
	if err != nil {
		writeError(w, http.StatusBadGateway, "polygon request failed")
		return
	}
	writeJSON(w, http.StatusOK, data)
}

// GET /api/market/losers
// GET /api/losers (alias)
func (h *MarketHandler) Losers(w http.ResponseWriter, r *http.Request) {
	data, err := h.polygon.GetLosersParsed()
	if err != nil {
		writeError(w, http.StatusBadGateway, "polygon request failed")
		return
	}
	writeJSON(w, http.StatusOK, data)
}

// GET /api/market/crypto/prices
// GET /api/crypto/quotes?symbols=BTC/USD,ETH/USD (alias)
func (h *MarketHandler) CryptoPrices(w http.ResponseWriter, r *http.Request) {
	prices := h.binance.GetPrices()
	writeJSON(w, http.StatusOK, prices)
}

// GET /api/crypto/quotes?symbols=BTC/USD,ETH/USD
// Returns: { "BTC/USD": { symbol, price, change, percent_change, ... } }
func (h *MarketHandler) CryptoQuotes(w http.ResponseWriter, r *http.Request) {
	symbolsStr := r.URL.Query().Get("symbols")
	allPrices := h.binance.GetPrices()

	// Build lookup map: BTCUSDT -> CryptoPrice
	priceMap := make(map[string]*model.CryptoPrice)
	for i := range allPrices {
		priceMap[allPrices[i].Symbol] = &allPrices[i]
	}

	result := make(map[string]any)

	if symbolsStr != "" {
		symbols := strings.Split(symbolsStr, ",")
		for _, sym := range symbols {
			sym = strings.TrimSpace(sym)
			// Convert BTC/USD -> BTCUSDT
			binanceSym := cryptoToBinanceSymbol(sym)
			if p, ok := priceMap[binanceSym]; ok {
				change := p.Price - p.Open24h
				result[sym] = map[string]any{
					"symbol":         sym,
					"close":          p.Price,
					"price":          p.Price,
					"change":         change,
					"percent_change": p.Change24h,
					"prev_close":     p.Open24h,
					"open":           p.Open24h,
					"high":           p.High24h,
					"low":            p.Low24h,
					"volume":         p.Volume24h,
				}
			}
		}
	} else {
		// Return all
		for _, p := range allPrices {
			sym := binanceToCryptoSymbol(p.Symbol)
			change := p.Price - p.Open24h
			result[sym] = map[string]any{
				"symbol":         sym,
				"close":          p.Price,
				"price":          p.Price,
				"change":         change,
				"percent_change": p.Change24h,
				"prev_close":     p.Open24h,
				"open":           p.Open24h,
				"high":           p.High24h,
				"low":            p.Low24h,
				"volume":         p.Volume24h,
			}
		}
	}

	writeJSON(w, http.StatusOK, result)
}

// GET /api/crypto/pairs?page=1&pageSize=30
func (h *MarketHandler) CryptoPairs(w http.ResponseWriter, r *http.Request) {
	prices := h.binance.GetPrices()

	items := make([]map[string]any, 0, len(prices))
	for _, p := range prices {
		change := p.Price - p.Open24h
		items = append(items, map[string]any{
			"symbol":         binanceToCryptoSymbol(p.Symbol),
			"name":           strings.TrimSuffix(p.Symbol, "USDT"),
			"price":          p.Price,
			"change":         change,
			"percent_change": p.Change24h,
			"prev_close":     p.Open24h,
			"open":           p.Open24h,
			"volume":         p.Volume24h,
			"high":           p.High24h,
			"low":            p.Low24h,
			"market":         "crypto",
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"items":    items,
		"total":    len(items),
		"page":     1,
		"pageSize": len(items),
		"hasMore":  false,
	})
}

// GET /api/crypto/depth?symbol=BTC/USD&limit=5
func (h *MarketHandler) CryptoDepth(w http.ResponseWriter, r *http.Request) {
	symbol := r.URL.Query().Get("symbol")
	if symbol == "" {
		writeError(w, http.StatusBadRequest, "symbol required")
		return
	}
	limit := r.URL.Query().Get("limit")
	if limit == "" {
		limit = "5"
	}

	binanceSym := cryptoToBinanceSymbol(symbol)
	url := fmt.Sprintf("https://api.binance.com/api/v3/depth?symbol=%s&limit=%s", binanceSym, limit)

	resp, err := h.httpClient.Get(url)
	if err != nil {
		writeError(w, http.StatusBadGateway, "binance request failed")
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

// GET /api/funding-rate?symbol=BTC/USD
func (h *MarketHandler) FundingRate(w http.ResponseWriter, r *http.Request) {
	symbol := r.URL.Query().Get("symbol")
	if symbol == "" {
		writeError(w, http.StatusBadRequest, "symbol required")
		return
	}
	binanceSym := cryptoToBinanceSymbol(symbol)
	url := fmt.Sprintf("https://fapi.binance.com/fapi/v1/premiumIndex?symbol=%s", binanceSym)
	resp, err := h.httpClient.Get(url)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"fundingRate": nil})
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		writeJSON(w, http.StatusOK, map[string]any{"fundingRate": nil})
		return
	}
	var raw struct {
		LastFundingRate string `json:"lastFundingRate"`
		NextFundingTime int64  `json:"nextFundingTime"`
		MarkPrice       string `json:"markPrice"`
		IndexPrice      string `json:"indexPrice"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"fundingRate": nil})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"symbol":          symbol,
		"fundingRate":     raw.LastFundingRate,
		"nextFundingTime": raw.NextFundingTime,
		"markPrice":       raw.MarkPrice,
		"indexPrice":      raw.IndexPrice,
	})
}

// GET /api/tickers-page?page=1&pageSize=30&sortColumn=pct
func (h *MarketHandler) TickersPage(w http.ResponseWriter, r *http.Request) {
	// Use Polygon gainers as a stock list source
	data, err := h.polygon.GetGainersParsed()
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"items":    []any{},
			"total":    0,
			"page":     1,
			"pageSize": 30,
			"hasMore":  false,
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"items":    data,
		"total":    len(data),
		"page":     1,
		"pageSize": len(data),
		"hasMore":  false,
	})
}

// GET /api/forex/pairs?page=1&pageSize=30
func (h *MarketHandler) ForexPairs(w http.ResponseWriter, r *http.Request) {
	pairs, err := h.polygon.GetForexPairs()
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"items":    []any{},
			"total":    0,
			"page":     1,
			"pageSize": 30,
			"hasMore":  false,
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items":    pairs,
		"total":    len(pairs),
		"page":     1,
		"pageSize": len(pairs),
		"hasMore":  false,
	})
}

// GET /api/forex/quotes?symbols=EUR/USD,GBP/USD
func (h *MarketHandler) ForexQuotes(w http.ResponseWriter, r *http.Request) {
	symbolsStr := r.URL.Query().Get("symbols")
	if symbolsStr == "" {
		writeJSON(w, http.StatusOK, map[string]any{})
		return
	}
	symbols := strings.Split(symbolsStr, ",")

	// Fetch all forex snapshots concurrently to avoid serial timeout
	type snapResult struct {
		sym  string
		snap map[string]any
	}
	ch := make(chan snapResult, len(symbols))
	for _, sym := range symbols {
		sym = strings.TrimSpace(sym)
		go func(s string) {
			snap, err := h.polygon.GetForexSnapshot(s)
			if err == nil && snap != nil {
				ch <- snapResult{s, snap}
			} else {
				ch <- snapResult{s, nil}
			}
		}(sym)
	}

	result := make(map[string]any)
	for range symbols {
		sr := <-ch
		if sr.snap != nil {
			result[sr.sym] = sr.snap
		}
	}

	writeJSON(w, http.StatusOK, result)
}

// GET /api/news?ticker=AAPL&limit=20
// GET /api/news/hot?limit=20
func (h *MarketHandler) News(w http.ResponseWriter, r *http.Request) {
	ticker := r.URL.Query().Get("ticker")
	limit := r.URL.Query().Get("limit")
	if limit == "" {
		limit = "10"
	}

	data, err := h.polygon.GetNews(ticker, limit)
	if err != nil {
		writeJSON(w, http.StatusOK, []any{})
		return
	}

	writeJSON(w, http.StatusOK, data)
}

// GET /api/market/snapshots?type=indices
func (h *MarketHandler) Snapshots(w http.ResponseWriter, r *http.Request) {
	typ := r.URL.Query().Get("type")
	if typ == "indices" && h.polygon != nil {
		indices := []struct {
			ticker string
			symbol string
			name   string
		}{
			{"I:DJI", "DJI", "DOW JONES"},
			{"I:SPX", "SPX", "S&P 500"},
			{"I:COMP", "IXIC", "NASDAQ"},
			{"I:VIX", "VIX", "VIX VOLATILITY"},
		}

		var result []map[string]any
		for _, idx := range indices {
			snap, err := h.polygon.GetIndexSnapshot(idx.ticker)
			if err == nil && snap != nil {
				snap["symbol"] = idx.symbol
				snap["name"] = idx.name
				result = append(result, snap)
			}
		}
		if result == nil {
			result = []map[string]any{}
		}
		writeJSON(w, http.StatusOK, result)
		return
	}

	writeJSON(w, http.StatusOK, []any{})
}

// ─── Helpers ─────────────────────────────────

// isCryptoDisplaySymbol checks if a symbol like "BTC/USD" is a crypto pair
func isCryptoDisplaySymbol(sym string) bool {
	cryptoBases := map[string]bool{
		"BTC": true, "ETH": true, "BNB": true, "SOL": true, "XRP": true,
		"DOGE": true, "ADA": true, "AVAX": true, "DOT": true, "MATIC": true,
		"LINK": true, "UNI": true, "SHIB": true, "LTC": true, "TRX": true,
		"ATOM": true, "NEAR": true, "APT": true, "ARB": true, "OP": true,
		"SUI": true, "SEI": true, "INJ": true, "TIA": true, "JUP": true,
		"WIF": true, "PEPE": true, "FLOKI": true, "BONK": true, "RENDER": true,
		"FET": true, "TAO": true, "AR": true, "FIL": true, "AAVE": true,
		"MKR": true, "CRV": true, "RUNE": true, "IMX": true, "STX": true,
		"TON": true, "HBAR": true, "VET": true, "ALGO": true, "FTM": true,
		"MANA": true, "SAND": true, "AXS": true, "GALA": true, "ENJ": true,
		"CHZ": true, "THETA": true, "ZIL": true, "IOTA": true, "EOS": true,
		"XLM": true, "XMR": true, "DASH": true, "ZEC": true, "BCH": true,
		"ETC": true, "NEO": true, "WAVES": true, "QTUM": true, "ONT": true,
		"ICX": true, "COMP": true, "SNX": true, "YFI": true, "SUSHI": true,
		"1INCH": true, "BAT": true, "KAVA": true, "CELO": true, "FLOW": true,
		"MINA": true, "KSM": true, "ROSE": true, "ZRX": true, "LRC": true,
		"ENS": true, "GMT": true, "APE": true, "LUNC": true, "CKB": true,
		"CFX": true, "AGIX": true, "RNDR": true, "GRT": true, "DYDX": true,
		"WLD": true, "PYTH": true, "JTO": true, "STRK": true, "PIXEL": true,
		"W": true, "PENDLE": true, "ETHFI": true, "BOME": true, "NOT": true,
	}
	parts := strings.SplitN(sym, "/", 2)
	if len(parts) != 2 {
		return false
	}
	return cryptoBases[strings.ToUpper(parts[0])]
}

func cryptoToBinanceSymbol(sym string) string {
	// BTC/USD -> BTCUSDT, BTCUSDT -> BTCUSDT
	sym = strings.ToUpper(strings.TrimSpace(sym))
	sym = strings.Replace(sym, "/USD", "USDT", 1)
	sym = strings.Replace(sym, "/", "", -1)
	if !strings.HasSuffix(sym, "USDT") && !strings.HasSuffix(sym, "BUSD") {
		sym += "USDT"
	}
	return sym
}

func binanceToCryptoSymbol(sym string) string {
	// BTCUSDT -> BTC/USD
	sym = strings.ToUpper(sym)
	if strings.HasSuffix(sym, "USDT") {
		base := strings.TrimSuffix(sym, "USDT")
		return base + "/USD"
	}
	return sym
}

func msToDate(ms string) string {
	var msInt int64
	json.Unmarshal([]byte(ms), &msInt)
	if msInt > 0 {
		return time.UnixMilli(msInt).Format("2006-01-02")
	}
	return ""
}
