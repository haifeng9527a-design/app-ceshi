import { Config } from '../config';

type MarketQuoteCallback = (data: Record<string, any>) => void;

/**
 * Market WebSocket Service
 *
 * Connects to the backend's /ws/market endpoint (no auth required).
 * Features: unlimited reconnect, heartbeat with latency measurement, connection status events.
 */
class MarketWebSocket {
  private ws: WebSocket | null = null;
  private listeners = new Map<string, Set<MarketQuoteCallback>>();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private reconnectAttempts = 0;
  private subscribedSymbols = new Set<string>();
  private _connected = false;
  private _latency = -1; // ms, -1 = unknown
  private _pingTs = 0;   // timestamp when ping was sent

  get connected() { return this._connected; }
  get latency() { return this._latency; }

  connect() {
    if (this.ws?.readyState === WebSocket.OPEN) return;

    console.log('[MarketWS] Connecting to', Config.WS_MARKET_URL);
    try {
      this.ws = new WebSocket(Config.WS_MARKET_URL);
    } catch (e) {
      console.error('[MarketWS] Failed to create WebSocket:', e);
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      console.log('[MarketWS] Connected');
      this._connected = true;
      this.reconnectAttempts = 0;
      this.startHeartbeat();
      if (this.subscribedSymbols.size > 0) {
        this.send({ type: 'subscribe', symbols: [...this.subscribedSymbols] });
      }
      this.notifyListeners({ type: 'ws_status', connected: true, latency: this._latency });
      // Measure latency immediately
      this.measureLatency();
    };

    this.ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        // Measure latency from pong response
        if (data.type === 'pong' && this._pingTs > 0) {
          this._latency = Date.now() - this._pingTs;
          this._pingTs = 0;
          this.notifyListeners({ type: 'ws_latency', latency: this._latency, connected: true });
          return;
        }
        this.notifyListeners(data);
      } catch (e) {
        console.warn('[MarketWS] Parse error:', e);
      }
    };

    this.ws.onerror = (e) => {
      console.error('[MarketWS] Error:', e);
    };

    this.ws.onclose = () => {
      console.log('[MarketWS] Disconnected');
      this._connected = false;
      this._latency = -1;
      this.stopHeartbeat();
      this.notifyListeners({ type: 'ws_status', connected: false, latency: -1 });
      this.scheduleReconnect();
    };
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.stopHeartbeat();
    this.ws?.close();
    this.ws = null;
    this.reconnectAttempts = 0;
    this._connected = false;
    this._latency = -1;
  }

  subscribe(symbol: string, callback: MarketQuoteCallback) {
    this.subscribedSymbols.add(symbol);
    if (!this.listeners.has(symbol)) {
      this.listeners.set(symbol, new Set());
    }
    this.listeners.get(symbol)!.add(callback);
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.send({ type: 'subscribe', symbols: [symbol] });
    }
  }

  subscribeMany(symbols: string[], callback: MarketQuoteCallback) {
    for (const s of symbols) {
      this.subscribedSymbols.add(s);
      if (!this.listeners.has(s)) {
        this.listeners.set(s, new Set());
      }
      this.listeners.get(s)!.add(callback);
    }
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.send({ type: 'subscribe', symbols });
    }
  }

  unsubscribe(symbol: string, callback: MarketQuoteCallback) {
    const cbs = this.listeners.get(symbol);
    if (cbs) {
      cbs.delete(callback);
      if (cbs.size === 0) {
        this.listeners.delete(symbol);
        this.subscribedSymbols.delete(symbol);
        if (this.ws?.readyState === WebSocket.OPEN) {
          this.send({ type: 'unsubscribe', symbols: [symbol] });
        }
      }
    }
  }

  onMessage(callback: MarketQuoteCallback) {
    if (!this.listeners.has('__all__')) {
      this.listeners.set('__all__', new Set());
    }
    this.listeners.get('__all__')!.add(callback);
  }

  offMessage(callback: MarketQuoteCallback) {
    this.listeners.get('__all__')?.delete(callback);
  }

  private send(data: Record<string, any>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  private measureLatency() {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this._pingTs = Date.now();
      this.send({ type: 'ping' });
    }
  }

  private notifyListeners(data: Record<string, any>) {
    const symbol = data.symbol || data.s;
    if (symbol) {
      this.listeners.get(symbol)?.forEach((cb) => cb(data));
    }
    if (data.type === 'update' && data.symbols && typeof data.symbols === 'object') {
      for (const [sym, quote] of Object.entries(data.symbols)) {
        const q = quote as Record<string, any>;
        const msg = { ...q, symbol: sym, type: 'quote' };
        this.listeners.get(sym)?.forEach((cb) => cb(msg));
      }
    }
    this.listeners.get('__all__')?.forEach((cb) => cb(data));
  }

  /** Heartbeat every 10s: keeps connection alive + measures latency */
  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.measureLatency();
    }, 10000);
  }

  private stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) return;
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
    console.log(`[MarketWS] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts + 1})...`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }
}

export const marketWs = new MarketWebSocket();
