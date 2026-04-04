/**
 * Binance public market data adapter for crypto market data.
 * No API key required for the endpoints used here.
 */

const BINANCE_BASE = process.env.BINANCE_BASE || 'https://api.binance.com';

const STABLE_QUOTES = new Set(['USDT', 'USDC', 'FDUSD', 'TUSD', 'USDP', 'BUSD']);
const DISPLAY_QUOTE_MAP = {
  USDT: 'USD',
  USDC: 'USD',
  FDUSD: 'USD',
  TUSD: 'USD',
  USDP: 'USD',
  BUSD: 'USD',
};
const ASSET_NAME_MAP = {
  BTC: 'Bitcoin',
  ETH: 'Ethereum',
  SOL: 'Solana',
  XRP: 'XRP',
  DOGE: 'Dogecoin',
  BNB: 'BNB',
  ADA: 'Cardano',
  AVAX: 'Avalanche',
  DOT: 'Polkadot',
  LINK: 'Chainlink',
  LTC: 'Litecoin',
  BCH: 'Bitcoin Cash',
  TRX: 'TRON',
  UNI: 'Uniswap',
  ATOM: 'Cosmos',
  MATIC: 'Polygon',
  ARB: 'Arbitrum',
  OP: 'Optimism',
  ETC: 'Ethereum Classic',
  XLM: 'Stellar',
  FIL: 'Filecoin',
  APT: 'Aptos',
  SUI: 'Sui',
  PEPE: 'Pepe',
  SHIB: 'Shiba Inu',
};

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

function displayQuoteAsset(quoteAsset) {
  const upper = String(quoteAsset || '').trim().toUpperCase();
  return DISPLAY_QUOTE_MAP[upper] || upper;
}

function buildOriginalSymbol(baseAsset, quoteAsset) {
  const base = String(baseAsset || '').trim().toUpperCase();
  const quote = displayQuoteAsset(quoteAsset);
  if (!base || !quote) return '';
  return `${base}/${quote}`;
}

