/**
 * 调用 Polygon.io API，需环境变量 POLYGON_API_KEY
 */
const POLYGON_BASE = 'https://api.polygon.io';

async function getLastTrade(apiKey, symbol) {
  const url = `${POLYGON_BASE}/v2/last/trade/${encodeURIComponent(symbol)}?apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (res.status !== 200) return null;
  const data = await res.json();
  const results = data?.results;
  if (!results || typeof results !== 'object') return null;
  return { price: results.p, size: results.s, time: results.t };
}

async function getPreviousClose(apiKey, symbol) {
  const url = `${POLYGON_BASE}/v2/aggs/ticker/${encodeURIComponent(symbol)}/prev?apiKey=${apiKey}&adjusted=true`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (res.status !== 200) return null;
  const data = await res.json();
  const results = data?.results;
  if (!Array.isArray(results) || !results[0]) return null;
  return results[0].c ?? null;
}

/** 前一交易日完整 K 线 (o,h,l,c,v)，用于 snapshot 无 day/prevDay 时兜底 */
async function getPrevDayBar(apiKey, symbol) {
  const url = `${POLYGON_BASE}/v2/aggs/ticker/${encodeURIComponent(symbol)}/prev?apiKey=${apiKey}&adjusted=true`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (res.status !== 200) return null;
  const data = await res.json();
  const results = data?.results;
  if (!Array.isArray(results) || !results[0]) return null;
  const b = results[0];
  return { o: b.o, h: b.h, l: b.l, c: b.c, v: b.v };
}

/** 单标的报价：last + prev -> price, change, changePercent（无今开/最高/最低/量） */
async function getQuote(apiKey, symbol) {
  const [trade, prev] = await Promise.all([
    getLastTrade(apiKey, symbol),
    getPreviousClose(apiKey, symbol),
  ]);
  const price = trade?.price ?? prev ?? 0;
  const prevClose = prev ?? 0;
  const change = prevClose > 0 && trade ? price - prevClose : 0;
  const changePercent = prevClose > 0 ? (change / prevClose) * 100 : 0;
  const hasData = price > 0 || prevClose > 0;
  return {
    symbol,
    price,
    change,
    changePercent,
    open: null,
    high: null,
    low: null,
    volume: null,
    ...(hasData ? {} : { error_reason: 'Polygon 无数据' }),
  };
}

/** 无数据时返回带 error_reason 的占位对象，便于排查「为什么 API 返回空」 */
function snapshotError(symbol, reason) {
  return { symbol, price: 0, change: 0, changePercent: 0, error_reason: reason };
}

/** 单标的 Snapshot：当日 OHLCV + 昨收；休市用 prevDay，再没有则用 /prev 日线兜底。失败时返回带 error_reason 的对象而非 null。 */
async function getTickerSnapshot(apiKey, symbol) {
  const url = `${POLYGON_BASE}/v2/snapshot/locale/us/markets/stocks/tickers/${encodeURIComponent(symbol)}?apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  const data = await res.json().catch(() => ({}));
  if (res.status !== 200) {
    const msg = data?.error || data?.message || data?.status || res.statusText || `HTTP ${res.status}`;
    return snapshotError(symbol, `Polygon Snapshot ${res.status}: ${msg}`);
  }
  const ticker = data?.ticker;
  if (!ticker || typeof ticker !== 'object') {
    return snapshotError(symbol, data?.error || data?.message || 'Polygon Snapshot 返回空或无效 ticker');
  }
  const day = ticker.day || {};
  const prevDay = ticker.prevDay || {};
  const lastTrade = ticker.lastTrade || {};
  let close = (day.c != null ? day.c : lastTrade.p) ?? prevDay.c ?? 0;
  let prevClose = prevDay.c ?? 0;
  let open = day.o != null ? day.o : prevDay.o;
  let high = day.h != null ? day.h : prevDay.h;
  let low = day.l != null ? day.l : prevDay.l;
  let vol = day.v != null ? day.v : prevDay.v;
  if (open == null && high == null && low == null && vol == null) {
    const prevBar = await getPrevDayBar(apiKey, symbol);
    if (prevBar) {
      open = prevBar.o;
      high = prevBar.h;
      low = prevBar.l;
      if (prevClose == null || prevClose === 0) prevClose = prevBar.c;
      if (close == null || close === 0) close = prevBar.c;
      vol = prevBar.v;
    }
  }
  // 若仍有缺失，用前一交易日日线补全，保证列表页能显示开/高/低/量
  if (open == null || high == null || low == null || vol == null) {
    const prevBar = await getPrevDayBar(apiKey, symbol);
    if (prevBar) {
      if (open == null) open = prevBar.o;
      if (high == null) high = prevBar.h;
      if (low == null) low = prevBar.l;
      if (vol == null) vol = prevBar.v;
      if ((prevClose == null || prevClose === 0) && prevBar.c != null) prevClose = prevBar.c;
      if ((close == null || close === 0) && prevBar.c != null) close = prevBar.c;
    }
  }
  // 优先用 Polygon 直接返回的涨跌额/涨跌幅，不自己算，避免 close/prevClose 缺失时算出 -100% 等异常
  let change = ticker.todaysChange != null ? ticker.todaysChange : (prevClose > 0 && close != null ? close - prevClose : 0);
  let changePercent = ticker.todaysChangePerc != null ? ticker.todaysChangePerc : (prevClose > 0 && change !== 0 ? (change / prevClose) * 100 : 0);
  // snapshot 常有 day/prevDay 为空但带 todaysChange：用 /prev 补昨收并反推最新价，避免列表出现「最新价 —、涨跌幅 -100%」
  if ((close === 0 || close == null) && (change !== 0 || changePercent !== 0)) {
    const prevBar = await getPrevDayBar(apiKey, symbol);
    if (prevBar && prevBar.c != null) {
      prevClose = prevBar.c;
      close = prevClose + change;
      if (open == null) open = prevBar.o;
      if (high == null) high = prevBar.h;
      if (low == null) low = prevBar.l;
      if (vol == null) vol = prevBar.v;
    }
  }
  const volume = vol != null ? Number(vol) : null;
  const hasValidPrice = close != null && Number(close) > 0;
  // lastQuote：买一/卖一（需 Polygon Stocks Quote 权限，无则为空）
  // Polygon: p=bid price, P=ask price, s=bid size, S=ask size
  const lastQuote = ticker.lastQuote || {};
  const bid = lastQuote.p ?? lastQuote.bp ?? null;
  const ask = lastQuote.P ?? lastQuote.ap ?? null;
  const bidSize = lastQuote.s ?? lastQuote.bs ?? null;
  const askSize = lastQuote.S ?? lastQuote.as ?? null;
  return {
    symbol,
    price: close,
    change,
    changePercent,
    open: open ?? null,
    high: high ?? null,
    low: low ?? null,
    volume: Number.isFinite(volume) ? volume : null,
    bid: bid != null ? Number(bid) : null,
    ask: ask != null ? Number(ask) : null,
    bidSize: bidSize != null ? Number(bidSize) : null,
    askSize: askSize != null ? Number(askSize) : null,
    ...(hasValidPrice ? {} : { error_reason: 'Polygon Snapshot 无当日/昨收数据' }),
  };
}

