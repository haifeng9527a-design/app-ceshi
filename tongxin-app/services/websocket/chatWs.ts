import { Config } from '../config';
import { getStoredToken } from '../api/client';
import type { ApiMessage } from '../api/messagesApi';

type NewMessageCallback = (message: ApiMessage) => void;
type ErrorCallback = (error: string) => void;
type ConnectedCallback = (conversationIds: string[]) => void;

/**
 * Chat WebSocket Service
 *
 * Connects to /ws/chat with JWT token.
 * Subscribes to conversation updates and sends messages in real-time.
 */
class ChatWebSocket {
  private ws: WebSocket | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;

  private pendingSubscriptions: string[] = [];
  private newMessageListeners = new Set<NewMessageCallback>();
  private errorListeners = new Set<ErrorCallback>();
  private connectedListeners = new Set<ConnectedCallback>();

  private _connected = false;

  get connected() {
    return this._connected;
  }

  /** Connect using stored JWT token */
  async connect(): Promise<void> {
    if (this.ws?.readyState === WebSocket.OPEN) return;

    let token: string | null;
    try {
      token = await getStoredToken();
      if (!token) {
        console.warn('[ChatWS] No JWT token, cannot connect');
        return;
      }
    } catch (e) {
      console.warn('[ChatWS] Failed to get token:', e);
      return;
    }

    const url = `${Config.WS_CHAT_URL}?token=${encodeURIComponent(token)}`;
    console.log('[ChatWS] Connecting...');

    this.ws = new WebSocket(url);

    this.ws.onopen = () => {
      console.log('[ChatWS] Connected');
      this._connected = true;
      this.reconnectAttempts = 0;
      this.startHeartbeat();

      // Re-subscribe pending conversations
      if (this.pendingSubscriptions.length > 0) {
        this.subscribe(this.pendingSubscriptions);
      }
    };

    this.ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data as string);
        this.handleMessage(data);
      } catch (e) {
        console.warn('[ChatWS] Parse error:', e);
      }
    };

    this.ws.onerror = () => {
      console.error('[ChatWS] Connection error');
    };

    this.ws.onclose = () => {
      console.log('[ChatWS] Disconnected');
      this._connected = false;
      this.stopHeartbeat();
      this.scheduleReconnect();
    };
  }

  /** Disconnect and clean up */
  disconnect() {
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

  /** Subscribe to conversation updates */
  subscribe(conversationIds: string[]) {
    this.pendingSubscriptions = [
      ...new Set([...this.pendingSubscriptions, ...conversationIds]),
    ];

    if (this.ws?.readyState === WebSocket.OPEN) {
      this.send({ type: 'subscribe', conversation_ids: conversationIds });
    }
  }

  /** Send a message via WebSocket */
  sendMessage(
    conversationId: string,
    content: string,
    messageType: string = 'text',
    extras?: {
      media_url?: string;
      reply_to_message_id?: string;
      reply_to_sender_name?: string;
      reply_to_content?: string;
    },
  ) {
    this.send({
      type: 'send',
      conversation_id: conversationId,
      content,
      message_type: messageType,
      ...extras,
    });
  }

  /** Listen for new messages */
  onNewMessage(callback: NewMessageCallback) {
    this.newMessageListeners.add(callback);
  }

  offNewMessage(callback: NewMessageCallback) {
    this.newMessageListeners.delete(callback);
  }

  /** Listen for errors */
  onError(callback: ErrorCallback) {
    this.errorListeners.add(callback);
  }

  offError(callback: ErrorCallback) {
    this.errorListeners.delete(callback);
  }

  /** Listen for subscription confirmations */
  onConnected(callback: ConnectedCallback) {
    this.connectedListeners.add(callback);
  }

  offConnected(callback: ConnectedCallback) {
    this.connectedListeners.delete(callback);
  }

  private send(data: Record<string, any>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  private handleMessage(data: any) {
    switch (data.type) {
      case 'new_message':
        if (data.message) {
          this.newMessageListeners.forEach((cb) => cb(data.message));
        }
        break;
      case 'subscribed':
        if (data.conversation_ids) {
          this.connectedListeners.forEach((cb) => cb(data.conversation_ids));
        }
        break;
      case 'error':
        console.warn('[ChatWS] Server error:', data.error);
        this.errorListeners.forEach((cb) => cb(data.error));
        break;
      case 'pong':
        // heartbeat response
        break;
      default:
        break;
    }
  }

  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.send({ type: 'ping' });
    }, 25000);
  }

  private stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  private scheduleReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.warn('[ChatWS] Max reconnect attempts reached');
      return;
    }
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
    console.log(`[ChatWS] Reconnecting in ${delay}ms...`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }
}

/** Singleton instance */
export const chatWs = new ChatWebSocket();
