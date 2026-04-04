package market

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type PolygonClient struct {
	apiKey     string
	httpClient *http.Client
	cache      *Cache
}

func NewPolygonClient(apiKey string, cache *Cache) *PolygonClient {
	return &PolygonClient{
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: 15 * time.Second},
		cache:      cache,
	}
}

func (p *PolygonClient) fetch(url string) (json.RawMessage, error) {
	if strings.Contains(url, "?") {
		url += "&apiKey=" + p.apiKey
	} else {
		url += "?apiKey=" + p.apiKey
	}

	resp, err := p.httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return json.RawMessage(body), nil
}

// ─── Snapshot (paid) ─────────────────────────────────

// GetSnapshot returns raw Polygon snapshot JSON for given symbols
func (p *PolygonClient) GetSnapshot(symbols []string) (json.RawMessage, error) {
	cacheKey := "snapshot:" + strings.Join(symbols, ",")
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(json.RawMessage), nil
	}

	tickers := strings.Join(symbols, ",")
	url := fmt.Sprintf("https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers?tickers=%s", tickers)
	data, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	p.cache.Set(cacheKey, data, 5*time.Second)
	return data, nil
}

// GetSnapshotParsed returns parsed quote data as map[symbol]quote.
// Falls back to last-trade API when snapshot day data is empty (delayed plan).
func (p *PolygonClient) GetSnapshotParsed(symbols []string) (map[string]map[string]any, error) {
	cacheKey := "snapshot_parsed:" + strings.Join(symbols, ",")
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(map[string]map[string]any), nil
	}

	tickers := strings.Join(symbols, ",")
	url := fmt.Sprintf("https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers?tickers=%s", tickers)
	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	result := make(map[string]map[string]any)
	var needLastTrade []string
	for _, item := range parseSnapshotTickers(raw) {
		sym, _ := item["symbol"].(string)
		if sym == "" {
			continue
		}
		result[sym] = item
		// If day.c was 0 (price fell back to prevDay), we need last trade
		if dayC, _ := item["price"].(float64); dayC > 0 {
			if prevC, _ := item["prev_close"].(float64); prevC > 0 && dayC == prevC {
				needLastTrade = append(needLastTrade, sym)
			}
		}
	}

	// Fetch last trade prices concurrently for symbols without day data
	if len(needLastTrade) > 0 {
		type ltResult struct {
			Symbol string
			Price  float64
		}
		ch := make(chan ltResult, len(needLastTrade))
		for _, sym := range needLastTrade {
			go func(s string) {
				ltURL := fmt.Sprintf("https://api.polygon.io/v2/last/trade/%s", s)
				ltRaw, err := p.fetch(ltURL)
				if err != nil {
					ch <- ltResult{s, 0}
					return
				}
				var lt struct {
					Results struct {
						Price float64 `json:"p"`
					} `json:"results"`
				}
				json.Unmarshal(ltRaw, &lt)
				ch <- ltResult{s, lt.Results.Price}
			}(sym)
		}
		for range needLastTrade {
			r := <-ch
			if r.Price > 0 {
				if item, ok := result[r.Symbol]; ok {
					prevClose, _ := item["prev_close"].(float64)
					item["price"] = r.Price
					item["close"] = r.Price
					if prevClose > 0 {
						change := r.Price - prevClose
						item["change"] = change
						item["percent_change"] = (change / prevClose) * 100
					}
				}
			}
		}
	}

	p.cache.Set(cacheKey, result, 5*time.Second)
	return result, nil
}

