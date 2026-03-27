/**
 * 行情代理路由：/api/quotes 按 symbol 缓存 + 批量查/补拉；其余接口仍用 getOrStale/set
 */
const { get, getOrStale, set, DEFAULT_TTL_MS } = require('./cache');
const { resolve, isCrypto, isUsStock } = require('./symbolResolver');
const polygon = require('./polygon');
const { getBatchSnapshotsV2, getBatchSnapshotsV3, V2_SNAPSHOT_BATCH_SIZE, V3_SNAPSHOT_BATCH_SIZE } = polygon;
const twelveData = require('./twelveData');
const binance = require('./binance');
const db = require('./db');
const quoteStore = require('./quoteStore');
const singleFlight = require('./singleFlight');
const rateLimiter = require('./rateLimiter');
const {
  POLYGON_RATE_LIMIT_PER_SEC,
  POLYGON_BATCH_SIZE,
  QUOTE_FETCH_TIMEOUT_MS,
  PARTIAL_THRESHOLD,
} = require('./config');
const quoteFetcher = require('./quoteFetcher');
const supabaseQuoteCache = require('./supabaseQuoteCache');
const supabaseClient = require('./supabaseClient');
const forexScheduler = require('./forexScheduler');
const supabaseForexCache = require('./supabaseForexCache');
const cryptoScheduler = require('./cryptoScheduler');
const supabaseCryptoCache = require('./supabaseCryptoCache');

const toQuoteSnapshot = quoteFetcher.toQuoteSnapshot;

/** 休市/接口无数据时：用 Supabase stock_quote_cache 表备份覆盖，最多取 24 小时内更新过的 */
const SUPABASE_FALLBACK_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const fetchOneQuote = quoteFetcher.fetchOneQuote;
const STOCK_24H_SYMBOLS = new Set(
  String(process.env.STOCK_24H_SYMBOLS || '')
    .split(/[,\s;|]+/)
    .map((s) => s.trim().toUpperCase())
    .filter(Boolean)
);

/** Supabase crypto_pair_cache 未配置时 /api/crypto/pairs 的静态兜底列表 */
const CRYPTO_PAIRS_FALLBACK = [
  { symbol: 'BTC/USD', name: 'Bitcoin' },
  { symbol: 'ETH/USD', name: 'Ethereum' },
  { symbol: 'SOL/USD', name: 'Solana' },
  { symbol: 'XRP/USD', name: 'XRP' },
  { symbol: 'DOGE/USD', name: 'Dogecoin' },
  { symbol: 'BNB/USD', name: 'BNB' },
  { symbol: 'ADA/USD', name: 'Cardano' },
  { symbol: 'AVAX/USD', name: 'Avalanche' },
  { symbol: 'DOT/USD', name: 'Polkadot' },
  { symbol: 'LINK/USD', name: 'Chainlink' },
  { symbol: 'LTC/USD', name: 'Litecoin' },
  { symbol: 'BCH/USD', name: 'Bitcoin Cash' },
  { symbol: 'TRX/USD', name: 'TRON' },
  { symbol: 'UNI/USD', name: 'Uniswap' },
  { symbol: 'ATOM/USD', name: 'Cosmos' },
  { symbol: 'MATIC/USD', name: 'Polygon' },
  { symbol: 'ARB/USD', name: 'Arbitrum' },
  { symbol: 'OP/USD', name: 'Optimism' },
];

function createRequireAdminRole() {
  return async (req, res, next) => {
    if (req.isAdminByKey === true || req.isAdminSession === true) return next();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('user_profiles')
        .select('role')
        .eq('user_id', uid)
        .maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      const role = String(data?.role || '').toLowerCase();
      if (role !== 'admin' && role !== 'customer_service_admin') {
        return res.status(403).json({ error: 'forbidden' });
      }
      return next();
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  };
}

function hasUsableQuotePayload(payload) {
  return !!payload && Number(payload.close) > 0 && !payload.error_reason;
}

/** GET /api/quotes?symbols=AAPL,MSFT,... — 按 symbol 缓存，批量查 + 只补缺失/过期
 *  若 symbols=单只&realtime=1：跳过缓存，直连 Polygon 取实时数据（供详情页使用）
 */