/** 涨跌榜 snapshot */
async function getGainers(apiKey) {
  const url = `${POLYGON_BASE}/v2/snapshot/locale/us/markets/stocks/gainers?apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  return Array.isArray(data?.tickers) ? data.tickers : [];
}

async function getLosers(apiKey) {
  const url = `${POLYGON_BASE}/v2/snapshot/locale/us/markets/stocks/losers?apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  return Array.isArray(data?.tickers) ? data.tickers : [];
}

/** K 线聚合 */
async function getAggregates(apiKey, symbol, multiplier, timespan, fromMs, toMs) {
  const url = `${POLYGON_BASE}/v2/aggs/ticker/${encodeURIComponent(symbol)}/range/${multiplier}/${timespan}/${fromMs}/${toMs}?apiKey=${apiKey}&adjusted=true&sort=asc`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  const results = data?.results;
  if (!Array.isArray(results)) return [];
  return results.map((r) => ({
    t: r.t,
    o: r.o,
    h: r.h,
    l: r.l,
    c: r.c,
    v: r.v ?? 0,
  }));
}

/** 全量美股列表（v3/reference/tickers market=stocks type=CS，分页至 next_url 为空），返回 ticker 字符串数组 */
async function getAllUsTickers(apiKey) {
  const list = [];
  let nextUrl = null;
  const limit = 1000;
  try {
    for (;;) {
      const url = nextUrl
        ? `${nextUrl}${nextUrl.includes('?') ? '&' : '?'}apiKey=${apiKey}`
        : `${POLYGON_BASE}/v3/reference/tickers?market=stocks&type=CS&limit=${limit}&apiKey=${apiKey}`;
      const res = await fetch(url, { signal: AbortSignal.timeout(30000) });
      if (res.status !== 200) break;
      const data = await res.json();
      const results = data?.results;
      if (Array.isArray(results)) {
        for (const r of results) {
          const t = r?.ticker;
          if (t && typeof t === 'string') list.push(String(t).trim());
        }
      }
      nextUrl = data?.next_url;
      if (!nextUrl || typeof nextUrl !== 'string') break;
      await new Promise((r) => setTimeout(r, 300));
    }
  } catch (e) {}
  return list;
}