// GetIndexSnapshot returns a single index snapshot (paid plan)
func (p *PolygonClient) GetIndexSnapshot(ticker string) (map[string]any, error) {
	cacheKey := "index:" + ticker
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(map[string]any), nil
	}

	url := fmt.Sprintf("https://api.polygon.io/v3/snapshot/indices?ticker.any_of=%s", ticker)
	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	var resp struct {
		Results []struct {
			Ticker  string  `json:"ticker"`
			Name    string  `json:"name"`
			Value   float64 `json:"value"`
			Session struct {
				Change        float64 `json:"change"`
				ChangePercent float64 `json:"change_percent"`
				Close         float64 `json:"close"`
				High          float64 `json:"high"`
				Low           float64 `json:"low"`
				Open          float64 `json:"open"`
				PreviousClose float64 `json:"previous_close"`
			} `json:"session"`
		} `json:"results"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}
	if len(resp.Results) == 0 {
		return nil, fmt.Errorf("no data for %s", ticker)
	}

	r := resp.Results[0]
	price := r.Value
	if r.Session.Close > 0 {
		price = r.Session.Close
	}

	result := map[string]any{
		"symbol":         r.Ticker,
		"name":           r.Name,
		"price":          price,
		"close":          price,
		"open":           r.Session.Open,
		"high":           r.Session.High,
		"low":            r.Session.Low,
		"prev_close":     r.Session.PreviousClose,
		"change":         r.Session.Change,
		"percent_change": r.Session.ChangePercent,
	}

	p.cache.Set(cacheKey, result, 10*time.Second)
	return result, nil
}

// GetPrevDay returns previous day aggregates (free tier fallback)
func (p *PolygonClient) GetPrevDay(ticker string) (map[string]any, error) {
	cacheKey := "prevday:" + ticker
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(map[string]any), nil
	}

	url := fmt.Sprintf("https://api.polygon.io/v2/aggs/ticker/%s/prev?adjusted=true", ticker)
	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	var resp struct {
		Results []json.RawMessage `json:"results"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}
	if len(resp.Results) == 0 {
		return nil, fmt.Errorf("no data for %s", ticker)
	}

	var r struct {
		O float64 `json:"o"`
		H float64 `json:"h"`
		L float64 `json:"l"`
		C float64 `json:"c"`
		V float64 `json:"v"`
	}
	if err := json.Unmarshal(resp.Results[0], &r); err != nil {
		return nil, err
	}

	change := r.C - r.O
	var pctChange float64
	if r.O > 0 {
		pctChange = (change / r.O) * 100
	}

	result := map[string]any{
		"symbol":         ticker,
		"price":          r.C,
		"close":          r.C,
		"open":           r.O,
		"high":           r.H,
		"low":            r.L,
		"volume":         r.V,
		"prev_close":     r.O,
		"change":         change,
		"percent_change": pctChange,
	}

	p.cache.Set(cacheKey, result, 30*time.Second)
	return result, nil
}

// ─── Candles ─────────────────────────────────────────

// GetCandles returns raw aggregated bars
func (p *PolygonClient) GetCandles(symbol, timeframe, from, to string) (json.RawMessage, error) {
	cacheKey := fmt.Sprintf("candles:%s:%s:%s:%s", symbol, timeframe, from, to)
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(json.RawMessage), nil
	}

	multiplier, timespan := parseTimeframe(timeframe)
	url := fmt.Sprintf("https://api.polygon.io/v2/aggs/ticker/%s/range/%s/%s/%s/%s?adjusted=true&sort=asc&limit=5000",
		symbol, multiplier, timespan, from, to)

	data, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	p.cache.Set(cacheKey, data, 60*time.Second)
	return data, nil
}