async function handleQuotes(req, res, polygonKey, twelveKey) {
  const raw = req.query.symbols;
  if (!raw || typeof raw !== 'string') {
    return res.status(400).json({ error: 'missing symbols' });
  }
  const symbols = [...new Set(raw.split(',').map((s) => s.trim().toUpperCase()).filter(Boolean))];
  if (symbols.length === 0) {
    return res.json({});
  }

  const realtime = req.query.realtime === '1' || req.query.realtime === 'true';
  if (realtime && symbols.length === 1) {
    const sym = symbols[0];
    const r = resolve(sym);
    if (isCrypto(sym)) {
      try {
        const liveMap = await binance.getQuotes([binance.toBinanceSymbol(sym)]);
        const q = liveMap.get(binance.toBinanceSymbol(sym));
        const snap = q
          ? toQuoteSnapshot({ ...q, symbol: sym })
          : toQuoteSnapshot({ symbol: sym, price: 0, change: 0, changePercent: 0, error_reason: 'Binance 无数据' });
        return res.json({ [sym]: snap });
      } catch (e) {
        const snap = toQuoteSnapshot({ symbol: sym, price: 0, change: 0, changePercent: 0, error_reason: String(e.message || e) });
        return res.json({ [sym]: snap });
      }
    }
    if (polygonKey) {
    if (r.usePolygon) {
      try {
        const [snapshot, quote, prevBar] = await Promise.all([
          polygon.getTickerSnapshot(polygonKey, r.polygon),
          polygon.getQuote(polygonKey, r.polygon),
          polygon.getPrevDayBar(polygonKey, r.polygon),
        ]);
        // 单标的 realtime=1：现价优先使用 last trade，更贴近成交明细；其余字段继续复用 snapshot/day 信息。
        let q = {
          ...snapshot,
          symbol: sym,
          price: quote?.price > 0
            ? quote.price
            : (snapshot?.price > 0 ? snapshot.price : (prevBar?.c || 0)),
          change: quote?.price > 0
            ? (quote.change ?? snapshot?.change ?? 0)
            : (snapshot?.change ?? quote?.change ?? 0),
          changePercent: quote?.price > 0
            ? (quote.changePercent ?? snapshot?.changePercent ?? 0)
            : (snapshot?.changePercent ?? quote?.changePercent ?? 0),
          prevClose: snapshot?.prevClose ?? (prevBar?.c ?? null),
          open: snapshot?.open ?? (prevBar?.o ?? null),
          high: snapshot?.high ?? (prevBar?.h ?? null),
          low: snapshot?.low ?? (prevBar?.l ?? null),
          volume: snapshot?.volume ?? (prevBar?.v ?? null),
        };
        if (!q.price || q.price <= 0) {
          q = {
            symbol: sym,
            price: quote?.price || prevBar?.c || 0,
            change: quote?.change ?? 0,
            changePercent: quote?.changePercent ?? 0,
            prevClose: prevBar?.c ?? (quote?.price > 0 ? quote.price - (quote.change ?? 0) : null),
            open: prevBar?.o ?? null,
            high: prevBar?.h ?? null,
            low: prevBar?.l ?? null,
            volume: prevBar?.v ?? null,
          };
        }
        const snap = toQuoteSnapshot({ ...q, symbol: sym });
        quoteStore.setQuotesBatch([{ symbol: sym, payload: snap, priority: 0 }]);
        return res.json({ [sym]: snap });
      } catch (e) {
        const snap = toQuoteSnapshot({ symbol: sym, price: 0, change: 0, changePercent: 0, error_reason: String(e.message || e) });
        return res.json({ [sym]: snap });
      }
    }
    }
  }

  db.touchMetaSymbols(symbols, 2);
  const metaMap = db.getMetaBySymbols(symbols);
  const { hit, miss } = await quoteStore.getQuotesBatch(symbols, metaMap);

  const out = {};
  const invalidHitSymbols = [];
  for (const [s, payload] of hit) {
    if (isUsStock(s) && !hasUsableQuotePayload(payload)) {
      invalidHitSymbols.push(s);
      continue;
    }
    out[s] = payload;
  }

  const polygonToFetch = [];
  const twelveToFetch = [];
  const binanceToFetch = [];
  for (const s of [...invalidHitSymbols, ...miss]) {
    const r = resolve(s);
    if (!r.usePolygon && !r.useTwelve) {
      out[s] = toQuoteSnapshot({ symbol: s, price: 0, change: 0, changePercent: 0, error_reason: '无法解析 symbol' });
      continue;
    }
    if (isCrypto(s)) {
      binanceToFetch.push({
        original: s,
        binance: binance.toBinanceSymbol(s),
      });
      continue;
    }
    if (r.usePolygon && polygonKey) polygonToFetch.push({ original: s, polygon: r.polygon });
    if (r.useTwelve && twelveKey) twelveToFetch.push({ original: s, twelve: r.twelve });
  }

  if (binanceToFetch.length > 0) {
    try {
      const liveMap = await binance.getQuotes(binanceToFetch.map((x) => x.binance));
      const entries = [];
      for (const { original, binance: binanceSymbol } of binanceToFetch) {
        const q = liveMap.get(binanceSymbol);
        const snap = q
          ? toQuoteSnapshot({ ...q, symbol: original })
          : toQuoteSnapshot({ symbol: original, price: 0, change: 0, changePercent: 0, error_reason: 'Binance 无数据' });
        out[original] = snap;
        entries.push({ symbol: original, payload: snap, priority: 2 });
      }
      if (entries.length > 0) quoteStore.setQuotesBatch(entries);
    } catch (e) {
      for (const { original } of binanceToFetch) {
        out[original] = toQuoteSnapshot({ symbol: original, price: 0, change: 0, changePercent: 0, error_reason: String(e.message || e) });
      }
    }
  }

  if (twelveToFetch.length && twelveKey) {
    const twelveList = [...new Set(twelveToFetch.map((x) => x.twelve))];
    try {
      const tdMap = await twelveData.getQuotes(twelveKey, twelveList);
      const entries = [];
      for (const { original, twelve } of twelveToFetch) {
        const q = tdMap[twelve];
        const snap = q
          ? toQuoteSnapshot({
              symbol: original,
              price: q.close,
              change: q.change,
              changePercent: q.percent_change,
              open: q.open,
              high: q.high,
              low: q.low,
              volume: q.volume,
            })
          : toQuoteSnapshot({ symbol: original, price: 0, change: 0, changePercent: 0, error_reason: 'Twelve Data 无数据' });
        out[original] = snap;
        entries.push({ symbol: original, payload: snap, priority: 2 });
      }
      quoteStore.setQuotesBatch(entries);
    } catch (e) {
      for (const { original } of twelveToFetch) {
        if (!out[original]) {
          out[original] = toQuoteSnapshot({ symbol: original, price: 0, change: 0, changePercent: 0, error_reason: String(e.message || e) });
        }
      }
    }
  } else if (twelveToFetch.length) {
    for (const { original } of twelveToFetch) {
      out[original] = toQuoteSnapshot({ symbol: original, price: 0, change: 0, changePercent: 0, error_reason: '未配置 TWELVE_DATA_API_KEY' });
    }
  }

  if (!polygonKey) {
    for (const { original } of polygonToFetch) {
      if (!out[original]) {
        out[original] = toQuoteSnapshot({ symbol: original, price: 0, change: 0, changePercent: 0, error_reason: '未配置 POLYGON_API_KEY' });
      }
    }
  } else if (polygonToFetch.length > 0) {
    const needRatio = polygonToFetch.length / symbols.length;
    /** 有缺失就优先用批量 Snapshot（v2 含 day/prevDay 能拿全今开/最高/最低/量），再对未命中做单只补拉 */
    const USE_BATCH_THRESHOLD = 1;
    /** 使用批量时不等先快返，等批量拉完再返回，保证 PC/Web 首包就有今开/最高/最低/量 */
    const useBatch = polygonToFetch.length >= USE_BATCH_THRESHOLD;
    const doPartial = useBatch ? false : needRatio > PARTIAL_THRESHOLD;

    const runPolygonFetch = async () => {
      const entries = [];
      let toFetch = [...polygonToFetch];

      if (toFetch.length >= USE_BATCH_THRESHOLD) {
        const batchSize = V2_SNAPSHOT_BATCH_SIZE;
        for (let i = 0; i < toFetch.length; i += batchSize) {
          const chunk = toFetch.slice(i, i + batchSize);
          const symbolsForApi = chunk.map((x) => x.polygon);
          let batchMap = await getBatchSnapshotsV2(polygonKey, symbolsForApi);
          if (batchMap.size === 0) {
            batchMap = await getBatchSnapshotsV3(polygonKey, symbolsForApi);
          }
          for (const item of chunk) {
            const data = batchMap.get(item.polygon);
            if (data != null) {
              const snap = toQuoteSnapshot({ ...data, symbol: item.original });
              out[item.original] = snap;
              entries.push({ symbol: item.original, payload: snap, priority: 2 });
            }
          }
          await rateLimiter.acquire();
        }
        toFetch = toFetch.filter((item) => out[item.original] == null);
      }

      if (toFetch.length > 0) {
        const concurrency = Math.min(POLYGON_RATE_LIMIT_PER_SEC, 5);
        const list = [...toFetch];
        await Promise.all(
          Array(concurrency)
            .fill(0)
            .map(async () => {
              while (list.length > 0) {
                const item = list.shift();
                if (!item) break;
                await rateLimiter.acquire();
                const snap = await singleFlight.getOrInflight(`quote:${item.original}`, () =>
                  fetchOneQuote(polygonKey, item.original, item.polygon)
                );
                out[item.original] = snap;
                entries.push({ symbol: item.original, payload: snap, priority: 2 });
              }
            })
        );
      }
      if (entries.length > 0) quoteStore.setQuotesBatch(entries);
    };

    if (doPartial) {
      const ordered = {};
      for (const s of symbols) {
        if (out[s] !== undefined) ordered[s] = out[s];
      }
      // 仅当已有缓存/其他源数据时才先快返；否则首屏会拿到空对象，列表全显示「—」
      if (Object.keys(ordered).length > 0) {
        ordered.partial = true;
        ordered.missingSymbols = polygonToFetch.map((x) => x.original);
        ordered.serverTimeMs = Date.now();
        res.json(ordered);
        runPolygonFetch().catch(() => {});
        return;
      }
    }

    await runPolygonFetch();
  }

  // 休市或 Polygon 无当日/昨收时：从 Supabase stock_quote_cache 取备份（24 小时内更新过的），覆盖无有效价格的项
  const needFallback = symbols.filter(
    (s) => out[s] && (out[s].close == null || Number(out[s].close) <= 0 || (out[s].error_reason && String(out[s].error_reason).trim().length > 0))
  );
  if (needFallback.length > 0 && supabaseQuoteCache.isConfigured()) {
    try {
      const fromSupabase = await supabaseQuoteCache.getBySymbols(needFallback, SUPABASE_FALLBACK_MAX_AGE_MS);
      for (const s of needFallback) {
        const row = fromSupabase.get(s);
        if (row && row.payload && row.payload.close != null && Number(row.payload.close) > 0) {
          out[s] = row.payload;
        }
      }
    } catch (_) {}
  }

  const ordered = {};
  for (const s of symbols) {
    if (out[s] !== undefined) ordered[s] = out[s];
  }
  res.json(ordered);
}

