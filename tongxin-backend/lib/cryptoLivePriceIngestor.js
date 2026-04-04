/**
 * cryptoLivePriceIngestor.js
 *
 * Manages per-symbol aggTrade streams dynamically based on what symbols clients
 * are subscribed to. Provides sub-second price updates (up to 10/sec per symbol).
 *
 * Uses Binance combined stream: wss://data-stream.binance.vision/stream?streams=btcusdt@aggTrade/...
 */

const WebSocket = require('ws');
const binance = require('./binance');
const { emitQuote } = require('./marketBroadcast');

const BASE_WS = process.env.BINANCE_STREAM_URL
  ? process.env.BINANCE_STREAM_URL.replace('!miniTicker@arr', '')
  : 'wss://data-stream.binance.vision/stream?streams=';

const MIN_EMIT_INTERVAL_MS = 100; // max 10 updates/sec per symbol
const RECONNECT_DELAY_MS = 3000;
const MAX_STREAMS_PER_CONNECTION = 50;

// Track last emit time per symbol to rate-limit
const lastEmitTime = new Map(); // binanceSymbol -> timestamp ms

// Current active WebSocket connection
let _ws = null;
let _reconnectTimer = null;
let _currentSymbols = []; // display symbols like ['BTC/USD', 'ETH/USD']
let _isConnecting = false;

/**
 * Called externally to update the set of symbols that should have aggTrade streams.
 * @param {string[]} displaySymbols - Array of display symbols like ['BTC/USD', 'ETH/USD']
 */
function updateActiveSymbols(displaySymbols) {
  // Filter to crypto-like symbols (those with a /)
  const cryptoSymbols = (displaySymbols || []).filter((s) => {
    const upper = String(s || '').trim().toUpperCase();
    return upper.includes('/') && !upper.startsWith('EUR/') && !upper.startsWith('USD/') &&
      !upper.startsWith('GBP/') && !upper.startsWith('AUD/') && !upper.startsWith('JPY/');
  });

  // Deduplicate and sort for stable comparison
  const unique = [...new Set(cryptoSymbols.map((s) => String(s).trim().toUpperCase()))].sort();
  const current = [..._currentSymbols].sort();

  // Check if symbols actually changed
  if (unique.length === current.length && unique.every((s, i) => s === current[i])) {
    return; // No change, do nothing
  }

  _currentSymbols = unique;

  if (unique.length === 0) {
    console.log('[cryptoLive] 0 symbols — disconnecting aggTrade stream');
    _disconnect();
    return;
  }

  console.log(`[cryptoLive] subscribing to ${Math.min(unique.length, MAX_STREAMS_PER_CONNECTION)} aggTrade streams: ${unique.slice(0, MAX_STREAMS_PER_CONNECTION).join(', ')}`);
  _reconnectNow();
}

function _reconnectNow() {
  // Cancel any pending reconnect timer
  if (_reconnectTimer) {
    clearTimeout(_reconnectTimer);
    _reconnectTimer = null;
  }
  _disconnect();
  _connect();
}

function _disconnect() {
  if (_ws) {
    const ws = _ws;
    _ws = null;
    try {
      ws.removeAllListeners();
      ws.terminate();
    } catch (_) {}
  }
  _isConnecting = false;
}

function _connect() {
  if (_currentSymbols.length === 0) return;
  if (_isConnecting) return;
  _isConnecting = true;

  // Take up to MAX_STREAMS_PER_CONNECTION symbols
  const symbols = _currentSymbols.slice(0, MAX_STREAMS_PER_CONNECTION);

  // Build stream names: btcusdt@aggTrade/ethusdt@aggTrade/...
  const streams = symbols
    .map((displaySym) => {
      const binanceSym = binance.toBinanceSymbol(displaySym);
      if (!binanceSym) return null;
      return `${binanceSym.toLowerCase()}@aggTrade`;
    })
    .filter(Boolean);

  if (streams.length === 0) {
    _isConnecting = false;
    return;
  }

  const url = `${BASE_WS}${streams.join('/')}`;

  let ws;
  try {
    ws = new WebSocket(url);
  } catch (err) {
    console.error('[cryptoLive] failed to create WebSocket:', err.message);
    _isConnecting = false;
    _scheduleReconnect();
    return;
  }

  _ws = ws;

  ws.on('open', () => {
    _isConnecting = false;
    console.log(`[cryptoLive] aggTrade stream connected (${streams.length} symbols)`);
  });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (_) {
      return;
    }

    // Combined stream format: { stream: 'btcusdt@aggTrade', data: { e: 'aggTrade', s: 'BTCUSDT', p: '...', T: ... } }
    const data = msg?.data;
    if (!data || data.e !== 'aggTrade') return;

    const binanceSym = String(data.s || '').toUpperCase();
    const price = Number(data.p);
    if (!binanceSym || !Number.isFinite(price) || price <= 0) return;

    // Rate limit: max 1 emit per MIN_EMIT_INTERVAL_MS per symbol
    const now = Date.now();
    const lastEmit = lastEmitTime.get(binanceSym) || 0;
    if (now - lastEmit < MIN_EMIT_INTERVAL_MS) return;
    lastEmitTime.set(binanceSym, now);

    // Convert binance symbol back to display symbol
    const displaySymbol = binance.fromBinanceSymbol(binanceSym);
    if (!displaySymbol) return;

    emitQuote({
      symbol: displaySymbol,
      price,
      change: null,
      percent_change: null,
      market: 'crypto',
      timestamp: Number(data.T) || now,
    });
  });

  ws.on('close', (code, reason) => {
    if (_ws !== ws) return; // stale socket
    _isConnecting = false;
    console.log(`[cryptoLive] aggTrade stream closed (code=${code}), reconnecting in ${RECONNECT_DELAY_MS}ms`);
    _ws = null;
    if (_currentSymbols.length > 0) {
      _scheduleReconnect();
    }
  });

  ws.on('error', (err) => {
    if (_ws !== ws) return; // stale socket
    console.error('[cryptoLive] aggTrade stream error:', err.message);
    // close event will follow and handle reconnect
  });
}

function _scheduleReconnect() {
  if (_reconnectTimer) return;
  _reconnectTimer = setTimeout(() => {
    _reconnectTimer = null;
    if (_currentSymbols.length > 0) {
      _connect();
    }
  }, RECONNECT_DELAY_MS);
}

module.exports = { updateActiveSymbols };
