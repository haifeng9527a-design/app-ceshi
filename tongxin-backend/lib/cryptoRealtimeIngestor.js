/**
 * Connects to Binance all-market mini ticker stream and writes rolling crypto
 * updates into Supabase crypto_quote_cache.
 */
const WebSocket = require('ws');
const binance = require('./binance');
const supabaseCryptoCache = require('./supabaseCryptoCache');
const { emitQuote } = require('./marketBroadcast');

const WS_URL = process.env.BINANCE_STREAM_URL || 'wss://data-stream.binance.vision/stream?streams=!miniTicker@arr';
const FLUSH_INTERVAL_MS = Math.max(300, parseInt(process.env.CRYPTO_WS_FLUSH_INTERVAL_MS || '1500', 10));
const RECONNECT_DELAY_MS = Math.max(1000, parseInt(process.env.CRYPTO_WS_RECONNECT_DELAY_MS || '3000', 10));

let ws = null;
let started = false;
let reconnectTimer = null;
let flushTimer = null;
const pending = new Map();

function normalizeMiniTicker(item) {
  const exchangeSymbol = String(item?.s || '').trim().toUpperCase();
  const displaySymbol = binance.fromBinanceSymbol(exchangeSymbol);
  if (!displaySymbol || !displaySymbol.endsWith('/USD')) return null;
  const close = Number(item?.c);
  const open = Number(item?.o);
  const high = Number(item?.h);
  const low = Number(item?.l);
  const volume = Number(item?.v);
  const quoteVolume = Number(item?.q);
  if (!Number.isFinite(close) || close <= 0) return null;
  const change = Number.isFinite(open) ? close - open : null;
  const percentChange =
    Number.isFinite(open) && open > 0 && change != null ? (change / open) * 100 : null;
  return {
    symbol: displaySymbol,
    price: close,
    change,
    percent_change: percentChange,
    open: Number.isFinite(open) ? open : null,
    high: Number.isFinite(high) ? high : null,
    low: Number.isFinite(low) ? low : null,
    volume: Number.isFinite(volume) ? volume : null,
    quote_volume: Number.isFinite(quoteVolume) ? quoteVolume : null,
    timestamp: Date.now(),
  };
}

function flushPending() {
  if (pending.size === 0) return;
  const updates = [...pending.values()];
  pending.clear();
  for (const update of updates) {
    emitQuote({ ...update, market: 'crypto' });
  }
  supabaseCryptoCache.setCryptoRealtimePricesBatch(updates).catch((e) => {
    console.warn('[cryptoRealtimeIngestor] realtime batch write failed:', String(e.message || e));
  });
}

function scheduleReconnect() {
  if (!started || reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, RECONNECT_DELAY_MS);
}

function parseInboundMessage(raw) {
  let msg;
  try {
    msg = JSON.parse(String(raw));
  } catch (_) {
    return [];
  }
  const payload = Array.isArray(msg?.data) ? msg.data : Array.isArray(msg) ? msg : [];
  return payload.map(normalizeMiniTicker).filter(Boolean);
}

function connect() {
  if (!started) return;
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }
  ws = new WebSocket(WS_URL);
  ws.on('message', (raw) => {
    for (const item of parseInboundMessage(raw)) {
      pending.set(item.symbol, item);
    }
  });
  ws.on('error', (e) => {
    console.warn('[cryptoRealtimeIngestor] ws error:', String(e.message || e));
  });
  ws.on('close', () => {
    ws = null;
    scheduleReconnect();
  });
}

function startCryptoRealtimeIngestor() {
  if (started) return;
  if (!supabaseCryptoCache.isConfigured()) {
    console.warn('[cryptoRealtimeIngestor] Supabase 未配置，跳过实时入库');
    return;
  }
  started = true;
  flushTimer = setInterval(flushPending, FLUSH_INTERVAL_MS);
  connect();
}

function stopCryptoRealtimeIngestor() {
  started = false;
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (flushTimer) {
    clearInterval(flushTimer);
    flushTimer = null;
  }
  flushPending();
  if (ws) {
    try {
      ws.close();
    } catch (_) {}
    ws = null;
  }
}

module.exports = {
  startCryptoRealtimeIngestor,
  stopCryptoRealtimeIngestor,
};