// 日/周/月 K 线默认范围：2 年，首屏响应控制在数秒内；需更多历史可由前端「加载更多」分页请求
const CANDLES_RANGE_YEARS = 2;
const CANDLES_DAY_MS = CANDLES_RANGE_YEARS * 365.25 * 24 * 60 * 60 * 1000;
const CANDLES_WEEK_MS = CANDLES_RANGE_YEARS * 365.25 * 24 * 60 * 60 * 1000;
const CANDLES_MONTH_MS = CANDLES_RANGE_YEARS * 365.25 * 24 * 60 * 60 * 1000;
const CANDLES_YEAR_MS = 20 * 365.25 * 24 * 60 * 60 * 1000; // 年K 默认 20 年

/** GET /api/candles?symbol=AAPL&interval=1day|1week|1month|5min|1min|1h
 *  可选 fromMs, toMs（毫秒时间戳）用于「加载更早」分页，不传则默认最近 CANDLES_RANGE_YEARS */
async function handleCandles(req, res, polygonKey, twelveKey) {
  const symbol = req.query.symbol?.trim();
  const interval = (req.query.interval || '1day').toLowerCase();
  if (!symbol) return res.status(400).json({ error: 'missing symbol' });

  const r = resolve(symbol);
  const now = Date.now();
  let toMs = now;
  let fromMs = now - 24 * 60 * 60 * 1000;
  const hasRange = req.query.fromMs != null && req.query.toMs != null;
  if (hasRange) {
    toMs = Math.min(now, parseInt(req.query.toMs, 10) || now);
    fromMs = parseInt(req.query.fromMs, 10) || fromMs;
    if (fromMs >= toMs) return res.status(400).json({ error: 'fromMs must be less than toMs' });
  } else {
    if (interval === '1day') fromMs = now - CANDLES_DAY_MS;
    else if (interval === '1week') fromMs = now - CANDLES_WEEK_MS;
    else if (interval === '1month') fromMs = now - CANDLES_MONTH_MS;
    else if (interval === '1year') fromMs = now - CANDLES_YEAR_MS;
    else if (interval === '1h') fromMs = now - 72 * 60 * 60 * 1000;
  }

  const cacheKey = hasRange
    ? `candles_${r.polygon || r.twelve}_${interval}_${fromMs}_${toMs}`
    : `candles_${r.polygon || r.twelve}_${interval}`;
  // K线必须避免读取长期陈旧的 DB stale 缓存，否则会出现“当前价与图上差很多”的问题。
  const cached = get(cacheKey);
  if (cached) return res.json(cached);

  let list = [];
  if (isCrypto(symbol)) {
    try {
      list = await binance.getCandles(symbol, interval, fromMs, toMs);
    } catch (_) {}
  }
  if (r.usePolygon && polygonKey) {
    let multiplier = 1;
    let timespan = 'minute';
    if (interval === '1min') { multiplier = 1; timespan = 'minute'; }
    else if (interval === '5min') { multiplier = 5; timespan = 'minute'; }
    else if (interval === '15min') { multiplier = 15; timespan = 'minute'; }
    else if (interval === '30min') { multiplier = 30; timespan = 'minute'; }
    else if (interval === '1h') { multiplier = 1; timespan = 'hour'; }
    else if (interval === '1week') { multiplier = 1; timespan = 'week'; }
    else if (interval === '1month') { multiplier = 1; timespan = 'month'; }
    else if (interval === '1year') { multiplier = 1; timespan = 'year'; }
    else { multiplier = 1; timespan = 'day'; }
    try {
      const bars = await polygon.getAggregates(polygonKey, r.polygon, multiplier, timespan, fromMs, toMs);
      list = (bars || []).map((b) => ({ t: b.t, o: b.o, h: b.h, l: b.l, c: b.c, v: b.v }));
    } catch (_) {}
  }
  // Polygon 无数据时用 Twelve 兜底（含美股分钟级，Polygon 可能无权限）
  const useTwelve = list.length === 0 && twelveKey;
  if (useTwelve) {
    const twelveSymbol = r.polygon || r.twelve;
    const tdInterval = ['1day', '1week', '1month', '1year', '1h', '30min', '15min', '5min', '1min'].includes(interval) ? interval : '1day';
    let outputsize = (tdInterval === '1day' || tdInterval === '1week' || tdInterval === '1month' || tdInterval === '1year') ? 600 : 120;
    if (hasRange && ['1min', '5min', '15min', '30min', '1h'].includes(tdInterval)) {
      const days = (toMs - fromMs) / (24 * 60 * 60 * 1000);
      const barsPerDay = tdInterval === '1min' ? 24 * 60 : tdInterval === '5min' ? 24 * 12 : tdInterval === '15min' ? 24 * 4 : tdInterval === '30min' ? 48 : 24;
      outputsize = Math.min(5000, Math.max(120, Math.ceil(days * barsPerDay)));
    }
    try {
      const bars = await twelveData.getTimeSeries(twelveKey, twelveSymbol, tdInterval, outputsize);
      list = (bars || []).map((b) => ({ t: b.t, o: b.o, h: b.h, l: b.l, c: b.c, v: b.v }));
    } catch (_) {}
  }
  const isIntraday = ['1min', '5min', '15min', '30min', '1h'].includes(interval);
  const candlesTtlMs = isIntraday ? 15 * 1000 : DEFAULT_TTL_MS.candles;
  set(cacheKey, list, candlesTtlMs);
  res.json(list);
}

