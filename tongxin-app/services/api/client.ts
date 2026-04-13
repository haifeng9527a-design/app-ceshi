import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Config } from '../config';

const TOKEN_KEY = 'tongxin_jwt_token';

/**
 * Get stored JWT token
 */
export async function getStoredToken(): Promise<string | null> {
  try {
    return await AsyncStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

/**
 * Save JWT token
 */
export async function saveToken(token: string): Promise<void> {
  await AsyncStorage.setItem(TOKEN_KEY, token);
}

/**
 * Clear stored JWT token
 */
export async function clearToken(): Promise<void> {
  await AsyncStorage.removeItem(TOKEN_KEY);
}

/**
 * Axios API client with JWT token interceptor
 */
const apiClient = axios.create({
  baseURL: Config.API_BASE_URL,
  timeout: 15000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Attach JWT token to authenticated requests
apiClient.interceptors.request.use(async (config) => {
  try {
    const token = await getStoredToken();
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
  } catch {
    // Non-blocking: market APIs work without auth
  }
  return config;
});

// Response error handling
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error('[API Error]', error.response?.status, error.message);
    return Promise.reject(error);
  }
);

export default apiClient;

// ─── Index Constants ─────────────────────────────────

const INDEX_SYMBOLS = ['DJI', 'SPX', 'IXIC', 'VIX'];
const INDEX_DISPLAY: Record<string, string> = {
  DJI: 'DOW JONES',
  SPX: 'S&P 500',
  IXIC: 'NASDAQ',
  VIX: 'VIX VOLATILITY',
};

// ─── Types ────────────────────────────────────────────

export interface IndexQuote {
  symbol: string;
  name: string;        // display name: "DOW JONES"
  price: number;
  change: number;
  percent_change: number;
  prev_close?: number;
}

export interface MarketQuote {
  symbol: string;
  name?: string;
  price: number;
  change: number;
  percent_change: number;
  high?: number;
  low?: number;
  open?: number;
  prev_close?: number;
  volume?: number;
  market?: string;
  timestamp?: number;
}

export interface KlineBar {
  time: number; // Unix timestamp (seconds) for LW Charts
  open: number;
  high: number;
  low: number;
  close: number;
  volume?: number;
}

export interface SearchResult {
  symbol: string;  // normalized (from ticker field)
  name: string;
  type?: string;
  market?: string;
}

/** Raw search response from backend uses `ticker` field */
interface RawSearchResult {
  ticker: string;
  name: string;
  type?: string;
  market?: string;
}

export interface TickerPageResult {
  items: MarketQuote[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

// ─── Market API ───────────────────────────────────────

/**
 * Fetch quotes for a list of symbols
 * GET /api/quotes?symbols=AAPL,BTC/USD
 * Returns: { "AAPL": { symbol, price, change, percent_change, ... } }
 */
export async function fetchQuotes(symbols: string[]): Promise<Record<string, MarketQuote>> {
  const { data } = await apiClient.get('/api/quotes', {
    params: { symbols: symbols.join(',') },
  });
  // Normalize: backend may use `close` for price
  const normalized: Record<string, MarketQuote> = {};
  for (const [sym, raw] of Object.entries(data as Record<string, any>)) {
    normalized[sym] = {
      symbol: raw.symbol ?? sym,
      price: raw.price ?? raw.close,
      change: raw.change,
      percent_change: raw.percent_change,
      prev_close: raw.prev_close,
      open: raw.open,
      high: raw.high,
      low: raw.low,
      volume: raw.volume,
      market: raw.market ?? 'stocks',
    };
  }
  return normalized;
}

/**
 * Fetch K-line / candle data
 * GET /api/candles?symbol=AAPL&interval=1day
 * Returns: [{ t, o, h, l, c, v }, ...]
 */
export async function fetchKlines(
  symbol: string,
  interval: string = '1day',
  fromMs?: number,
  toMs?: number
): Promise<KlineBar[]> {
  const { data } = await apiClient.get('/api/candles', {
    params: { symbol, interval, fromMs, toMs },
  });
  // Transform backend format { t, o, h, l, c, v } → { time, open, high, low, close, volume }
  return (data || []).map((bar: any) => ({
    time: Math.floor(bar.t / 1000), // ms → seconds for LW Charts
    open: bar.o,
    high: bar.h,
    low: bar.l,
    close: bar.c,
    volume: bar.v,
  }));
}

/**
 * Fetch funding rate from Binance
 * GET /api/funding-rate?symbol=BTC/USD
 */
export async function fetchFundingRate(symbol: string) {
  try {
    const { data } = await apiClient.get('/api/funding-rate', { params: { symbol } });
    return data;
  } catch {
    return { fundingRate: null };
  }
}

/**
 * Search symbols
 * GET /api/search?q=apple
 * Returns: [{ symbol, name, type, market }, ...]
 */
export async function searchSymbols(query: string): Promise<SearchResult[]> {
  const { data } = await apiClient.get('/api/search', {
    params: { q: query },
  });
  // Backend returns `ticker` field, normalize to `symbol`
  return (data || []).map((item: RawSearchResult) => ({
    symbol: item.ticker,
    name: item.name,
    type: item.type,
    market: item.market,
  }));
}

/**
 * Fetch paginated stock list with quotes
 * GET /api/tickers-page?page=1&pageSize=30&sortColumn=pct
 */
export async function fetchTickersPage(
  page: number = 1,
  pageSize: number = 30,
  sortColumn: string = 'pct'
): Promise<TickerPageResult> {
  const { data } = await apiClient.get('/api/tickers-page', {
    params: { page, pageSize, sortColumn },
  });
  return data;
}

/**
 * Fetch crypto pairs list
 * GET /api/crypto/pairs?page=1&pageSize=30
 */
export async function fetchCryptoPairs(page = 1, pageSize = 30): Promise<TickerPageResult> {
  const { data } = await apiClient.get('/api/crypto/pairs', {
    params: { page, pageSize },
  });
  return data;
}

/**
 * Fetch crypto quotes
 * GET /api/crypto/quotes?symbols=BTC/USD,ETH/USD
 */
export async function fetchCryptoQuotes(symbols: string[]): Promise<Record<string, MarketQuote>> {
  const { data } = await apiClient.get('/api/crypto/quotes', {
    params: { symbols: symbols.join(',') },
  });
  // Normalize: backend uses `close` for current price
  const normalized: Record<string, MarketQuote> = {};
  for (const [sym, raw] of Object.entries(data as Record<string, any>)) {
    normalized[sym] = {
      symbol: raw.symbol,
      price: raw.close ?? raw.price,
      change: raw.change,
      percent_change: raw.percent_change,
      prev_close: raw.prev_close,
      open: raw.open,
      high: raw.high,
      low: raw.low,
      volume: raw.volume,
      market: 'crypto',
    };
  }
  return normalized;
}

/**
 * Fetch forex pairs list
 * GET /api/forex/pairs?page=1&pageSize=30
 */
export async function fetchForexPairs(page = 1, pageSize = 30): Promise<TickerPageResult> {
  const { data } = await apiClient.get('/api/forex/pairs', {
    params: { page, pageSize },
  });
  return data;
}

/**
 * Fetch forex quotes
 * GET /api/forex/quotes?symbols=EUR/USD,GBP/USD
 */
export async function fetchForexQuotes(symbols: string[]): Promise<Record<string, MarketQuote>> {
  const { data } = await apiClient.get('/api/forex/quotes', {
    params: { symbols: symbols.join(',') },
  });
  // Normalize field names
  const normalized: Record<string, MarketQuote> = {};
  for (const [sym, raw] of Object.entries(data as Record<string, any>)) {
    normalized[sym] = {
      symbol: raw.symbol ?? sym,
      price: raw.close ?? raw.price,
      change: raw.change,
      percent_change: raw.percent_change,
      prev_close: raw.prev_close,
      open: raw.open,
      high: raw.high,
      low: raw.low,
      volume: raw.volume,
      market: 'forex',
    };
  }
  return normalized;
}

/**
 * Fetch futures quotes
 * GET /api/futures/quotes?symbols=ES,NQ,GC,CL
 */
export async function fetchFuturesQuotes(symbols: string[]): Promise<Record<string, MarketQuote>> {
  const { data } = await apiClient.get('/api/futures/quotes', {
    params: { symbols: symbols.join(',') },
  });
  const normalized: Record<string, MarketQuote> = {};
  for (const [sym, raw] of Object.entries(data as Record<string, any>)) {
    normalized[sym] = {
      symbol: raw.symbol ?? sym,
      price: raw.price ?? raw.close,
      change: raw.change,
      percent_change: raw.percent_change,
      prev_close: raw.prev_close,
      open: raw.open,
      high: raw.high,
      low: raw.low,
      volume: raw.volume,
      market: 'futures',
    };
  }
  return normalized;
}

/**
 * Top gainers
 * GET /api/gainers
 */
export async function fetchGainers(): Promise<MarketQuote[]> {
  const { data } = await apiClient.get('/api/gainers');
  return data;
}

/**
 * Top losers
 * GET /api/losers
 */
export async function fetchLosers(): Promise<MarketQuote[]> {
  const { data } = await apiClient.get('/api/losers');
  return data;
}

/**
 * Crypto order book depth
 * GET /api/crypto/depth?symbol=BTC/USD&limit=5
 */
export async function fetchCryptoDepth(symbol: string, limit = 5) {
  const { data } = await apiClient.get('/api/crypto/depth', {
    params: { symbol, limit },
  });
  return data;
}

/**
 * News
 * GET /api/news?ticker=AAPL&limit=20
 */
export async function fetchNews(ticker?: string, limit = 20) {
  const { data } = await apiClient.get(ticker ? '/api/news' : '/api/news/hot', {
    params: ticker ? { ticker, limit } : { limit },
  });
  return data;
}

/**
 * Fetch major indices (DJI, SPX, IXIC, VIX)
 * Uses /api/quotes with index symbols, falls back to /api/market/snapshots
 */
export async function fetchIndices(): Promise<IndexQuote[]> {
  try {
    const { data } = await apiClient.get('/api/quotes', {
      params: { symbols: INDEX_SYMBOLS.join(',') },
    });
    const result: IndexQuote[] = [];
    for (const sym of INDEX_SYMBOLS) {
      const raw = (data as Record<string, any>)[sym];
      if (raw && (raw.close > 0 || raw.price > 0)) {
        result.push({
          symbol: sym,
          name: INDEX_DISPLAY[sym] || sym,
          price: raw.close ?? raw.price ?? 0,
          change: raw.change ?? 0,
          percent_change: raw.percent_change ?? 0,
          prev_close: raw.prev_close,
        });
      }
    }
    if (result.length >= 2) return result;
  } catch (e) {
    console.warn('[API] fetchIndices primary failed, trying snapshot fallback');
  }

  // Fallback: market snapshots
  try {
    const { data } = await apiClient.get('/api/market/snapshots', {
      params: { type: 'indices' },
    });
    if (Array.isArray(data) && data.length > 0) {
      return data.map((r: any) => ({
        symbol: r.symbol,
        name: INDEX_DISPLAY[r.symbol] || r.name || r.symbol,
        price: r.close ?? r.price ?? 0,
        change: r.change ?? 0,
        percent_change: r.percent_change ?? 0,
        prev_close: r.prev_close,
      }));
    }
  } catch (e) {
    console.warn('[API] fetchIndices snapshot fallback also failed');
  }

  return [];
}

// ── VIP & Fee ──

export interface VipFeeRate {
  level: number;
  maker_fee: number;
  taker_fee: number;
}

export interface VipInfo {
  vip_level: number;
  maker_fee: number;
  taker_fee: number;
}

export async function fetchFeeSchedule(): Promise<VipFeeRate[]> {
  const { data } = await apiClient.get('/api/trading/fee-schedule');
  return data;
}

export async function fetchVipInfo(): Promise<VipInfo> {
  const { data } = await apiClient.get('/api/trading/vip-info');
  return data;
}
