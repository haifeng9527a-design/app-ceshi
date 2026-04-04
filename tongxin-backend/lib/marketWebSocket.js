/**
 * 独立行情 WebSocket：/ws/market
 * - 无需鉴权，任何客户端均可连接
 * - 客户端发送：{ type: 'subscribe',   symbols: ['BTC/USD','ETH/USD','AAPL'] }
 * - 客户端发送：{ type: 'unsubscribe', symbols: ['AAPL'] }
 * - 客户端发送：{ type: 'ping' }
 * - 服务端推送：{ type: 'quote', symbol, price, change, percent_change, market, timestamp }
 * - 服务端推送：{ type: 'pong' }
 * - 服务端推送：{ type: 'subscribed', symbols: [...] }
 */
const WebSocket = require('ws');
const { marketBroadcast } = require('./marketBroadcast');
const { updateActiveSymbols } = require('./cryptoLivePriceIngestor');

// symbol -> Set<WebSocket>
const symbolSubs = new Map();
// WebSocket -> Set<string symbols>
const clientSymbols = new WeakMap();

const MAX_SYMBOLS_PER_CLIENT = 100;

function send(ws, payload) {
  if (ws.readyState === WebSocket.OPEN) {
    try { ws.send(JSON.stringify(payload)); } catch (_) {}
  }
}

function _refreshLiveSubscriptions() {
  const allSymbols = [...symbolSubs.keys()];
  updateActiveSymbols(allSymbols);
}

function subscribe(ws, symbols) {
  if (!Array.isArray(symbols)) return;
  const mySymbols = clientSymbols.get(ws) || new Set();
  for (const raw of symbols) {
    const sym = String(raw).trim().toUpperCase();
    if (!sym) continue;
    if (mySymbols.size >= MAX_SYMBOLS_PER_CLIENT) break;
    mySymbols.add(sym);
    if (!symbolSubs.has(sym)) symbolSubs.set(sym, new Set());
    symbolSubs.get(sym).add(ws);
  }
  clientSymbols.set(ws, mySymbols);
  send(ws, { type: 'subscribed', symbols: [...mySymbols] });
  _refreshLiveSubscriptions();
}

function unsubscribe(ws, symbols) {
  if (!Array.isArray(symbols)) return;
  const mySymbols = clientSymbols.get(ws);
  if (!mySymbols) return;
  for (const raw of symbols) {
    const sym = String(raw).trim().toUpperCase();
    mySymbols.delete(sym);
    const set = symbolSubs.get(sym);
    if (set) {
      set.delete(ws);
      if (set.size === 0) symbolSubs.delete(sym);
    }
  }
  _refreshLiveSubscriptions();
}

function cleanup(ws) {
  const mySymbols = clientSymbols.get(ws);
  if (!mySymbols) return;
  for (const sym of mySymbols) {
    const set = symbolSubs.get(sym);
    if (set) {
      set.delete(ws);
      if (set.size === 0) symbolSubs.delete(sym);
    }
  }
  mySymbols.clear();
  _refreshLiveSubscriptions();
}

// 监听 ingestors 广播，推给已订阅的客户端
marketBroadcast.on('quote', (update) => {
  if (!update?.symbol) return;
  const sym = String(update.symbol).toUpperCase();
  const set = symbolSubs.get(sym);
  if (!set || set.size === 0) return;
  const payload = JSON.stringify({
    type: 'quote',
    symbol: update.symbol,
    price: update.price,
    change: update.change ?? null,
    percent_change: update.percent_change ?? null,
    market: update.market ?? null,
    open: update.open ?? null,
    high: update.high ?? null,
    low: update.low ?? null,
    volume: update.volume ?? null,
    timestamp: update.timestamp ?? Date.now(),
  });
  for (const ws of set) {
    if (ws.readyState === WebSocket.OPEN) {
      try { ws.send(payload); } catch (_) {}
    }
  }
});

function createMarketWsServer(httpServer) {
  const wss = new WebSocket.Server({ server: httpServer, path: '/ws/market' });

  wss.on('connection', (ws, req) => {
    clientSymbols.set(ws, new Set());
    const ip = req.socket.remoteAddress;
    console.log(`[marketWs] client connected (${ip}), total=${wss.clients.size}`);

    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw); } catch (_) { return; }
      const { type, symbols } = msg || {};
      if (type === 'subscribe')   subscribe(ws, symbols);
      if (type === 'unsubscribe') unsubscribe(ws, symbols);
      if (type === 'ping')        send(ws, { type: 'pong' });
    });

    ws.on('close', () => {
      cleanup(ws);
      console.log(`[marketWs] client disconnected, total=${wss.clients.size}`);
    });

    ws.on('error', () => cleanup(ws));

    // 欢迎消息，告诉客户端连接成功
    send(ws, { type: 'connected', message: 'market websocket ready' });
  });

  console.log('[marketWs] /ws/market ready');
  return wss;
}

module.exports = { createMarketWsServer };