function splitBinanceSymbol(symbol) {
  const upper = String(symbol || '').trim().toUpperCase();
  if (!upper) return null;
  const quotes = ['USDT', 'USDC', 'FDUSD', 'BUSD', 'TUSD', 'USDP', 'BTC', 'ETH', 'BNB', 'TRY', 'EUR'];
  for (const quote of quotes) {
    if (upper.endsWith(quote) && upper.length > quote.length) {
      return {
        baseAsset: upper.slice(0, -quote.length),
        quoteAsset: quote,
      };
    }
  }
  return null;
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

function fromBinanceSymbol(symbol) {
  const parts = splitBinanceSymbol(symbol);
  if (!parts) return '';
  return buildOriginalSymbol(parts.baseAsset, parts.quoteAsset);
}

function buildPairName(baseAsset, quoteAsset) {
  const base = String(baseAsset || '').trim().toUpperCase();
  const baseName = ASSET_NAME_MAP[base] || base;
  return `${baseName} / ${displayQuoteAsset(quoteAsset)}`;
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
      quoteVolume: Number(row.quoteVolume || 0) || null,
      weightedAvgPrice: Number(row.weightedAvgPrice || 0) || null,
      tradeCount: Number(row.count || 0) || null,
      openTime: Number(row.openTime || 0) || null,
      closeTime: Number(row.closeTime || 0) || null,
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

async function getDepth(symbol, limit = 5) {
  const binanceSymbol = toBinanceSymbol(symbol);
  if (!binanceSymbol) return { bids: [], asks: [], lastUpdateId: null };
  const safeLimit = Math.max(1, Math.min(Number(limit) || 5, 20));
  const url =
    `${BINANCE_BASE}/api/v3/depth?symbol=${encodeURIComponent(binanceSymbol)}` +
    `&limit=${safeLimit}`;
  const data = await fetchJson(url);
  const mapSide = (rows) =>
    Array.isArray(rows)
      ? rows
          .map((row) => {
            if (!Array.isArray(row) || row.length < 2) return null;
            const price = Number(row[0]);
            const qty = Number(row[1]);
            if (!Number.isFinite(price) || price <= 0 || !Number.isFinite(qty) || qty < 0) {
              return null;
            }
            return [price, Math.round(qty)] ;
          })
          .filter(Boolean)
      : [];
  return {
    lastUpdateId: Number(data?.lastUpdateId || 0) || null,
    bids: mapSide(data?.bids),
    asks: mapSide(data?.asks),
  };
}

async function getTradingPairs() {
  const [exchangeInfo, tickersResp] = await Promise.all([
    fetchJson(`${BINANCE_BASE}/api/v3/exchangeInfo?permissions=%5B%22SPOT%22%5D`),
    fetchJson(`${BINANCE_BASE}/api/v3/ticker/24hr?type=MINI`),
  ]);
  const tickerRows = Array.isArray(tickersResp) ? tickersResp : [];
  const tickerMap = new Map(
    tickerRows
      .filter((row) => row && row.symbol)
      .map((row) => [String(row.symbol).toUpperCase(), row]),
  );
  const symbols = Array.isArray(exchangeInfo?.symbols) ? exchangeInfo.symbols : [];
  const out = [];
  for (const item of symbols) {
    const status = String(item?.status || '').toUpperCase();
    const baseAsset = String(item?.baseAsset || '').trim().toUpperCase();
    const quoteAsset = String(item?.quoteAsset || '').trim().toUpperCase();
    const exchangeSymbol = String(item?.symbol || '').trim().toUpperCase();
    if (!exchangeSymbol || !baseAsset || !quoteAsset) continue;
    if (status !== 'TRADING') continue;
    if (!STABLE_QUOTES.has(quoteAsset)) continue;
    if (item?.isSpotTradingAllowed === false) continue;
    const ticker = tickerMap.get(exchangeSymbol);
    const quoteVolume = Number(ticker?.quoteVolume || 0) || 0;
    out.push({
      symbol: buildOriginalSymbol(baseAsset, quoteAsset),
      name: buildPairName(baseAsset, quoteAsset),
      market: 'crypto',
      exchangeSymbol,
      baseAsset,
      quoteAsset,
      quoteVolume,
      lastPrice: Number(ticker?.lastPrice || 0) || null,
    });
  }
  const deduped = new Map();
  for (const item of out) {
    const existing = deduped.get(item.symbol);
    if (!existing) {
      deduped.set(item.symbol, item);
      continue;
    }
    if ((item.quoteVolume || 0) > (existing.quoteVolume || 0)) {
      deduped.set(item.symbol, item);
      continue;
    }
    if ((item.quoteVolume || 0) === (existing.quoteVolume || 0) &&
        String(item.exchangeSymbol).localeCompare(String(existing.exchangeSymbol)) < 0) {
      deduped.set(item.symbol, item);
    }
  }
  const normalized = [...deduped.values()];
  normalized.sort((a, b) => {
    if (b.quoteVolume !== a.quoteVolume) return b.quoteVolume - a.quoteVolume;
    return a.symbol.localeCompare(b.symbol);
  });
  return normalized;
}

/**
 * 获取 Binance 永续合约资金费率
 * GET https://fapi.binance.com/fapi/v1/premiumIndex?symbol=BTCUSDT
 */
const BINANCE_FAPI = process.env.BINANCE_FAPI_BASE || 'https://fapi.binance.com';

async function getFundingRate(displaySymbol) {
  const binSym = toBinanceSymbol(displaySymbol);
  if (!binSym) return null;
  const url = `${BINANCE_FAPI}/fapi/v1/premiumIndex?symbol=${binSym}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const data = await res.json();
  return {
    symbol: displaySymbol,
    fundingRate: parseFloat(data.lastFundingRate),       // e.g. 0.0001 = 0.01%
    nextFundingTime: data.nextFundingTime,               // unix ms
    markPrice: parseFloat(data.markPrice),
    indexPrice: parseFloat(data.indexPrice),
  };
}

module.exports = {
  toBinanceSymbol,
  fromBinanceSymbol,
  buildOriginalSymbol,
  getTradingPairs,
  getQuotes,
  getDepth,
  getCandles,
  getFundingRate,
};