/** GET /api/gainers?limit=20 */
async function handleGainers(req, res, polygonKey) {
  if (!polygonKey) return res.json([]);
  const cacheKey = 'gainers_20';
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const list = await polygon.getGainers(polygonKey);
    set(cacheKey, list, DEFAULT_TTL_MS.gainers);
    res.json(list);
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/losers?limit=20 */
async function handleLosers(req, res, polygonKey) {
  if (!polygonKey) return res.json([]);
  const cacheKey = 'losers_20';
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const list = await polygon.getLosers(polygonKey);
    set(cacheKey, list, DEFAULT_TTL_MS.losers);
    res.json(list);
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/search?q=apple */
async function handleSearch(req, res, polygonKey) {
  const q = req.query.q?.trim();
  if (!q) return res.json([]);
  if (!polygonKey) return res.json([]);
  const cacheKey = `search_${q}`;
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const list = await polygon.searchTickers(polygonKey, q, 20);
    set(cacheKey, list, DEFAULT_TTL_MS.search);
    res.json(list);
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/ratios?symbol=AAPL — 财务比率（市盈率等） */
async function handleRatios(req, res, polygonKey) {
  const symbol = req.query.symbol?.trim();
  if (!symbol) return res.status(400).json({ error: 'missing symbol' });
  if (!polygonKey) return res.json(null);
  const cacheKey = `ratios_${symbol.toUpperCase()}`;
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const sym = symbol.toUpperCase();
    const data = await polygon.getKeyRatios(polygonKey, sym);
    if (data) set(cacheKey, data, DEFAULT_TTL_MS.ratios);
    res.json(data);
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/dividends?symbol=AAPL — 分红历史 */
async function handleDividends(req, res, polygonKey) {
  const symbol = req.query.symbol?.trim();
  if (!symbol) return res.status(400).json({ error: 'missing symbol' });
  if (!polygonKey) return res.json([]);
  const cacheKey = `dividends_${symbol.toUpperCase()}`;
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const sym = symbol.toUpperCase();
    const list = await polygon.getDividends(polygonKey, sym, 20);
    set(cacheKey, list, DEFAULT_TTL_MS.dividends);
    res.json(list);
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/splits?symbol=AAPL — 拆股历史 */
async function handleSplits(req, res, polygonKey) {
  const symbol = req.query.symbol?.trim();
  if (!symbol) return res.status(400).json({ error: 'missing symbol' });
  if (!polygonKey) return res.json([]);
  const cacheKey = `splits_${symbol.toUpperCase()}`;
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const sym = symbol.toUpperCase();
    const list = await polygon.getSplits(polygonKey, sym, 20);
    set(cacheKey, list, DEFAULT_TTL_MS.splits);
    res.json(list);
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/news/hot?limit=6 — 热点英文新闻 */
async function handleHotNews(req, res, polygonKey) {
  const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 6, 20));
  if (!polygonKey) return res.json([]);
  const cacheKey = `news_hot_${limit}`;
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const list = await polygon.getReferenceNews(polygonKey, { limit });
    set(cacheKey, list, DEFAULT_TTL_MS.news);
    return res.json(list);
  } catch (e) {
    return res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/news?ticker=AAPL&limit=20 — 个股新闻 */
async function handleTickerNews(req, res, polygonKey) {
  const ticker = String(req.query.ticker || '').trim().toUpperCase();
  const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 20, 50));
  if (!ticker) return res.status(400).json({ error: 'missing ticker' });
  if (!polygonKey) return res.json([]);
  const cacheKey = `news_${ticker}_${limit}`;
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const list = await polygon.getReferenceNews(polygonKey, { ticker, limit });
    set(cacheKey, list, DEFAULT_TTL_MS.news);
    return res.json(list);
  } catch (e) {
    return res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/news/announcements?ticker=AAPL&limit=20 — 公告类新闻 */
async function handleTickerAnnouncements(req, res, polygonKey) {
  const ticker = String(req.query.ticker || '').trim().toUpperCase();
  const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 20, 50));
  if (!ticker) return res.status(400).json({ error: 'missing ticker' });
  if (!polygonKey) return res.json([]);
  const cacheKey = `news_ann_${ticker}_${limit}`;
  const cached = getOrStale(cacheKey);
  if (cached) return res.json(cached);
  try {
    const list = await polygon.getAnnouncementNews(polygonKey, ticker, limit);
    set(cacheKey, list, DEFAULT_TTL_MS.news);
    return res.json(list);
  } catch (e) {
    return res.status(502).json({ error: String(e.message || e) });
  }
}

const MARKET_SNAPSHOTS_TABLE = 'market_snapshots';

/** GET /api/market/snapshots?type=gainers|losers|indices|forex|crypto — 从 Supabase 读取行情快照 */
async function handleMarketSnapshotsGet(req, res) {
  const type = req.query.type?.trim();
  if (!type) return res.status(400).json({ error: 'missing type' });
  const supabase = supabaseClient.getClient();
  if (!supabase) return res.status(503).json({ error: 'Supabase 未配置' });
  try {
    const { data, error } = await supabase
      .from(MARKET_SNAPSHOTS_TABLE)
      .select('payload')
      .eq('type', type)
      .maybeSingle();
    if (error) {
      console.warn('[api/market/snapshots GET] fallback empty:', String(error.message));
      return res.json([]);
    }
    const payload = data?.payload;
    if (!payload) return res.json([]);
    return res.json(Array.isArray(payload) ? payload : [payload]);
  } catch (e) {
    console.warn('[api/market/snapshots GET] exception:', String(e.message || e));
    return res.json([]);
  }
}

/** PUT /api/market/snapshots — 写入行情快照，body: { type, payload } */
async function handleMarketSnapshotsPut(req, res) {
  const { type, payload } = req.body || {};
  if (!type || typeof type !== 'string' || !payload) {
    return res.status(400).json({ error: 'missing type or payload' });
  }
  const supabase = supabaseClient.getClient();
  if (!supabase) return res.status(503).json({ error: 'Supabase 未配置' });
  try {
    const { error } = await supabase
      .from(MARKET_SNAPSHOTS_TABLE)
      .upsert(
        { type: type.trim(), payload, updated_at: new Date().toISOString() },
        { onConflict: 'type' },
      );
    if (error) {
      console.warn('[api/market/snapshots PUT] noop on error:', String(error.message));
      return res.json({ ok: false, reason: String(error.message) });
    }
    return res.json({ ok: true });
  } catch (e) {
    console.warn('[api/market/snapshots PUT] exception:', String(e.message || e));
    return res.json({ ok: false, reason: String(e.message || e) });
  }
}

/** GET /api/tickers-from-cache — 从 Supabase stock_quote_cache 取 symbol+name 列表，秒开美股列表 */
async function handleTickersFromCache(req, res) {
  if (!supabaseQuoteCache.isConfigured()) {
    return res.status(503).json({ error: 'Supabase 未配置' });
  }
  try {
    const maxAgeMs = req.query.maxAgeHours ? parseInt(req.query.maxAgeHours, 10) * 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
    const list = await supabaseQuoteCache.getAllSymbolsAndNames(maxAgeMs);
    const enriched = (list || []).map((item) => {
      const symbol = String(item.symbol || '').toUpperCase();
      return {
        ...item,
        is_24h_trading: STOCK_24H_SYMBOLS.has(symbol),
      };
    });
    return res.json(enriched);
  } catch (e) {
    return res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/tickers-page — 从 stock_quote_cache 按排序字段分页读取（含报价） */
async function handleTickersPage(req, res) {
  if (!supabaseQuoteCache.isConfigured()) {
    return res.status(503).json({ error: 'Supabase 未配置' });
  }
  try {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const pageSize = Math.max(1, Math.min(parseInt(req.query.pageSize, 10) || 30, 200));
    const sortColumn = String(req.query.sortColumn || 'pct');
    const sortAscending = req.query.sortAscending === '1' || req.query.sortAscending === 'true';
    const maxAgeHours = parseInt(req.query.maxAgeHours, 10);
    const maxAgeMs = Number.isFinite(maxAgeHours) && maxAgeHours > 0
      ? maxAgeHours * 60 * 60 * 1000
      : 0;
    const result = await supabaseQuoteCache.getTickersPageWithQuotes({
      page,
      pageSize,
      sortColumn,
      sortAscending,
      maxAgeMs,
    });
    const rows = (result.rows || []).map((row) => {
      const symbol = String(row.symbol || '').toUpperCase();
      return {
        symbol,
        name: row.name || symbol,
        stock_type: null,
        is_24h_trading: STOCK_24H_SYMBOLS.has(symbol),
        close: row.close != null ? Number(row.close) : null,
        change: row.change != null ? Number(row.change) : null,
        percent_change: row.percent_change != null ? Number(row.percent_change) : null,
        open: row.open != null ? Number(row.open) : null,
        high: row.high != null ? Number(row.high) : null,
        low: row.low != null ? Number(row.low) : null,
        volume: row.volume != null ? Number(row.volume) : null,
        prev_close: row.prev_close != null ? Number(row.prev_close) : null,
        updated_at: row.updated_at || null,
      };
    });
    return res.json({
      items: rows,
      total: result.total || 0,
      page,
      pageSize,
      hasMore: !!result.hasMore,
    });
  } catch (e) {
    return res.status(502).json({ error: String(e.message || e) });
  }
}

/** POST /api/tickers-upsert — 批量写入 symbol+name 到 stock_quote_cache（无报价也可，用于预填股票列表） */
async function handleTickersUpsert(req, res) {
  if (!supabaseQuoteCache.isConfigured()) {
    return res.status(503).json({ error: 'Supabase 未配置' });
  }
  const body = req.body;
  if (!Array.isArray(body) || body.length === 0) {
    return res.status(400).json({ error: 'body 需为 [{ symbol, name }, ...] 非空数组' });
  }
  if (body.length > 10000) {
    return res.status(400).json({ error: '单次最多 10000 条' });
  }
  try {
    const entries = body.map((e) => ({ symbol: e.symbol, name: e.name }));
    await supabaseQuoteCache.upsertSymbolsAndNames(entries);
    return res.json({ ok: true, count: entries.length });
  } catch (e) {
    return res.status(502).json({ error: String(e.message || e) });
  }
}

/** GET /api/forex/pairs?page=1&pageSize=30 — 服务端分页外汇交易对 */
async function handleForexPairs(req, res) {
  if (!supabaseForexCache.isConfigured()) {
    return res.status(503).json({ error: 'forex supabase cache not configured' });
  }
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const pageSize = Math.max(1, Math.min(parseInt(req.query.pageSize, 10) || 30, 200));
  const result = await supabaseForexCache.getForexPairsPage(page, pageSize);
  return res.json({
    items: (result.rows || []).map((r) => ({
      symbol: r.symbol,
      name: r.name || r.symbol,
      market: r.market || 'forex',
    })),
    total: result.total || 0,
    page: result.page || page,
    pageSize: result.pageSize || pageSize,
    hasMore: !!result.hasMore,
  });
}

/** GET /api/forex/quotes?symbols=EUR/USD,USD/JPY — 从 Supabase 外汇缓存读可视区域数据 */
async function handleForexQuotes(req, res) {
  if (!supabaseForexCache.isConfigured()) {
    return res.status(503).json({ error: 'forex supabase cache not configured' });
  }
  const raw = req.query.symbols;
  if (!raw || typeof raw !== 'string') {
    return res.status(400).json({ error: 'missing symbols' });
  }
  const symbols = [...new Set(raw.split(',').map((s) => s.trim()).filter(Boolean))];
  if (symbols.length === 0) return res.json({});
  if (symbols.length > 100) {
    return res.status(400).json({ error: 'symbols 最多 100 个' });
  }
  const out = await forexScheduler.getForexQuotesFromCache(symbols);
  return res.json(out);
}

/** GET /api/crypto/pairs?page=1&pageSize=30 — 服务端分页加密货币交易对 */
async function handleCryptoPairs(req, res) {
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const pageSize = Math.max(1, Math.min(parseInt(req.query.pageSize, 10) || 30, 200));
  if (!supabaseCryptoCache.isConfigured()) {
    const total = CRYPTO_PAIRS_FALLBACK.length;
    const from = (page - 1) * pageSize;
    const slice = CRYPTO_PAIRS_FALLBACK.slice(from, from + pageSize);
    return res.json({
      items: slice.map((r) => ({
        symbol: r.symbol,
        name: r.name || r.symbol,
        market: 'crypto',
      })),
      total,
      page,
      pageSize,
      hasMore: from + slice.length < total,
    });
  }
  const result = await supabaseCryptoCache.getCryptoPairsPage(page, pageSize);
  return res.json({
    items: (result.rows || []).map((r) => ({
      symbol: r.symbol,
      name: r.name || r.symbol,
      market: r.market || 'crypto',
    })),
    total: result.total || 0,
    page: result.page || page,
    pageSize: result.pageSize || pageSize,
    hasMore: !!result.hasMore,
  });
}

/** GET /api/crypto/quotes?symbols=BTC/USD,ETH/USD — 从 Supabase 加密缓存读数据 */
async function handleCryptoQuotes(req, res) {
  const raw = req.query.symbols;
  if (!raw || typeof raw !== 'string') {
    return res.status(400).json({ error: 'missing symbols' });
  }
  const symbols = [...new Set(raw.split(',').map((s) => s.trim()).filter(Boolean))];
  if (symbols.length === 0) return res.json({});
  if (symbols.length > 100) {
    return res.status(400).json({ error: 'symbols 最多 100 个' });
  }
  try {
    const mapped = symbols.map((s) => ({ original: s, binance: binance.toBinanceSymbol(s) }));
    const liveMap = await binance.getQuotes(mapped.map((x) => x.binance));
    const out = {};
    for (const { original, binance: binanceSymbol } of mapped) {
      const q = liveMap.get(binanceSymbol);
      out[original] = q
        ? toQuoteSnapshot({ ...q, symbol: original })
        : toQuoteSnapshot({ symbol: original, price: 0, change: 0, changePercent: 0, error_reason: 'Binance 无数据' });
    }
    return res.json(out);
  } catch (e) {
    return res.status(502).json({ error: String(e.message || e) });
  }
}

function registerRoutes(app, polygonKey, twelveKey, requireAuth) {
  const requireAdminRole = createRequireAdminRole();
  rateLimiter.init(require('./config').POLYGON_RATE_LIMIT_PER_SEC);
  app.get('/api/market/snapshots', handleMarketSnapshotsGet);
  app.put('/api/market/snapshots', requireAuth, requireAdminRole, handleMarketSnapshotsPut);
  app.get('/api/tickers-from-cache', handleTickersFromCache);
  app.get('/api/tickers-page', handleTickersPage);
  app.post('/api/tickers-upsert', requireAuth, requireAdminRole, handleTickersUpsert);
  app.get('/api/forex/pairs', handleForexPairs);
  app.get('/api/forex/quotes', handleForexQuotes);
  app.get('/api/crypto/pairs', handleCryptoPairs);
  app.get('/api/crypto/quotes', handleCryptoQuotes);
  app.get('/api/quotes', (req, res) => handleQuotes(req, res, polygonKey, twelveKey));
  app.get('/api/candles', (req, res) => handleCandles(req, res, polygonKey, twelveKey));
  app.get('/api/gainers', (req, res) => handleGainers(req, res, polygonKey));
  app.get('/api/losers', (req, res) => handleLosers(req, res, polygonKey));
  app.get('/api/search', (req, res) => handleSearch(req, res, polygonKey));
  app.get('/api/ratios', (req, res) => handleRatios(req, res, polygonKey));
  app.get('/api/dividends', (req, res) => handleDividends(req, res, polygonKey));
  app.get('/api/splits', (req, res) => handleSplits(req, res, polygonKey));
  app.get('/api/news/hot', (req, res) => handleHotNews(req, res, polygonKey));
  app.get('/api/news', (req, res) => handleTickerNews(req, res, polygonKey));
  app.get('/api/news/announcements', (req, res) => handleTickerAnnouncements(req, res, polygonKey));
}

module.exports = { registerRoutes };