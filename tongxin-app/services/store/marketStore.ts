import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
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

  // 用户在现货 / 合约页选择的 K 线周期（例如 '1min' / '15min' / '1h' / '1day'）。
  // 单独按场景存，避免合约切回现货时被覆盖。两者都走 persist，刷新不会丢。
  spotTimeframe: string;
  futuresTimeframe: string;

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
  setSpotTimeframe: (tf: string) => void;
  setFuturesTimeframe: (tf: string) => void;
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

// ─── High-frequency quote update batching ─────────────────────────
// WS pushes can fire 100+ times/second. We coalesce multiple updateQuote()
// calls for different symbols into a single set({ quotes }) every QUOTE_FLUSH_MS.
// This dramatically reduces React re-render pressure without changing the
// public updateQuote API — callers simply see a <= 50ms delay before the
// store reflects the latest value.
const QUOTE_FLUSH_MS = 50;
const pendingQuoteUpdates: Record<string, Partial<MarketQuote>> = {};
let quoteFlushTimer: ReturnType<typeof setTimeout> | null = null;

// ─── Persistent quote cache ───────────────────────────────────────
// Persists the current quote map to AsyncStorage so the symbol dropdown
// (and other surfaces) show prices immediately on next app launch instead
// of flashing `--` until REST responds. Writes are debounced; reads happen
// once at module load and live values always win over cache.
const QUOTE_CACHE_KEY = 'tongxin_quotes_v1';
const QUOTE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const QUOTE_PERSIST_DEBOUNCE_MS = 2000;
let persistTimer: ReturnType<typeof setTimeout> | null = null;

function schedulePersistQuotes(quotes: Record<string, MarketQuote>) {
  // Debounce: one pending timer at a time. Captures the quotes ref at fire time.
  if (persistTimer) return;
  persistTimer = setTimeout(() => {
    persistTimer = null;
    try {
      const payload = JSON.stringify({ quotes, ts: Date.now() });
      AsyncStorage.setItem(QUOTE_CACHE_KEY, payload).catch(() => {});
    } catch {
      // JSON serialize failure (circular etc.) — non-fatal, skip this persist
    }
  }, QUOTE_PERSIST_DEBOUNCE_MS);
}

// ─── Watchlist + timeframe persistence ────────────────────────────
// 不能用 zustand/middleware 的 persist：它的 devtools 路径里用到了 import.meta，
// Metro 把整个 web bundle 作为 <script> 加载，遇到 import.meta 会直接 SyntaxError
// 让整个 bundle 挂掉（白屏）。因此自己做手动 hydrate + 写时落盘。
// 存储字段：watchlist / spotTimeframe / futuresTimeframe。
const DEFAULT_WATCHLIST = ['BTC/USD', 'ETH/USD', 'AAPL', 'EUR/USD'];
const WATCHLIST_STORAGE_KEY = 'tongxin_market_v2';
const LEGACY_WATCHLIST_KEY = 'tongxin_watchlist_v1'; // 旧版只存纯数组 JSON

interface PersistedMarketShape {
  watchlist?: unknown;
  spotTimeframe?: unknown;
  futuresTimeframe?: unknown;
}

// 落盘防抖：多个 setXxx 连续触发时合并一次写。
let persistStateTimer: ReturnType<typeof setTimeout> | null = null;
function schedulePersistState() {
  if (persistStateTimer) return;
  persistStateTimer = setTimeout(() => {
    persistStateTimer = null;
    try {
      const s = useMarketStore.getState();
      const payload = JSON.stringify({
        watchlist: s.watchlist,
        spotTimeframe: s.spotTimeframe,
        futuresTimeframe: s.futuresTimeframe,
      });
      AsyncStorage.setItem(WATCHLIST_STORAGE_KEY, payload).catch((e) => {
        console.warn('[marketStore] persist state failed:', e);
      });
    } catch (e) {
      console.warn('[marketStore] persist state serialize failed:', e);
    }
  }, 200);
}