/** 搜索 tickers */
async function searchTickers(apiKey, query, limit = 20) {
  const url = `${POLYGON_BASE}/v3/reference/tickers?search=${encodeURIComponent(query)}&limit=${limit}&apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  const results = data?.results;
  if (!Array.isArray(results)) return [];
  return results.map((r) => ({
    ticker: r.ticker || '',
    name: r.name || r.ticker || '',
    market: r.market,
  })).filter((r) => r.ticker);
}

/** 财务比率（P/E、市净率、股息率等），单标的，取最新一条；需 Polygon 对应套餐 */
async function getKeyRatios(apiKey, ticker) {
  const url = `${POLYGON_BASE}/stocks/financials/v1/ratios?ticker=${encodeURIComponent(ticker)}&limit=1&apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (res.status !== 200) return null;
  let data;
  try {
    data = await res.json();
  } catch (_) {
    return null;
  }
  const results = data?.results;
  if (!Array.isArray(results) || !results[0]) return null;
  const r = results[0];
  return {
    ticker: r.ticker,
    date: r.date,
    price_to_earnings: r?.price_to_earnings ?? null,
    price_to_book: r?.price_to_book ?? null,
    price_to_sales: r?.price_to_sales ?? null,
    dividend_yield: r?.dividend_yield ?? null,
    earnings_per_share: r?.earnings_per_share ?? null,
    market_cap: r?.market_cap ?? null,
    return_on_equity: r?.return_on_equity ?? null,
    return_on_assets: r?.return_on_assets ?? null,
    debt_to_equity: r?.debt_to_equity ?? null,
  };
}

/** 分红历史，单标的 */
async function getDividends(apiKey, ticker, limit = 20) {
  const url = `${POLYGON_BASE}/v3/reference/dividends?ticker=${encodeURIComponent(ticker)}&limit=${limit}&apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  const results = data?.results;
  if (!Array.isArray(results)) return [];
  return results.map((d) => ({
    ticker: d.ticker,
    ex_dividend_date: d.ex_dividend_date,
    pay_date: d.pay_date,
    cash_amount: d.cash_amount,
    currency: d.currency,
    distribution_type: d.distribution_type,
    frequency: d.frequency,
  }));
}

/** 拆股历史，单标的 */
async function getSplits(apiKey, ticker, limit = 20) {
  const url = `${POLYGON_BASE}/v3/reference/splits?ticker=${encodeURIComponent(ticker)}&limit=${limit}&apiKey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  const results = data?.results;
  if (!Array.isArray(results)) return [];
  return results.map((s) => ({
    ticker: s.ticker,
    execution_date: s.execution_date,
    split_from: s.split_from,
    split_to: s.split_to,
    adjustment_type: s.adjustment_type,
  }));
}