// resolvePolygonTicker converts display symbols to Polygon ticker format:
//   BTC/USD → X:BTCUSD (crypto), EUR/USD → C:EURUSD (forex),
//   DJI → I:DJI, SPX → I:SPX, IXIC → I:COMP, VIX → I:VIX (indices),
//   AAPL → AAPL (stocks, unchanged)
func resolvePolygonTicker(symbol string) string {
	// Index mapping
	indexMap := map[string]string{
		"DJI": "I:DJI", "SPX": "I:SPX", "IXIC": "I:COMP", "VIX": "I:VIX",
	}
	if ticker, ok := indexMap[symbol]; ok {
		return ticker
	}

	// Slash-based symbols: crypto or forex
	parts := strings.SplitN(symbol, "/", 2)
	if len(parts) == 2 {
		base, quote := parts[0], parts[1]
		// Crypto: quote is USD/USDT and base is a known crypto
		cryptoBases := map[string]bool{
			"BTC": true, "ETH": true, "BNB": true, "SOL": true, "XRP": true,
			"DOGE": true, "ADA": true, "AVAX": true, "DOT": true, "MATIC": true,
			"LINK": true, "UNI": true, "SHIB": true, "LTC": true, "TRX": true,
			"ATOM": true, "NEAR": true, "APT": true, "ARB": true, "OP": true,
			"SUI": true, "SEI": true, "INJ": true, "TIA": true, "JUP": true,
			"WIF": true, "PEPE": true, "FLOKI": true, "BONK": true, "RENDER": true,
			"FET": true, "TAO": true, "AR": true, "FIL": true, "AAVE": true,
			"MKR": true, "CRV": true, "RUNE": true, "IMX": true, "STX": true,
		}
		if cryptoBases[base] {
			return "X:" + base + quote
		}
		// Forex
		return "C:" + base + quote
	}

	return symbol
}

// GetCandlesParsed returns parsed candle bars as [{t,o,h,l,c,v}]
func (p *PolygonClient) GetCandlesParsed(symbol, timeframe, from, to string) ([]map[string]any, error) {
	cacheKey := fmt.Sprintf("candles_parsed:%s:%s:%s:%s", symbol, timeframe, from, to)
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.([]map[string]any), nil
	}

	ticker := resolvePolygonTicker(symbol)
	multiplier, timespan := parseTimeframe(timeframe)
	url := fmt.Sprintf("https://api.polygon.io/v2/aggs/ticker/%s/range/%s/%s/%s/%s?adjusted=true&sort=asc&limit=5000",
		ticker, multiplier, timespan, from, to)

	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	var resp struct {
		Results []json.RawMessage `json:"results"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}

	bars := make([]map[string]any, 0, len(resp.Results))
	for _, rawBar := range resp.Results {
		var b struct {
			T int64   `json:"t"`
			O float64 `json:"o"`
			H float64 `json:"h"`
			L float64 `json:"l"`
			C float64 `json:"c"`
			V float64 `json:"v"`
		}
		if json.Unmarshal(rawBar, &b) == nil {
			bars = append(bars, map[string]any{
				"t": b.T, "o": b.O, "h": b.H, "l": b.L, "c": b.C, "v": b.V,
			})
		}
	}

	p.cache.Set(cacheKey, bars, 60*time.Second)
	return bars, nil
}

// ─── Search ──────────────────────────────────────────

// Search returns raw search results
func (p *PolygonClient) Search(query string) (json.RawMessage, error) {
	url := fmt.Sprintf("https://api.polygon.io/v3/reference/tickers?search=%s&active=true&limit=20", query)
	return p.fetch(url)
}

// SearchParsed returns parsed search results as [{ticker, name, type, market}]
func (p *PolygonClient) SearchParsed(query string) ([]map[string]any, error) {
	url := fmt.Sprintf("https://api.polygon.io/v3/reference/tickers?search=%s&active=true&limit=20", query)
	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	var resp struct {
		Results []struct {
			Ticker string `json:"ticker"`
			Name   string `json:"name"`
			Type   string `json:"type"`
			Market string `json:"market"`
		} `json:"results"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}

	results := make([]map[string]any, 0, len(resp.Results))
	for _, r := range resp.Results {
		results = append(results, map[string]any{
			"ticker": r.Ticker,
			"name":   r.Name,
			"type":   r.Type,
			"market": r.Market,
		})
	}
	return results, nil
}

// ─── Gainers / Losers ────────────────────────────────