export const useMarketStore = create<MarketState>((set, get) => ({
  quotes: {},
  watchlist: DEFAULT_WATCHLIST,
  spotTimeframe: '1h',
  futuresTimeframe: '1h',
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
      schedulePersistQuotes(quotes);
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
      schedulePersistQuotes(quotes);
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
      schedulePersistQuotes(quotes);
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
      schedulePersistQuotes(quotes);
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
    // Coalesce into pending batch; flush together every QUOTE_FLUSH_MS.
    const existing = pendingQuoteUpdates[symbol] || {};
    pendingQuoteUpdates[symbol] = { ...existing, ...data };

    if (quoteFlushTimer != null) return;
    quoteFlushTimer = setTimeout(() => {
      quoteFlushTimer = null;
      const symbols = Object.keys(pendingQuoteUpdates);
      if (symbols.length === 0) return;
      const quotes = { ...get().quotes };
      for (const sym of symbols) {
        const patch = pendingQuoteUpdates[sym];
        delete pendingQuoteUpdates[sym];
        const prev = quotes[sym] || ({} as MarketQuote);
        const merged = { ...prev, ...patch, symbol: sym } as MarketQuote;
        // 24h 涨跌幅：始终基于 prev_close 重新计算
        const prevClose = merged.prev_close;
        const price = merged.price;
        if (prevClose && prevClose !== 0 && price != null) {
          merged.change = price - prevClose;
          merged.percent_change = ((price - prevClose) / prevClose) * 100;
        }
        quotes[sym] = merged;
      }
      set({ quotes });
      schedulePersistQuotes(quotes);
    }, QUOTE_FLUSH_MS);
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
    if (!symbol || typeof symbol !== 'string') return;
    const wl = get().watchlist;
    if (wl.includes(symbol)) return;
    set({ watchlist: [...wl, symbol] });
    schedulePersistState();
  },

  removeWatchlist: (symbol) => {
    const wl = get().watchlist;
    if (!wl.includes(symbol)) return;
    set({ watchlist: wl.filter((s) => s !== symbol) });
    schedulePersistState();
  },

  isInWatchlist: (symbol) => get().watchlist.includes(symbol),

  setSpotTimeframe: (tf) => {
    if (!tf || typeof tf !== 'string') return;
    if (get().spotTimeframe === tf) return;
    set({ spotTimeframe: tf });
    schedulePersistState();
  },

  setFuturesTimeframe: (tf) => {
    if (!tf || typeof tf !== 'string') return;
    if (get().futuresTimeframe === tf) return;
    set({ futuresTimeframe: tf });
    schedulePersistState();
  },
}));

// ─── Hydrate persisted state on module load ───────────────────────
// 异步读 AsyncStorage，把 watchlist / spotTimeframe / futuresTimeframe 恢复进 store。
// 合并策略：只有 persisted 有有效值才覆盖默认；空数组 / 空串 走默认。
// 同时兼容老 key tongxin_watchlist_v1（纯数组 JSON）。
(async () => {
  try {
    const raw = await AsyncStorage.getItem(WATCHLIST_STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as PersistedMarketShape;
      const patch: Partial<MarketState> = {};
      if (Array.isArray(parsed.watchlist)) {
        const valid = (parsed.watchlist as unknown[]).filter(
          (s): s is string => typeof s === 'string' && s.trim().length > 0,
        );
        if (valid.length > 0) patch.watchlist = valid;
      }
      if (typeof parsed.spotTimeframe === 'string' && parsed.spotTimeframe) {
        patch.spotTimeframe = parsed.spotTimeframe;
      }
      if (typeof parsed.futuresTimeframe === 'string' && parsed.futuresTimeframe) {
        patch.futuresTimeframe = parsed.futuresTimeframe;
      }
      if (Object.keys(patch).length > 0) {
        useMarketStore.setState(patch);
      }
    } else {
      // 迁移：老版本把 watchlist 单独存在 tongxin_watchlist_v1 里（纯数组）
      const legacy = await AsyncStorage.getItem(LEGACY_WATCHLIST_KEY);
      if (legacy) {
        const arr = JSON.parse(legacy);
        if (Array.isArray(arr)) {
          const valid = arr.filter(
            (s: unknown): s is string => typeof s === 'string' && s.trim().length > 0,
          );
          if (valid.length > 0) {
            useMarketStore.setState({ watchlist: valid });
            schedulePersistState();
            AsyncStorage.removeItem(LEGACY_WATCHLIST_KEY).catch(() => {});
          }
        }
      }
    }
  } catch (e) {
    console.warn('[marketStore] hydrate failed:', e);
  }
})();

// ─── Hydrate persisted quotes on module load ──────────────────────
// Non-blocking. Live values (from REST/WS after app start) always win;
// we only fill in symbols that haven't been refreshed yet. Expired
// cache is discarded silently.
(async () => {
  try {
    const raw = await AsyncStorage.getItem(QUOTE_CACHE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw) as { quotes?: Record<string, MarketQuote>; ts?: number };
    if (!parsed?.quotes || !parsed.ts) return;
    if (Date.now() - parsed.ts > QUOTE_CACHE_TTL_MS) {
      AsyncStorage.removeItem(QUOTE_CACHE_KEY).catch(() => {});
      return;
    }
    useMarketStore.setState((s) => ({
      quotes: { ...parsed.quotes, ...s.quotes },
    }));
  } catch {
    // Corrupt payload — drop it so next write starts fresh
    AsyncStorage.removeItem(QUOTE_CACHE_KEY).catch(() => {});
  }
})();

