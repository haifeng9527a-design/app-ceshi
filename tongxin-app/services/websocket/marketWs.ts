import { Config } from '../config';

type MarketQuoteCallback = (data: Record<string, any>) => void;

/**
 * Market WebSocket Service
 *
 * Connects to the backend's /ws/market endpoint (no auth required).
 * Subscribes to symbol quote updates and K-line data.
 */
class MarketWebSocket {
  private ws: WebSocket | null = null;
  private listeners = new Map<string, Set<MarketQuoteCallback>>();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private subscribedSymbols = new Set<string>();

  /** Connect to WebSocket server */
  connect() {
    if (this.ws?.readyState === WebSocket.OPEN) return;

    console.log('[MarketWS] Connecting to', Config.WS_MARKET_URL);
    this.ws = new WebSocket(Config.WS_MARKET_URL);

    this.ws.onopen = () => {
      console.log('[MarketWS] Connected');
      this.reconnectAttempts = 0;
      // Re-subscribe all symbols in batch
      if (this.subscribedSymbols.size > 0) {
        this.send({ type: 'subscribe', symbols: [...this.subscribedSymbols] });
      }
    };

    this.ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
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
      this.scheduleReconnect();
    };
  }

  /** Disconnect and clean up */
  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.ws?.close();
    this.ws = null;
    this.reconnectAttempts = 0;
  }

  /** Subscribe to a symbol's quote updates */
  subscribe(symbol: string, callback: MarketQuoteCallback) {
    this.subscribedSymbols.add(symbol);

    if (!this.listeners.has(symbol)) {
      this.listeners.set(symbol, new Set());
    }
    this.listeners.get(symbol)!.add(callback);

    // Send subscribe message if connected (backend expects symbols array)
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.send({ type: 'subscribe', symbols: [symbol] });
    }
  }

  /** Subscribe to multiple symbols at once */
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

  /** Unsubscribe from a symbol */
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

  /** Listen to all incoming messages */
  onMessage(callback: MarketQuoteCallback) {
    if (!this.listeners.has('__all__')) {
      this.listeners.set('__all__', new Set());
    }
    this.listeners.get('__all__')!.add(callback);
  }

  /** Remove global listener */
  offMessage(callback: MarketQuoteCallback) {
    this.listeners.get('__all__')?.delete(callback);
  }

  private send(data: Record<string, any>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  private notifyListeners(data: Record<string, any>) {
    // Handle per-symbol quote message: {type:"quote", symbol:"BTC/USD", price:...}
    const symbol = data.symbol || data.s;
    if (symbol) {
      this.listeners.get(symbol)?.forEach((cb) => cb(data));
    }

    // Handle batch update: {type:"update", symbols:{"BTC/USD":{...}, ...}}
    if (data.type === 'update' && data.symbols && typeof data.symbols === 'object') {
      for (const [sym, quote] of Object.entries(data.symbols)) {
        const q = quote as Record<string, any>;
        const msg = { ...q, symbol: sym, type: 'quote' };
        this.listeners.get(sym)?.forEach((cb) => cb(msg));
      }
    }

    // Notify global listeners
    this.listeners.get('__all__')?.forEach((cb) => cb(data));
  }

  private scheduleReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.warn('[MarketWS] Max reconnect attempts reached');
      return;
    }
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
    console.log(`[MarketWS] Reconnecting in ${delay}ms...`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }
}

/** Singleton instance */
export const marketWs = new MarketWebSocket();