// GetGainers returns raw gainers JSON
func (p *PolygonClient) GetGainers() (json.RawMessage, error) {
	cacheKey := "gainers"
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(json.RawMessage), nil
	}

	url := "https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/gainers"
	data, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	p.cache.Set(cacheKey, data, 30*time.Second)
	return data, nil
}

// GetGainersParsed returns parsed gainers list
func (p *PolygonClient) GetGainersParsed() ([]map[string]any, error) {
	cacheKey := "gainers_parsed"
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.([]map[string]any), nil
	}

	raw, err := p.GetGainers()
	if err != nil {
		return nil, err
	}

	items := parseSnapshotTickers(raw)
	p.cache.Set(cacheKey, items, 30*time.Second)
	return items, nil
}

// GetLosers returns raw losers JSON
func (p *PolygonClient) GetLosers() (json.RawMessage, error) {
	cacheKey := "losers"
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(json.RawMessage), nil
	}

	url := "https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/losers"
	data, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	p.cache.Set(cacheKey, data, 30*time.Second)
	return data, nil
}

// GetLosersParsed returns parsed losers list
func (p *PolygonClient) GetLosersParsed() ([]map[string]any, error) {
	cacheKey := "losers_parsed"
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.([]map[string]any), nil
	}

	raw, err := p.GetLosers()
	if err != nil {
		return nil, err
	}

	items := parseSnapshotTickers(raw)
	p.cache.Set(cacheKey, items, 30*time.Second)
	return items, nil
}

// ─── Forex ───────────────────────────────────────────

// GetForexPairs returns common forex pairs with snapshot data
func (p *PolygonClient) GetForexPairs() ([]map[string]any, error) {
	cacheKey := "forex_pairs"
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.([]map[string]any), nil
	}

	pairs := []string{"C:EURUSD", "C:GBPUSD", "C:USDJPY", "C:AUDUSD", "C:USDCAD", "C:USDCHF", "C:NZDUSD", "C:EURGBP"}
	displayNames := map[string]string{
		"C:EURUSD": "EUR/USD", "C:GBPUSD": "GBP/USD", "C:USDJPY": "USD/JPY",
		"C:AUDUSD": "AUD/USD", "C:USDCAD": "USD/CAD", "C:USDCHF": "USD/CHF",
		"C:NZDUSD": "NZD/USD", "C:EURGBP": "EUR/GBP",
	}

	var result []map[string]any
	for _, pair := range pairs {
		snap, err := p.GetForexSnapshot(displayNames[pair])
		if err == nil && snap != nil {
			result = append(result, snap)
		}
	}
	if result == nil {
		result = []map[string]any{}
	}

	p.cache.Set(cacheKey, result, 30*time.Second)
	return result, nil
}

