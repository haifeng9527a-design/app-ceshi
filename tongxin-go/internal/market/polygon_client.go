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

	// Use sort=desc so Polygon returns the newest candles first.
	// Polygon forex API caps results per request regardless of limit,
	// so sort=asc would return only the oldest slice of the range.
	url := fmt.Sprintf("https://api.polygon.io/v2/aggs/ticker/%s/range/%s/%s/%s/%s?adjusted=true&sort=desc&limit=5000",
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

	// Reverse to ascending time order for the frontend
	for i, j := 0, len(bars)-1; i < j; i, j = i+1, j-1 {
		bars[i], bars[j] = bars[j], bars[i]
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

// GetForexSnapshotAll fetches ALL forex tickers in one API call and returns
// a map keyed by display symbol (e.g. "EUR/USD").
func (p *PolygonClient) GetForexSnapshotAll() (map[string]map[string]any, error) {
	cacheKey := "forex_snapshot_all"
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(map[string]map[string]any), nil
	}

	url := "https://api.polygon.io/v2/snapshot/locale/global/markets/forex/tickers"
	raw, err := p.fetch(url)
	if err != nil {
		return nil, err
	}

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
		return nil, err
	}

	result := make(map[string]map[string]any, len(resp.Tickers))
	for _, t := range resp.Tickers {
		// Convert C:EURUSD → EUR/USD
		sym := strings.TrimPrefix(t.Ticker, "C:")
		if len(sym) == 6 {
			sym = sym[:3] + "/" + sym[3:]
		}
		result[sym] = map[string]any{
			"symbol":         sym,
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
	}

	p.cache.Set(cacheKey, result, 1*time.Second)
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

// ─── Futures ─────────────────────────────────────────

// Known futures root symbols and their active contract month patterns.
// Quarterly: H(Mar), M(Jun), U(Sep), Z(Dec)
var futuresMonths = map[string][]byte{
	"ES":  {'H', 'M', 'U', 'Z'}, // E-mini S&P 500
	"NQ":  {'H', 'M', 'U', 'Z'}, // E-mini Nasdaq
	"YM":  {'H', 'M', 'U', 'Z'}, // Mini Dow
	"RTY": {'H', 'M', 'U', 'Z'}, // Mini Russell 2000
	"ZB":  {'H', 'M', 'U', 'Z'}, // 30-Year T-Bond
	"ZN":  {'H', 'M', 'U', 'Z'}, // 10-Year T-Note
	"ZF":  {'H', 'M', 'U', 'Z'}, // 5-Year T-Note
	"ZT":  {'H', 'M', 'U', 'Z'}, // 2-Year T-Note
	"CL":  {'F', 'G', 'H', 'J', 'K', 'M', 'N', 'Q', 'U', 'V', 'X', 'Z'}, // Crude Oil
	"NG":  {'F', 'G', 'H', 'J', 'K', 'M', 'N', 'Q', 'U', 'V', 'X', 'Z'}, // Natural Gas
	"GC":  {'G', 'J', 'M', 'Q', 'V', 'Z'}, // Gold
	"SI":  {'H', 'K', 'N', 'U', 'Z'},       // Silver
	"HG":  {'H', 'K', 'N', 'U', 'Z'},       // Copper
	"ZC":  {'H', 'K', 'N', 'U', 'Z'},       // Corn
	"ZS":  {'F', 'H', 'K', 'N', 'Q', 'U', 'X'}, // Soybeans
	"ZW":  {'H', 'K', 'N', 'U', 'Z'},       // Wheat
	"ZM":  {'F', 'H', 'K', 'N', 'Q', 'V', 'Z'}, // Soybean Meal
	"ZL":  {'F', 'H', 'K', 'N', 'Q', 'V', 'Z'}, // Soybean Oil
	"KC":  {'H', 'K', 'N', 'U', 'Z'},       // Coffee
	"SB":  {'H', 'K', 'N', 'V'},             // Sugar
	"CC":  {'H', 'K', 'N', 'U', 'Z'},       // Cocoa
	"CT":  {'H', 'K', 'N', 'V', 'Z'},       // Cotton
	"LE":  {'G', 'J', 'M', 'Q', 'V', 'Z'},  // Live Cattle
	"HE":  {'G', 'J', 'K', 'M', 'N', 'Q', 'V', 'Z'}, // Lean Hogs
	"GF":  {'F', 'H', 'J', 'K', 'Q', 'U', 'V', 'X'}, // Feeder Cattle
	"PA":  {'H', 'M', 'U', 'Z'},             // Palladium
	"PL":  {'F', 'J', 'N', 'V'},             // Platinum
}

// monthCodeToInt maps futures month codes to calendar months.
var monthCodeToInt = map[byte]int{
	'F': 1, 'G': 2, 'H': 3, 'J': 4, 'K': 5, 'M': 6,
	'N': 7, 'Q': 8, 'U': 9, 'V': 10, 'X': 11, 'Z': 12,
}

// resolveFuturesTicker converts a root symbol (e.g. "ES") to the front-month
// Polygon futures ticker (e.g. "ESM6" for June 2026).
func resolveFuturesTicker(root string) string {
	months, ok := futuresMonths[root]
	if !ok {
		months = []byte{'F', 'G', 'H', 'J', 'K', 'M', 'N', 'Q', 'U', 'V', 'X', 'Z'}
	}

	now := time.Now()
	curMonth := int(now.Month())
	curYear := now.Year() % 100

	for _, mc := range months {
		m := monthCodeToInt[mc]
		if m > curMonth || (m == curMonth && now.Day() <= 15) {
			return fmt.Sprintf("%s%c%d", root, mc, curYear)
		}
	}
	return fmt.Sprintf("%s%c%d", root, months[0], curYear+1)
}

// IsFuturesSymbol checks if a symbol is a known futures root symbol.
func IsFuturesSymbol(sym string) bool {
	_, ok := futuresMonths[sym]
	return ok
}

// parseFuturesResolution converts our internal timeframe to Polygon futures resolution format.
func parseFuturesResolution(tf string) string {
	switch tf {
	case "1", "1m", "1min":
		return "1min"
	case "3", "3m", "3min":
		return "3min"
	case "5", "5m", "5min":
		return "5min"
	case "15", "15m", "15min":
		return "15min"
	case "30", "30m", "30min":
		return "30min"
	case "60", "1h", "1H", "60min":
		return "1hour"
	case "2h":
		return "2hour"
	case "4h", "4H", "240":
		return "4hour"
	case "1D", "1d", "day", "1day":
		return "1session"
	case "1W", "1w", "week", "1week":
		return "1week"
	case "1M", "month", "1month":
		return "1month"
	default:
		return "1session"
	}
}

// GetFuturesCandlesParsed fetches candle data for a futures contract via the Polygon futures API.
// Falls back to the standard stock aggs API if the futures API is unauthorized.
func (p *PolygonClient) GetFuturesCandlesParsed(symbol, timeframe, from, to string) ([]map[string]any, error) {
	ticker := resolveFuturesTicker(symbol)
	resolution := parseFuturesResolution(timeframe)

	cacheKey := fmt.Sprintf("futures_candles:%s:%s:%s:%s", ticker, resolution, from, to)
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.([]map[string]any), nil
	}

	url := fmt.Sprintf("https://api.polygon.io/futures/vX/aggs/%s?resolution=%s&window_start.gte=%s&window_start.lte=%s&limit=5000&sort=window_start.desc",
		ticker, resolution, from+"T00:00:00Z", to+"T23:59:59Z")

	raw, err := p.fetch(url)
	if err != nil {
		// Fallback to stock aggs API
		return p.GetCandlesParsed(symbol, timeframe, from, to)
	}

	// Check if unauthorized
	var statusCheck struct {
		Status string `json:"status"`
	}
	json.Unmarshal(raw, &statusCheck)
	if statusCheck.Status == "NOT_AUTHORIZED" {
		return p.GetCandlesParsed(symbol, timeframe, from, to)
	}

	var resp struct {
		Results []struct {
			Open            float64 `json:"open"`
			High            float64 `json:"high"`
			Low             float64 `json:"low"`
			Close           float64 `json:"close"`
			Volume          float64 `json:"volume"`
			WindowStart     int64   `json:"window_start"`
			SettlementPrice float64 `json:"settlement_price"`
		} `json:"results"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil || len(resp.Results) == 0 {
		// Fallback to stock aggs API
		return p.GetCandlesParsed(symbol, timeframe, from, to)
	}

	bars := make([]map[string]any, 0, len(resp.Results))
	for _, b := range resp.Results {
		tMs := b.WindowStart / 1_000_000 // nanoseconds → milliseconds
		bars = append(bars, map[string]any{
			"t": tMs, "o": b.Open, "h": b.High, "l": b.Low, "c": b.Close, "v": b.Volume,
		})
	}

	// Reverse to ascending time order
	for i, j := 0, len(bars)-1; i < j; i, j = i+1, j-1 {
		bars[i], bars[j] = bars[j], bars[i]
	}

	p.cache.Set(cacheKey, bars, 60*time.Second)
	return bars, nil
}

// GetFuturesQuotes fetches latest quotes for multiple futures root symbols.
// Tries the dedicated futures API first; if unauthorized, falls back to stock snapshot.
func (p *PolygonClient) GetFuturesQuotes(symbols []string) (map[string]map[string]any, error) {
	cacheKey := "futures_quotes:" + strings.Join(symbols, ",")
	if cached, ok := p.cache.Get(cacheKey); ok {
		return cached.(map[string]map[string]any), nil
	}

	result := make(map[string]map[string]any)
	type fqResult struct {
		Symbol string
		Data   map[string]any
	}
	ch := make(chan fqResult, len(symbols))

	for _, sym := range symbols {
		go func(s string) {
			ticker := resolveFuturesTicker(s)
			now := time.Now()
			from := now.AddDate(0, 0, -7).Format("2006-01-02")
			to := now.Format("2006-01-02")
			url := fmt.Sprintf("https://api.polygon.io/futures/vX/aggs/%s?resolution=1session&window_start.gte=%s&window_start.lte=%s&limit=2&sort=window_start.desc",
				ticker, from+"T00:00:00Z", to+"T23:59:59Z")

			raw, err := p.fetch(url)
			if err != nil {
				ch <- fqResult{s, nil}
				return
			}

			// Check if unauthorized (plan doesn't include futures)
			var statusCheck struct {
				Status string `json:"status"`
			}
			json.Unmarshal(raw, &statusCheck)
			if statusCheck.Status == "NOT_AUTHORIZED" {
				ch <- fqResult{s, nil}
				return
			}

			var resp struct {
				Results []struct {
					Open            float64 `json:"open"`
					High            float64 `json:"high"`
					Low             float64 `json:"low"`
					Close           float64 `json:"close"`
					Volume          float64 `json:"volume"`
					SettlementPrice float64 `json:"settlement_price"`
				} `json:"results"`
			}
			if err := json.Unmarshal(raw, &resp); err != nil || len(resp.Results) == 0 {
				ch <- fqResult{s, nil}
				return
			}

			latest := resp.Results[0]
			price := latest.Close
			if latest.SettlementPrice > 0 {
				price = latest.SettlementPrice
			}

			prevClose := latest.Open
			if len(resp.Results) > 1 {
				prev := resp.Results[1]
				if prev.SettlementPrice > 0 {
					prevClose = prev.SettlementPrice
				} else {
					prevClose = prev.Close
				}
			}

			change := price - prevClose
			var pctChange float64
			if prevClose > 0 {
				pctChange = (change / prevClose) * 100
			}

			ch <- fqResult{s, map[string]any{
				"symbol":         s,
				"price":          price,
				"close":          price,
				"open":           latest.Open,
				"high":           latest.High,
				"low":            latest.Low,
				"volume":         latest.Volume,
				"prev_close":     prevClose,
				"change":         change,
				"percent_change": pctChange,
				"market":         "futures",
			}}
		}(sym)
	}

	for range symbols {
		r := <-ch
		if r.Data != nil {
			result[r.Symbol] = r.Data
		}
	}

	// If futures API returned nothing (unauthorized), fall back to stock snapshot
	if len(result) == 0 {
		snaps, err := p.GetSnapshotParsed(symbols)
		if err == nil {
			for sym, snap := range snaps {
				snap["market"] = "futures"
				result[sym] = snap
			}
		}
	}

	p.cache.Set(cacheKey, result, 1*time.Second)
	return result, nil
}

// ─── Helpers ─────────────────────────────────────────

func parseTimeframe(tf string) (string, string) {
	switch tf {
	case "1", "1m", "1min":
		return "1", "minute"
	case "3", "3m", "3min":
		return "3", "minute"
	case "5", "5m", "5min":
		return "5", "minute"
	case "15", "15m", "15min":
		return "15", "minute"
	case "30", "30m", "30min":
		return "30", "minute"
	case "60", "1h", "1H", "60min":
		return "1", "hour"
	case "2h":
		return "2", "hour"
	case "4h", "4H", "240":
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
