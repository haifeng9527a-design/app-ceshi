/**
 * 启动即连接 Polygon WebSocket，订阅全量美股成交(T.*)；
 * 将实时价格增量批量写入 Supabase stock_quote_cache。
 */
const WebSocket = require('ws');
const supabaseQuoteCache = require('./supabaseQuoteCache');
const { emitQuote } = require('./marketBroadcast');

const POLYGON_WS = 'wss://socket.polygon.io/stocks';
const FLUSH_INTERVAL_MS = 1500;
const RECONNECT_DELAY_MS = 3000;

let ws = null;
let started = false;
let reconnectTimer = null;
let flushTimer = null;
const pending = new Map(); // symbol -> latestPrice

function flushPending() {
  if (pending.size === 0) return;
  const trades = [];
  for (const [symbol, price] of pending) {
    trades.push({ symbol, price });
    emitQuote({ symbol, price, market: 'stock' });
  }
  pending.clear();
  supabaseQuoteCache.setRealtimeTradesBatch(trades).catch((e) => {
    console.warn('[stockRealtimeIngestor] realtime batch write failed:', String(e.message || e));
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

function handlePolygonMessage(raw) {
  let arr;
  try {
    arr = JSON.parse(String(raw));
  } catch (_) {
    return;
  }
  if (!Array.isArray(arr)) return;
  for (const msg of arr) {
    if (!msg || typeof msg !== 'object') continue;
    if (msg.ev === 'status') {
      const statusText = String(msg.message || msg.status || '');
      if (statusText) console.log(`[stockRealtimeIngestor] status: ${statusText}`);
      continue;
    }
    if (msg.ev !== 'T') continue;
    const symbol = String(msg.sym || '').trim().toUpperCase();
    const price = Number(msg.p);
    if (!symbol || !Number.isFinite(price) || price <= 0) continue;
    pending.set(symbol, price);
  }
}

function connect(apiKey) {
  if (!started || !apiKey) return;
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }
  ws = new WebSocket(POLYGON_WS);
  ws.on('open', () => {
    ws.send(JSON.stringify({ action: 'auth', params: apiKey }));
    ws.send(JSON.stringify({ action: 'subscribe', params: 'T.*' }));
    console.log('[stockRealtimeIngestor] subscribed: T.*');
  });
  ws.on('message', handlePolygonMessage);
  ws.on('error', (e) => {
    console.warn('[stockRealtimeIngestor] ws error:', String(e.message || e));
  });
  ws.on('close', () => {
    ws = null;
    scheduleReconnect(apiKey);
  });
}

function startStockRealtimeIngestor(apiKey) {
  if (started || !apiKey) return;
  if (!supabaseQuoteCache.isConfigured()) {
    console.warn('[stockRealtimeIngestor] Supabase 未配置，跳过实时入库');
    return;
  }
  started = true;
  flushTimer = setInterval(flushPending, FLUSH_INTERVAL_MS);
  connect(apiKey);
}

function stopStockRealtimeIngestor() {
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
  startStockRealtimeIngestor,
  stopStockRealtimeIngestor,
};