// GetForexSnapshot returns a forex pair snapshot
func (p *PolygonClient) GetForexSnapshot(symbol string) (map[string]any, error) {
	polygonSym := "C:" + strings.Replace(symbol, "/", "", 1)
	cacheKey := "forex:" + polygonSym
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(map[string]any), nil
	}

	url := fmt.Sprintf("https://api.polygon.io/v2/snapshot/locale/global/markets/forex/tickers/%s", polygonSym)
	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	var resp struct {
		Ticker struct {
			Ticker string `json:"ticker"`
			Day    struct {
				O float64 `json:"o"`
				H float64 `json:"h"`
				L float64 `json:"l"`
				C float64 `json:"c"`
				V float64 `json:"v"`
			} `json:"day"`
			PrevDay struct {
				C float64 `json:"c"`
			} `json:"prevDay"`
			TodaysChange     float64 `json:"todaysChange"`
			TodaysChangePerc float64 `json:"todaysChangePerc"`
		} `json:"ticker"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}

	t := resp.Ticker
	result := map[string]any{
		"symbol":         symbol,
		"price":          t.Day.C,
		"close":          t.Day.C,
		"open":           t.Day.O,
		"high":           t.Day.H,
		"low":            t.Day.L,
		"volume":         t.Day.V,
		"prev_close":     t.PrevDay.C,
		"change":         t.TodaysChange,
		"percent_change": t.TodaysChangePerc,
		"market":         "forex",
	}

	p.cache.Set(cacheKey, result, 3*time.Second)
	return result, nil
}

// ─── News ────────────────────────────────────────────

// GetNews returns news articles from Polygon
func (p *PolygonClient) GetNews(ticker, limit string) ([]map[string]any, error) {
	cacheKey := fmt.Sprintf("news:%s:%s", ticker, limit)
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.([]map[string]any), nil
	}

	url := fmt.Sprintf("https://api.polygon.io/v2/reference/news?limit=%s&order=desc", limit)
	if ticker != "" {
		url += "&ticker=" + ticker
	}

	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

	var resp struct {
		Results []struct {
			Title        string `json:"title"`
			Description  string `json:"description"`
			ArticleURL   string `json:"article_url"`
			PublishedUTC string `json:"published_utc"`
			ImageURL     string `json:"image_url"`
			Publisher    struct {
				Name string `json:"name"`
			} `json:"publisher"`
		} `json:"results"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}

	articles := make([]map[string]any, 0, len(resp.Results))
	for _, r := range resp.Results {
		articles = append(articles, map[string]any{
			"headline":     r.Title,
			"summary":      r.Description,
			"url":          r.ArticleURL,
			"publishedUtc": r.PublishedUTC,
			"source":       r.Publisher.Name,
			"image_url":    r.ImageURL,
		})
	}

	p.cache.Set(cacheKey, articles, 5*time.Minute)
	return articles, nil
}

// ─── Helpers ─────────────────────────────────────────

func parseTimeframe(tf string) (string, string) {
	switch tf {
	case "1m", "1min":
		return "1", "minute"
	case "3m", "3min":
		return "3", "minute"
	case "5m", "5min":
		return "5", "minute"
	case "15m", "15min":
		return "15", "minute"
	case "30m", "30min":
		return "30", "minute"
	case "1h", "1H", "60min":
		return "1", "hour"
	case "2h":
		return "2", "hour"
	case "4h", "4H":
		return "4", "hour"
	case "6h":
		return "6", "hour"
	case "12h":
		return "12", "hour"
	case "1D", "1d", "day", "1day":
		return "1", "day"
	case "3d", "3day":
		return "3", "day"
	case "1W", "1w", "week", "1week":
		return "1", "week"
	case "1M", "month", "1month":
		return "1", "month"
	default:
		return "1", "day"
	}
}

func parseSnapshotTickers(raw json.RawMessage) []map[string]any {
	var resp struct {
		Tickers []struct {
			Ticker string `json:"ticker"`
			Day    struct {
				O float64 `json:"o"`
				H float64 `json:"h"`
				L float64 `json:"l"`
				C float64 `json:"c"`
				V float64 `json:"v"`
			} `json:"day"`
			PrevDay struct {
				C float64 `json:"c"`
			} `json:"prevDay"`
			TodaysChange     float64 `json:"todaysChange"`
			TodaysChangePerc float64 `json:"todaysChangePerc"`
		} `json:"tickers"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil
	}

	items := make([]map[string]any, 0, len(resp.Tickers))
	for _, t := range resp.Tickers {
		price := t.Day.C
		if price == 0 {
			price = t.PrevDay.C
		}
		items = append(items, map[string]any{
			"symbol":         t.Ticker,
			"price":          price,
			"close":          price,
			"change":         t.TodaysChange,
			"percent_change": t.TodaysChangePerc,
			"open":           t.Day.O,
			"high":           t.Day.H,
			"low":            t.Day.L,
			"volume":         t.Day.V,
			"prev_close":     t.PrevDay.C,
			"market":         "stocks",
		})
	}
	return items
}
