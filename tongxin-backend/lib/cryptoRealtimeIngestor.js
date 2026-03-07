/**
 * 启动即连接 Twelve Data WebSocket，订阅全量加密货币交易对；
 * 将实时价格增量批量写入 Supabase crypto_quote_cache。
 */
const WebSocket = require('ws');
const supabaseCryptoCache = require('./supabaseCryptoCache');
const { emitQuote } = require('./marketBroadcast');

const WS_URL_BASE = 'wss://ws.twelvedata.com/v1/quotes/price';
const FLUSH_INTERVAL_MS = Math.max(300, parseInt(process.env.CRYPTO_WS_FLUSH_INTERVAL_MS || '1500', 10));
const RECONNECT_DELAY_MS = Math.max(1000, parseInt(process.env.CRYPTO_WS_RECONNECT_DELAY_MS || '3000', 10));
const RESYNC_INTERVAL_MS = Math.max(60 * 1000, parseInt(process.env.CRYPTO_WS_RESYNC_INTERVAL_MS || `${60 * 60 * 1000}`, 10));
const SUBSCRIBE_CHUNK_SIZE = Math.max(1, parseInt(process.env.CRYPTO_WS_SUBSCRIBE_CHUNK_SIZE || '200', 10));

let ws = null;
let started = false;
let reconnectTimer = null;
let flushTimer = null;
let resyncTimer = null;
const pending = new Map(); // symbol -> latest update

function flushPending() {
  if (pending.size === 0) return;
  const updates = [];
  for (const [, item] of pending) {
    updates.push(item);
  }
  pending.clear();
  for (const u of updates) {
    emitQuote({ ...u, market: 'crypto' });
  }
  const sample = updates.slice(0, 5).map((u) => `${u.symbol}:${u.price}`).join(', ');
  const startedAt = Date.now();
  supabaseCryptoCache.setCryptoRealtimePricesBatch(updates)
    .then(() => {
      const cost = Date.now() - startedAt;
      console.log(`[cryptoRealtimeIngestor] cache update ok count=${updates.length} cost=${cost}ms sample=[${sample}]`);
    })
    .catch((e) => {
      console.warn('[cryptoRealtimeIngestor] realtime batch write failed:', String(e.message || e));
    });
}

function scheduleReconnect(apiKey) {
  if (!started) return;
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect(apiKey);
  }, RECONNECT_DELAY_MS);
}

function parseInboundMessage(raw) {
  let msg;
  try {
    msg = JSON.parse(String(raw));
  } catch (_) {
    return null;
  }
  if (!msg || typeof msg !== 'object') return null;
  const symbol = String(msg.symbol || msg.s || '').trim();
  const price = Number(msg.price ?? msg.close ?? msg.p);
  if (!symbol || !Number.isFinite(price) || price <= 0) return null;
  const out = { symbol, price };
  const change = Number(msg.change);
  const percent = Number(msg.percent_change ?? msg.percentChange);
  const open = Number(msg.open);
  const high = Number(msg.high);
  const low = Number(msg.low);
  const volume = Number(msg.volume);
  const timestamp = Number(msg.timestamp ?? msg.ts ?? msg.time);
  if (Number.isFinite(change)) out.change = change;
  if (Number.isFinite(percent)) out.percent_change = percent;
  if (Number.isFinite(open)) out.open = open;
  if (Number.isFinite(high)) out.high = high;
  if (Number.isFinite(low)) out.low = low;
  if (Number.isFinite(volume)) out.volume = volume;
  if (Number.isFinite(timestamp)) out.timestamp = timestamp;
  return out;
}

async function subscribeAllSymbols() {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  const symbols = await supabaseCryptoCache.getAllCryptoSymbols();
  if (!Array.isArray(symbols) || symbols.length === 0) {
    console.warn('[cryptoRealtimeIngestor] no crypto symbols available to subscribe');
    return;
  }
  try {
    ws.send(JSON.stringify({ action: 'reset' }));
  } catch (_) {}
  let chunks = 0;
  for (let i = 0; i < symbols.length; i += SUBSCRIBE_CHUNK_SIZE) {
    const chunk = symbols.slice(i, i + SUBSCRIBE_CHUNK_SIZE);
    ws.send(JSON.stringify({ action: 'subscribe', params: { symbols: chunk.join(',') } }));
    chunks += 1;
  }
  console.log(`[cryptoRealtimeIngestor] subscribed crypto symbols=${symbols.length} chunks=${chunks}`);
}

function connect(apiKey) {
  if (!started || !apiKey) return;
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }
  const url = `${WS_URL_BASE}?apikey=${encodeURIComponent(apiKey)}`;
  ws = new WebSocket(url);
  ws.on('open', () => {
    subscribeAllSymbols().catch((e) => {
      console.warn('[cryptoRealtimeIngestor] subscribe failed:', String(e.message || e));
    });
  });
  ws.on('message', (raw) => {
    const item = parseInboundMessage(raw);
    if (!item) return;
    pending.set(item.symbol, item);
  });
  ws.on('error', (e) => {
    console.warn('[cryptoRealtimeIngestor] ws error:', String(e.message || e));
  });
  ws.on('close', () => {
    ws = null;
    scheduleReconnect(apiKey);
  });
}

function startCryptoRealtimeIngestor(apiKey) {
  if (started || !apiKey) return;
  if (!supabaseCryptoCache.isConfigured()) {
    console.warn('[cryptoRealtimeIngestor] Supabase 未配置，跳过实时入库');
    return;
  }
  started = true;
  flushTimer = setInterval(flushPending, FLUSH_INTERVAL_MS);
  resyncTimer = setInterval(() => {
    subscribeAllSymbols().catch((e) => {
      console.warn('[cryptoRealtimeIngestor] periodic resubscribe failed:', String(e.message || e));
    });
  }, RESYNC_INTERVAL_MS);
  connect(apiKey);
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
  if (resyncTimer) {
    clearInterval(resyncTimer);
    resyncTimer = null;
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
