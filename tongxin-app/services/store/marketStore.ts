import { create } from 'zustand';
import type { MarketQuote, KlineBar, SearchResult, IndexQuote } from '../api/client';
import {
  fetchQuotes,
  fetchKlines,
  searchSymbols,
  fetchCryptoQuotes,
  fetchForexQuotes,
  fetchFuturesQuotes,
  fetchTickersPage,
  fetchCryptoPairs,
  fetchForexPairs,
  fetchGainers,
  fetchLosers,
  fetchNews,
  fetchIndices,
} from '../api/client';

export type { IndexQuote };

export interface NewsItem {
  headline: string;
  summary?: string;
  url?: string;
  publishedUtc?: string;
  source?: string;
  image_url?: string;
}

interface MarketState {
  // Quotes (keyed by symbol)
  quotes: Record<string, MarketQuote>;
  watchlist: string[];

  // K-line
  klines: KlineBar[];
  klinesLoading: boolean;
  klinesCache: Record<string, { data: KlineBar[]; ts: number }>;

  // Search
  searchResults: SearchResult[];
  searchLoading: boolean;

  // Gainers / Losers
  gainers: MarketQuote[];
  losers: MarketQuote[];

  // News
  news: NewsItem[];
  newsLoading: boolean;

  // Indices
  indices: IndexQuote[];
  indicesLoading: boolean;

  // Connection status
  wsConnected: boolean;

  // Actions
  loadQuotes: (symbols: string[]) => Promise<void>;
  loadCryptoQuotes: (symbols: string[]) => Promise<void>;
  loadForexQuotes: (symbols: string[]) => Promise<void>;
  loadFuturesQuotes: (symbols: string[]) => Promise<void>;
  loadKlines: (symbol: string, interval?: string) => Promise<void>;
  search: (query: string) => Promise<void>;
  clearSearch: () => void;
  loadGainersLosers: () => Promise<void>;
  loadNews: (ticker?: string) => Promise<void>;
  loadIndices: () => Promise<void>;
  updateQuote: (symbol: string, data: Partial<MarketQuote>) => void;
  updateIndex: (symbol: string, data: Partial<IndexQuote>) => void;
  setWsConnected: (connected: boolean) => void;
  addWatchlist: (symbol: string) => void;
  removeWatchlist: (symbol: string) => void;
  isInWatchlist: (symbol: string) => boolean;
}

// Map backend interval names to API format
const INTERVAL_MAP: Record<string, string> = {
  '1': '1min',
  '5': '5min',
  '15': '15min',
  '30': '30min',
  '60': '1h',
  '1D': '1day',
  '1W': '1week',
};

