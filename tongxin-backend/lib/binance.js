/**
 * Binance public market data adapter for crypto quotes/candles.
 * No API key required for the endpoints used here.
 */

const BINANCE_BASE = process.env.BINANCE_BASE || 'https://data-api.binance.vision';

const INTERVAL_MAP = {
  '1min': '1m',
  '5min': '5m',
  '15min': '15m',
  '30min': '30m',
  '1h': '1h',
  '1day': '1d',
  '1week': '1w',
  '1month': '1M',
};

function normalizeOriginalSymbol(symbol) {
  return String(symbol || '').trim().toUpperCase();
}

function toBinanceSymbol(symbol) {
  const raw = normalizeOriginalSymbol(symbol);
  if (!raw) return '';
  if (!raw.includes('/')) return raw.endsWith('USD') ? `${raw.slice(0, -3)}USDT` : raw;
  const [base, quote] = raw.split('/');
  if (!base || !quote) return '';
  const mappedQuote = quote === 'USD' ? 'USDT' : quote;
  return `${base}${mappedQuote}`;
}

async function fetchJson(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (res.status !== 200) {
    const text = await res.text().catch(() => '');
    throw new Error(`Binance ${res.status}: ${text || 'request failed'}`);
  }
  return res.json();
}

async function getQuotes(symbols) {
  const unique = [...new Set((symbols || []).map((s) => String(s || '').trim().toUpperCase()).filter(Boolean))];
  if (unique.length === 0) return new Map();

  const tickerUrl =
    unique.length === 1
      ? `${BINANCE_BASE}/api/v3/ticker/24hr?symbol=${encodeURIComponent(unique[0])}`
      : `${BINANCE_BASE}/api/v3/ticker/24hr?symbols=${encodeURIComponent(JSON.stringify(unique))}`;
  const bookUrl =
    unique.length === 1
      ? `${BINANCE_BASE}/api/v3/ticker/bookTicker?symbol=${encodeURIComponent(unique[0])}`
      : `${BINANCE_BASE}/api/v3/ticker/bookTicker?symbols=${encodeURIComponent(JSON.stringify(unique))}`;

  const [tickerResp, bookResp] = await Promise.all([
    fetchJson(tickerUrl),
    fetchJson(bookUrl),
  ]);

  const tickers = Array.isArray(tickerResp) ? tickerResp : [tickerResp];
  const books = Array.isArray(bookResp) ? bookResp : [bookResp];
  const bookMap = new Map(books.map((item) => [String(item.symbol || '').toUpperCase(), item]));

  const out = new Map();
  for (const row of tickers) {
    const symbol = String(row.symbol || '').toUpperCase();
    if (!symbol) continue;
    const book = bookMap.get(symbol) || {};
    out.set(symbol, {
      symbol,
      price: Number(row.lastPrice || 0),
      change: Number(row.priceChange || 0),
      changePercent: Number(row.priceChangePercent || 0),
      prevClose: Number(row.prevClosePrice || 0) || null,
      open: Number(row.openPrice || 0) || null,
      high: Number(row.highPrice || 0) || null,
      low: Number(row.lowPrice || 0) || null,
      volume: Number(row.volume || 0) || null,
      bid: Number(book.bidPrice || 0) || null,
      ask: Number(book.askPrice || 0) || null,
      bidSize: Number(book.bidQty || 0) || null,
      askSize: Number(book.askQty || 0) || null,
    });
  }
  return out;
}

function intervalToMs(interval) {
  switch (interval) {
    case '1min': return 60 * 1000;
    case '5min': return 5 * 60 * 1000;
    case '15min': return 15 * 60 * 1000;
    case '30min': return 30 * 60 * 1000;
    case '1h': return 60 * 60 * 1000;
    case '1day': return 24 * 60 * 60 * 1000;
    case '1week': return 7 * 24 * 60 * 60 * 1000;
    case '1month': return 30 * 24 * 60 * 60 * 1000;
    default: return 60 * 1000;
  }
}

async function getCandles(symbol, interval, fromMs, toMs) {
  const binanceSymbol = toBinanceSymbol(symbol);
  const binanceInterval = INTERVAL_MAP[interval] || '1m';
  if (!binanceSymbol) return [];

  const stepMs = intervalToMs(interval);
  const out = [];
  let startTime = fromMs;
  const endTime = toMs;
  let safety = 0;

  while (startTime < endTime && safety < 10) {
    safety += 1;
    const url =
      `${BINANCE_BASE}/api/v3/klines?symbol=${encodeURIComponent(binanceSymbol)}` +
      `&interval=${encodeURIComponent(binanceInterval)}` +
      `&startTime=${startTime}&limit=1000`;
    const rows = await fetchJson(url);
    if (!Array.isArray(rows) || rows.length === 0) break;
    for (const row of rows) {
      if (!Array.isArray(row) || row.length < 6) continue;
      const openTime = Number(row[0]);
      if (!Number.isFinite(openTime) || openTime > endTime) continue;
      out.push({
        t: openTime,
        o: Number(row[1]),
        h: Number(row[2]),
        l: Number(row[3]),
        c: Number(row[4]),
        v: Number(row[5]) || 0,
      });
    }
    const lastOpen = Number(rows[rows.length - 1][0]);
    if (!Number.isFinite(lastOpen)) break;
    const nextStart = lastOpen + stepMs;
    if (nextStart <= startTime) break;
    startTime = nextStart;
    if (lastOpen >= endTime - stepMs || rows.length < 1000) break;
  }

  out.sort((a, b) => a.t - b.t);
  return out;
}

module.exports = {
  toBinanceSymbol,
  getQuotes,
  getCandles,
};
