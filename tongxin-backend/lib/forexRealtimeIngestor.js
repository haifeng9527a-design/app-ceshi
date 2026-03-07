/**
 * 启动即连接 Twelve Data WebSocket，订阅全量外汇交易对；
 * 将实时价格增量批量写入 Supabase forex_quote_cache。
 */
const WebSocket = require('ws');
const supabaseForexCache = require('./supabaseForexCache');

const WS_URL_BASE = 'wss://ws.twelvedata.com/v1/quotes/price';
const FLUSH_INTERVAL_MS = Math.max(300, parseInt(process.env.FOREX_WS_FLUSH_INTERVAL_MS || '1500', 10));
const RECONNECT_DELAY_MS = Math.max(1000, parseInt(process.env.FOREX_WS_RECONNECT_DELAY_MS || '3000', 10));
const RESYNC_INTERVAL_MS = Math.max(60 * 1000, parseInt(process.env.FOREX_WS_RESYNC_INTERVAL_MS || `${60 * 60 * 1000}`, 10));
const SUBSCRIBE_CHUNK_SIZE = Math.max(1, parseInt(process.env.FOREX_WS_SUBSCRIBE_CHUNK_SIZE || '200', 10));

let ws = null;
let started = false;
let reconnectTimer = null;
let flushTimer = null;
let resyncTimer = null;
const pending = new Map(); // symbol -> latest update
let inboundCount = 0;
let lastInboundLogAt = 0;

function flushPending() {
  if (pending.size === 0) return;
  const updates = [];
  for (const [, item] of pending) {
    updates.push(item);
  }
  pending.clear();
  const sample = updates.slice(0, 5).map((u) => `${u.symbol}:${u.price}`).join(', ');
  const startedAt = Date.now();
  supabaseForexCache.setForexRealtimePricesBatch(updates)
    .then(() => {
      const cost = Date.now() - startedAt;
      console.log(`[forexRealtimeIngestor] cache update ok count=${updates.length} cost=${cost}ms sample=[${sample}]`);
    })
    .catch((e) => {
      console.warn('[forexRealtimeIngestor] realtime batch write failed:', String(e.message || e));
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

  // 订阅反馈 / 状态消息
  if (msg.status || msg.success || msg.fails || msg.message) {
    const text = [
      msg.status ? `status=${msg.status}` : null,
      Array.isArray(msg.success) ? `success=${msg.success.length}` : null,
      Array.isArray(msg.fails) ? `fails=${msg.fails.length}` : null,
      msg.message ? `message=${String(msg.message)}` : null,
    ].filter(Boolean).join(' ');
    if (text) console.log(`[forexRealtimeIngestor] ${text}`);
  }

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
  const symbols = await supabaseForexCache.getAllForexSymbols();
  if (!Array.isArray(symbols) || symbols.length === 0) {
    console.warn('[forexRealtimeIngestor] no forex symbols available to subscribe');
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
  console.log(`[forexRealtimeIngestor] subscribed forex symbols=${symbols.length} chunks=${chunks}`);
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
      console.warn('[forexRealtimeIngestor] subscribe failed:', String(e.message || e));
    });
  });
  ws.on('message', (raw) => {
    const item = parseInboundMessage(raw);
    if (!item) return;
    pending.set(item.symbol, item);
    inboundCount += 1;
    const now = Date.now();
    // 控制台输出“订阅收到数据”状态：每 3 秒最多一条，防止刷屏
    if (now - lastInboundLogAt >= 3000) {
      lastInboundLogAt = now;
      console.log(
        `[forexRealtimeIngestor] subscribed data recv total=${inboundCount} pending=${pending.size} ` +
        `latest=${item.symbol}:${item.price}`
      );
    }
  });
  ws.on('error', (e) => {
    console.warn('[forexRealtimeIngestor] ws error:', String(e.message || e));
  });
  ws.on('close', () => {
    ws = null;
    scheduleReconnect(apiKey);
  });
}

function startForexRealtimeIngestor(apiKey) {
  if (started || !apiKey) return;
  if (!supabaseForexCache.isConfigured()) {
    console.warn('[forexRealtimeIngestor] Supabase 未配置，跳过实时入库');
    return;
  }
  started = true;
  inboundCount = 0;
  lastInboundLogAt = 0;
  flushTimer = setInterval(flushPending, FLUSH_INTERVAL_MS);
  resyncTimer = setInterval(() => {
    subscribeAllSymbols().catch((e) => {
      console.warn('[forexRealtimeIngestor] periodic resubscribe failed:', String(e.message || e));
    });
  }, RESYNC_INTERVAL_MS);
  connect(apiKey);
}

function stopForexRealtimeIngestor() {
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
  startForexRealtimeIngestor,
  stopForexRealtimeIngestor,
};