const V2_SNAPSHOT_BATCH_SIZE = 250;
const V3_SNAPSHOT_BATCH_SIZE = 250;

/**
 * 将 v2 snapshot 的单个 ticker 对象转成统一报价格式（与 getTickerSnapshot 返回一致）
 */
function tickerToQuotePayload(ticker, symbol) {
  const day = ticker.day || {};
  const prevDay = ticker.prevDay || {};
  const lastTrade = ticker.lastTrade || {};
  let close = (day.c != null ? day.c : lastTrade.p) ?? prevDay.c ?? 0;
  const prevClose = prevDay.c ?? 0;
  const open = day.o != null ? day.o : prevDay.o;
  const high = day.h != null ? day.h : prevDay.h;
  const low = day.l != null ? day.l : prevDay.l;
  const vol = day.v != null ? day.v : prevDay.v;
  let change = ticker.todaysChange != null ? ticker.todaysChange : (prevClose > 0 && close != null ? close - prevClose : 0);
  let changePercent = ticker.todaysChangePerc != null ? ticker.todaysChangePerc : (prevClose > 0 && change !== 0 ? (change / prevClose) * 100 : 0);
  const volume = vol != null ? Number(vol) : null;
  const hasValidPrice = close != null && Number(close) > 0;
  return {
    symbol,
    price: close,
    change,
    changePercent,
    open: open ?? null,
    high: high ?? null,
    low: low ?? null,
    volume: Number.isFinite(volume) ? volume : null,
    ...(hasValidPrice ? {} : { error_reason: 'Polygon Snapshot 无当日/昨收数据' }),
  };
}

/**
 * 批量 Snapshot（v2 股票）：tickers=AAPL,MSFT,... 一次请求，返回结构与单只一致（含 day/prevDay 的今开、最高、最低、成交量）。
 * 优先用此接口做列表批量，能拿到完整 OHLCV。
 * @param {string} apiKey
 * @param {string[]} symbols 最多 250 个
 * @returns {Promise<Map<string, object>>} symbol -> { symbol, price, change, changePercent, open, high, low, volume, error_reason? }
 */
async function getBatchSnapshotsV2(apiKey, symbols) {
  const out = new Map();
  if (!apiKey || !Array.isArray(symbols) || symbols.length === 0) return out;
  const list = symbols.slice(0, V2_SNAPSHOT_BATCH_SIZE);
  const tickersParam = list.join(',');
  const url = `${POLYGON_BASE}/v2/snapshot/locale/us/markets/stocks/tickers?tickers=${encodeURIComponent(tickersParam)}&apiKey=${apiKey}`;
  let res;
  let data;
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(25000) });
    data = await res.json().catch(() => ({}));
  } catch (e) {
    for (const s of list) {
      out.set(s, { symbol: s, price: 0, change: 0, changePercent: 0, error_reason: String(e.message || e) });
    }
    return out;
  }
  if (res.status !== 200) {
    const msg = data?.error || data?.message || data?.status || res.statusText || `HTTP ${res.status}`;
    for (const s of list) {
      out.set(s, { symbol: s, price: 0, change: 0, changePercent: 0, error_reason: `Polygon v2 Snapshot ${res.status}: ${msg}` });
    }
    return out;
  }
  const tickers = data?.tickers;
  if (!Array.isArray(tickers)) {
    for (const s of list) {
      out.set(s, { symbol: s, price: 0, change: 0, changePercent: 0, error_reason: 'Polygon v2 Snapshot 返回空 tickers' });
    }
    return out;
  }
  for (const t of tickers) {
    const symbol = t?.ticker ? String(t.ticker).trim().toUpperCase() : null;
    if (!symbol) continue;
    out.set(symbol, tickerToQuotePayload(t, symbol));
  }
  return out;
}

