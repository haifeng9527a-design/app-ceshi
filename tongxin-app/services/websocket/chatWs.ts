import { Config } from '../config';

function wsChatOrigin(): string {
  try {
    const u = new URL(Config.WS_CHAT_URL);
    return `${u.protocol}//${u.host}${u.pathname}`;
  } catch {
    return Config.WS_CHAT_URL;
  }
}
import { getStoredToken } from '../api/client';
import type { ApiMessage } from '../api/messagesApi';
import type { CallRecord } from '../api/callsApi';

type NewMessageCallback = (message: ApiMessage) => void;
type ErrorCallback = (error: string) => void;
type ConnectedCallback = (conversationIds: string[]) => void;

export type FriendRequestWsPayload = {
  request_id: string;
  from_user_id: string;
  from_display_name?: string;
};

export type FriendAcceptedWsPayload = {
  accepter_user_id: string;
  accepter_display_name?: string;
};

type FriendRequestCallback = (payload: FriendRequestWsPayload) => void;
type FriendAcceptedCallback = (payload: FriendAcceptedWsPayload) => void;
type CallEventType = 'call_invite' | 'call_accepted' | 'call_rejected' | 'call_ended';
export type CallWsPayload = {
  type: CallEventType;
  call: CallRecord;
  actor_id?: string;
};
type CallEventCallback = (payload: CallWsPayload) => void;

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
  private friendRequestListeners = new Set<FriendRequestCallback>();
  private friendAcceptedListeners = new Set<FriendAcceptedCallback>();
  private callEventListeners = new Set<CallEventCallback>();

  private _connected = false;
  /** 供 zustand 同步 wsConnected（含断线重连成功） */
  private connectionStateHandler: ((open: boolean) => void) | null = null;

  get connected() {
    return this._connected;
  }

  /** 连接/断开时回调（open=true 含首次连接与重连成功） */
  setConnectionStateHandler(handler: ((open: boolean) => void) | null) {
    this.connectionStateHandler = handler;
  }

  private emitConnectionState(open: boolean) {
    try {
      this.connectionStateHandler?.(open);
    } catch (_) {
      /* ignore */
    }
  }

  /**
   * Connect using stored JWT token.
   * @returns true when the socket is OPEN（此前实现未等待 onopen，导致 store 里 wsConnected 长期为 false、订阅被跳过）
   */
  async connect(): Promise<boolean> {
    if (this.ws?.readyState === WebSocket.OPEN) {
      return true;
    }

    let token: string | null;
    try {
      token = await getStoredToken();
      if (!token) {
        console.warn('[ChatWS] No JWT token, cannot connect');
        return false;
      }
    } catch (e) {
      console.warn('[ChatWS] Failed to get token:', e);
      return false;
    }

    const url = `${Config.WS_CHAT_URL}?token=${encodeURIComponent(token)}`;
    console.log('[ChatWS] Connecting to', wsChatOrigin(), '(token hidden)');

    return new Promise((resolve) => {
      const ws = new WebSocket(url);
      this.ws = ws;
      let settled = false;

      const finish = (success: boolean) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeoutId);
        resolve(success);
      };

      const timeoutId = setTimeout(() => {
        if (settled) return;
        try {
          ws.close();
        } catch {
          /* ignore */
        }
        finish(false);
      }, 20000);

      const isCurrent = () => this.ws === ws;

      ws.onopen = () => {
        if (!isCurrent()) return;
        console.log('[ChatWS] Connected');
        this._connected = true;
        this.reconnectAttempts = 0;
        this.startHeartbeat();
        if (this.pendingSubscriptions.length > 0) {
          this.subscribe(this.pendingSubscriptions);
        }
        this.emitConnectionState(true);
        finish(true);
      };

      ws.onmessage = (event) => {
        if (!isCurrent()) return;
        try {
          const data = JSON.parse(event.data as string);
          this.handleMessage(data);
        } catch (e) {
          console.warn('[ChatWS] Parse error:', e);
        }
      };

      // React Native 上部分环境会先触发 onerror 仍能 onopen，此处勿 resolve(false)，由 onclose 判定失败
      ws.onerror = (ev) => {
        if (!isCurrent()) return;
        console.error(
          '[ChatWS] Connection error — 若 API 用局域网 IP，请确认 WS 也指向同一主机；Node 服务端需 Firebase ID Token，Go 服务端需与登录相同的 JWT（见 services/config.ts）',
          ev,
        );
      };

      ws.onclose = (ev) => {
        if (!isCurrent()) return;
        console.warn('[ChatWS] Disconnected', {
          code: ev.code,
          reason: ev.reason || '(none)',
          wasClean: ev.wasClean,
        });
        this._connected = false;
        this.stopHeartbeat();
        this.emitConnectionState(false);
        if (!settled) {
          finish(false);
        } else {
          this.scheduleReconnect();
        }
      };
    });
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
    this.emitConnectionState(false);
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

  onFriendRequest(callback: FriendRequestCallback) {
    this.friendRequestListeners.add(callback);
  }

  offFriendRequest(callback: FriendRequestCallback) {
    this.friendRequestListeners.delete(callback);
  }

  onFriendAccepted(callback: FriendAcceptedCallback) {
    this.friendAcceptedListeners.add(callback);
  }

  offFriendAccepted(callback: FriendAcceptedCallback) {
    this.friendAcceptedListeners.delete(callback);
  }

  onCallEvent(callback: CallEventCallback) {
    this.callEventListeners.add(callback);
  }

  offCallEvent(callback: CallEventCallback) {
    this.callEventListeners.delete(callback);
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
        {
          const message = String(data.message ?? data.error ?? 'unknown error');
          console.warn('[ChatWS] Server error:', message);
          this.errorListeners.forEach((cb) => cb(message));
        }
        break;
      case 'pong':
        // heartbeat response
        break;
      case 'friend_request':
        this.friendRequestListeners.forEach((cb) =>
          cb({
            request_id: String(data.request_id ?? ''),
            from_user_id: String(data.from_user_id ?? ''),
            from_display_name: data.from_display_name,
          }),
        );
        break;
      case 'friend_accepted':
        this.friendAcceptedListeners.forEach((cb) =>
          cb({
            accepter_user_id: String(data.accepter_user_id ?? ''),
            accepter_display_name: data.accepter_display_name,
          }),
        );
        break;
      case 'call_invite':
      case 'call_accepted':
      case 'call_rejected':
      case 'call_ended':
        if (data.call) {
          this.callEventListeners.forEach((cb) =>
            cb({
              type: data.type,
              call: data.call,
              actor_id: data.actor_id ? String(data.actor_id) : undefined,
            }),
          );
        }
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
      void this.connect();
    }, delay);
  }
}

/** Singleton instance */
export const chatWs = new ChatWebSocket();
