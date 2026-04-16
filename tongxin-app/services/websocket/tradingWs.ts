import { Config } from '../config';
import { getStoredToken } from '../api/client';

type TradingEventCallback = (data: any) => void;
type ReconnectCallback = () => void;

type EventType =
  | 'order_created'
  | 'order_filled'
  | 'order_cancelled'
  | 'position_update'
  | 'position_closed'
  | 'position_liquidated'
  | 'balance_update'
  | 'account_update'
  | 'copy_trade_opened'
  | 'copy_trade_closed'
  // spot events (backend: internal/service/spot_service.go pushSpotOrderEvent)
  | 'spot_order_placed'
  | 'spot_order_filled'
  | 'spot_order_cancelled'
  | 'spot_balance_update';

/**
 * Trading WebSocket Service
 *
 * Connects to /ws/trading with JWT token.
 * Receives real-time trading events: order fills, position updates, balance changes.
 * Persistent connection — survives page switches, auto-reconnects on failure.
 */
class TradingWebSocket {
  private ws: WebSocket | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 50;
  private _connected = false;
  private _intentionalClose = false;
  private lastPongTime = 0;
  private onReconnectCallbacks: Set<ReconnectCallback> = new Set();

  private listeners: Record<EventType, Set<TradingEventCallback>> = {
    order_created: new Set(),
    order_filled: new Set(),
    order_cancelled: new Set(),
    position_update: new Set(),
    position_closed: new Set(),
    position_liquidated: new Set(),
    balance_update: new Set(),
    account_update: new Set(),
    copy_trade_opened: new Set(),
    copy_trade_closed: new Set(),
    spot_order_placed: new Set(),
    spot_order_filled: new Set(),
    spot_order_cancelled: new Set(),
    spot_balance_update: new Set(),
  };

  get connected() {
    return this._connected;
  }

  async connect(): Promise<void> {
    if (this.ws?.readyState === WebSocket.OPEN) return;
    if (this.ws?.readyState === WebSocket.CONNECTING) return;

    this._intentionalClose = false;

    let token: string | null;
    try {
      token = await getStoredToken();
      if (!token) {
        console.warn('[TradingWS] No JWT token, cannot connect');
        return;
      }
    } catch (e) {
      console.warn('[TradingWS] Failed to get token:', e);
      return;
    }

    const url = `${Config.WS_TRADING_URL}?token=${encodeURIComponent(token)}`;
    console.log('[TradingWS] Connecting...');

    try {
      this.ws = new WebSocket(url);
    } catch (e) {
      console.warn('[TradingWS] WebSocket constructor failed:', e);
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      const isReconnect = this.reconnectAttempts > 0;
      console.log(`[TradingWS] Connected${isReconnect ? ' (reconnected)' : ''}`);
      this._connected = true;
      this.reconnectAttempts = 0;
      this.lastPongTime = Date.now();
      this.startHeartbeat();
      // On reconnect, refresh data to catch any missed WS messages
      if (isReconnect) {
        this.onReconnectCallbacks.forEach((cb) => cb());
      }
    };

    this.ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data as string);
        if (data.type === 'pong' || data.type === 'connected') {
          this.lastPongTime = Date.now();
        }
        this.handleMessage(data);
      } catch (e) {
        console.warn('[TradingWS] Parse error:', e);
      }
    };

    this.ws.onerror = () => {
      console.error('[TradingWS] Connection error');
    };

    this.ws.onclose = () => {
      console.log('[TradingWS] Disconnected');
      this._connected = false;
      this.stopHeartbeat();
      if (!this._intentionalClose) {
        this.scheduleReconnect();
      }
    };
  }

  disconnect() {
    this._intentionalClose = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.stopHeartbeat();
    this.ws?.close();
    this.ws = null;
    this._connected = false;
    this.reconnectAttempts = 0;
  }

  on(event: EventType, cb: TradingEventCallback) {
    this.listeners[event]?.add(cb);
  }

  off(event: EventType, cb: TradingEventCallback) {
    this.listeners[event]?.delete(cb);
  }

  onReconnect(cb: ReconnectCallback) {
    this.onReconnectCallbacks.add(cb);
  }

  offReconnect(cb: ReconnectCallback) {
    this.onReconnectCallbacks.delete(cb);
  }

  private handleMessage(data: any) {
    const type = data.type as EventType;
    if (type && this.listeners[type]) {
      this.listeners[type].forEach((cb) => cb(data.data));
    }
  }

  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ type: 'ping' }));

        // Check if server responded to recent pings (pong health check)
        const elapsed = Date.now() - this.lastPongTime;
        if (elapsed > 45000) {
          // No pong for 45s — connection is dead, force reconnect
          console.warn('[TradingWS] No pong for 45s, forcing reconnect');
          this.ws?.close();
        }
      }
    }, 15000); // ping every 15s (was 25s — more aggressive keepalive)
  }

  private stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  private scheduleReconnect() {
    if (this._intentionalClose) return;
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.warn('[TradingWS] Max reconnect attempts reached');
      return;
    }
    // Fast reconnect: 500ms, 1s, 2s, 4s, max 10s
    const delay = Math.min(500 * Math.pow(2, this.reconnectAttempts), 10000);
    console.log(`[TradingWS] Reconnecting in ${delay}ms...`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }
}

export const tradingWs = new TradingWebSocket();