/**
 * 批量 Snapshot（v3）：一次请求最多 250 只；v3 可能无 day 对象，列表缺今开/最高/最低/量时优先用 getBatchSnapshotsV2。
 * @param {string} apiKey
 * @param {string[]} symbols 最多 250 个
 * @returns {Promise<Map<string, object>>} symbol -> { symbol, price, change, changePercent, open, high, low, volume, error_reason? }
 */
async function getBatchSnapshotsV3(apiKey, symbols) {
  const out = new Map();
  if (!apiKey || !Array.isArray(symbols) || symbols.length === 0) return out;
  const list = symbols.slice(0, V3_SNAPSHOT_BATCH_SIZE);
  const tickerAnyOf = list.join(',');
  const url = `${POLYGON_BASE}/v3/snapshot?ticker.any_of=${encodeURIComponent(tickerAnyOf)}&limit=${V3_SNAPSHOT_BATCH_SIZE}&apiKey=${apiKey}`;
  let res;
  let data;
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(20000) });
    data = await res.json().catch(() => ({}));
  } catch (e) {
    for (const s of list) {
      out.set(s, { symbol: s, price: 0, change: 0, changePercent: 0, error_reason: String(e.message || e) });
    }
    return out;
  }
  if (res.status !== 200) {
    const msg = data?.error || data?.message || data?.status || res.statusText || `HTTP ${res.status}`;
    for (const s of list) {
      out.set(s, { symbol: s, price: 0, change: 0, changePercent: 0, error_reason: `Polygon v3 Snapshot ${res.status}: ${msg}` });
    }
    return out;
  }
  const results = data?.results;
  if (!Array.isArray(results)) {
    for (const s of list) {
      out.set(s, { symbol: s, price: 0, change: 0, changePercent: 0, error_reason: 'Polygon v3 Snapshot 返回空 results' });
    }
    return out;
  }
  for (const r of results) {
    const symbol = r?.ticker ? String(r.ticker).trim().toUpperCase() : null;
    if (!symbol) continue;
    const day = r?.day || {};
    const prevDay = r?.prev_day || r?.prevDay || {};
    const lastTrade = r?.last_trade || r?.lastTrade || {};
    let close = (day.c != null ? day.c : lastTrade?.price ?? lastTrade?.p) ?? prevDay.c ?? 0;
    const prevClose = prevDay.c ?? 0;
    const open = day.o ?? prevDay.o ?? null;
    const high = day.h ?? prevDay.h ?? null;
    const low = day.l ?? prevDay.l ?? null;
    const vol = day.v ?? prevDay.v ?? null;
    let change = r?.todays_change != null ? r.todays_change : (prevClose > 0 && close != null ? close - prevClose : 0);
    let changePercent = r?.todays_change_percent != null ? r.todays_change_percent : (prevClose > 0 && change !== 0 ? (change / prevClose) * 100 : 0);
    const hasValidPrice = close != null && Number(close) > 0;
    out.set(symbol, {
      symbol,
      price: close,
      change,
      changePercent,
      open: open ?? null,
      high: high ?? null,
      low: low ?? null,
      volume: Number.isFinite(Number(vol)) ? Number(vol) : null,
      ...(hasValidPrice ? {} : { error_reason: 'Polygon v3 Snapshot 无当日/昨收数据' }),
    });
  }
  return out;
}

module.exports = {
  getBatchSnapshotsV2,
  getBatchSnapshotsV3,
  V2_SNAPSHOT_BATCH_SIZE,
  V3_SNAPSHOT_BATCH_SIZE,
  getQuote,
  getPrevDayBar,
  getTickerSnapshot,
  getLastTrade,
  getPreviousClose,
  getGainers,
  getLosers,
  getAggregates,
  getAllUsTickers,
  searchTickers,
  getKeyRatios,
  getDividends,
  getSplits,
};