export const useMarketStore = create<MarketState>((set, get) => ({
  quotes: {},
  watchlist: ['BTC/USD', 'ETH/USD', 'AAPL', 'EUR/USD'],
  indices: [],
  indicesLoading: false,
  klines: [],
  klinesLoading: false,
  klinesCache: {},
  searchResults: [],
  searchLoading: false,
  gainers: [],
  losers: [],
  news: [],
  newsLoading: false,
  wsConnected: false,

  loadQuotes: async (symbols) => {
    try {
      const data = await fetchQuotes(symbols);
      const quotes = { ...get().quotes };
      for (const [sym, q] of Object.entries(data)) {
        quotes[sym] = q;
      }
      set({ quotes });
    } catch (e) {
      console.error('[Store] loadQuotes error:', e);
    }
  },

  loadCryptoQuotes: async (symbols) => {
    try {
      const data = await fetchCryptoQuotes(symbols);
      const quotes = { ...get().quotes };
      for (const [sym, q] of Object.entries(data)) {
        quotes[sym] = q;
      }
      set({ quotes });
    } catch (e) {
      console.error('[Store] loadCryptoQuotes error:', e);
    }
  },

  loadForexQuotes: async (symbols) => {
    try {
      const data = await fetchForexQuotes(symbols);
      const quotes = { ...get().quotes };
      for (const [sym, q] of Object.entries(data)) {
        quotes[sym] = q;
      }
      set({ quotes });
    } catch (e) {
      console.error('[Store] loadForexQuotes error:', e);
    }
  },

  loadFuturesQuotes: async (symbols) => {
    try {
      const data = await fetchFuturesQuotes(symbols);
      const quotes = { ...get().quotes };
      for (const [sym, q] of Object.entries(data)) {
        quotes[sym] = q;
      }
      set({ quotes });
    } catch (e) {
      console.error('[Store] loadFuturesQuotes error:', e);
    }
  },

  loadIndices: async () => {
    // Don't show loading if we already have indices (SWR: stale-while-revalidate)
    if (get().indices.length === 0) set({ indicesLoading: true });
    try {
      const data = await fetchIndices();
      set({ indices: data, indicesLoading: false });
    } catch (e) {
      console.error('[Store] loadIndices error:', e);
      set({ indicesLoading: false });
    }
  },

  loadKlines: async (symbol, interval = '1D') => {
    const apiInterval = INTERVAL_MAP[interval] || interval;
    const cacheKey = `${symbol}_${apiInterval}`;
    const cached = get().klinesCache[cacheKey];
    const CACHE_TTL = 60 * 1000; // 前端缓存60秒，避免频繁切换时间周期重复请求

    // 有缓存且未过期：直接使用，不请求
    if (cached && Date.now() - cached.ts < CACHE_TTL) {
      set({ klines: cached.data, klinesLoading: false });
      return;
    }

    // 有缓存但过期：先展示旧数据，后台刷新
    if (cached) {
      set({ klines: cached.data, klinesLoading: true });
    } else {
      set({ klines: [], klinesLoading: true });
    }

    try {
      const data = await fetchKlines(symbol, apiInterval);
      set((s) => ({
        klines: data,
        klinesLoading: false,
        klinesCache: { ...s.klinesCache, [cacheKey]: { data, ts: Date.now() } },
      }));
    } catch (e) {
      console.error('[Store] loadKlines error:', e);
      if (!cached) set({ klinesLoading: false, klines: [] });
      else set({ klinesLoading: false });
    }
  },

  search: async (query) => {
    if (!query || query.length < 1) {
      set({ searchResults: [], searchLoading: false });
      return;
    }
    set({ searchLoading: true });
    try {
      const data = await searchSymbols(query);
      set({ searchResults: data, searchLoading: false });
    } catch (e) {
      console.error('[Store] search error:', e);
      set({ searchLoading: false });
    }
  },

  clearSearch: () => set({ searchResults: [], searchLoading: false }),

  loadGainersLosers: async () => {
    try {
      const [g, l] = await Promise.allSettled([fetchGainers(), fetchLosers()]);
      set({
        gainers: g.status === 'fulfilled' ? (g.value || []).slice(0, 5) : [],
        losers: l.status === 'fulfilled' ? (l.value || []).slice(0, 5) : [],
      });
    } catch (e) {
      console.error('[Store] loadGainersLosers error:', e);
    }
  },

  loadNews: async (ticker?: string) => {
    if (get().news.length === 0) set({ newsLoading: true });
    try {
      const data = await fetchNews(ticker, 6);
      set({ news: data || [], newsLoading: false });
    } catch (e) {
      console.error('[Store] loadNews error:', e);
      set({ newsLoading: false });
    }
  },

  updateQuote: (symbol, data) => {
    const quotes = { ...get().quotes };
    const existing = quotes[symbol] || {} as MarketQuote;
    const merged = { ...existing, ...data, symbol };

    // 24h 涨跌幅：始终基于 prev_close 重新计算
    const prevClose = merged.prev_close;
    const price = merged.price;
    if (prevClose && prevClose !== 0 && price != null) {
      merged.change = price - prevClose;
      merged.percent_change = ((price - prevClose) / prevClose) * 100;
    }

    quotes[symbol] = merged;
    set({ quotes });
  },

  updateIndex: (symbol, data) => {
    const indices = get().indices.map((idx) => {
      if (idx.symbol !== symbol) return idx;
      const merged = { ...idx, ...data };
      // Recalculate change based on prev_close
      if (merged.prev_close && merged.prev_close !== 0 && merged.price != null) {
        merged.change = merged.price - merged.prev_close;
        merged.percent_change = ((merged.price - merged.prev_close) / merged.prev_close) * 100;
      }
      return merged;
    });
    set({ indices });
  },

  setWsConnected: (connected) => set({ wsConnected: connected }),

  addWatchlist: (symbol) => {
    const wl = [...get().watchlist];
    if (!wl.includes(symbol)) {
      wl.push(symbol);
      set({ watchlist: wl });
    }
  },

  removeWatchlist: (symbol) => {
    set({ watchlist: get().watchlist.filter((s) => s !== symbol) });
  },

  isInWatchlist: (symbol) => get().watchlist.includes(symbol),
}));
