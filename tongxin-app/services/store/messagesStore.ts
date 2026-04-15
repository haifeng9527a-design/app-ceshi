import { create } from 'zustand';
import {
  fetchConversations,
  ensureMySupportAssignment,
  fetchMessages,
  sendMessageHttp,
  markAsRead,
  fetchUnreadCount,
  fetchUserProfilesBatch,
  fetchFriends,
  fetchIncomingFriendRequests,
  fetchOutgoingFriendRequests,
  type ApiConversation,
  type ApiMessage,
  type ApiFriendRequest,
  type PeerProfile,
  type FriendProfile,
  type SupportAssignmentDetail,
} from '../api/messagesApi';
import { chatWs, type ChatConnectionStatus } from '../websocket/chatWs';
import { useAuthStore } from './authStore';

/** 会话 id 可能来自不同路径，避免严格 === 导致新消息无法并入当前聊天 */
function sameConvoId(a: string | null | undefined, b: string | null | undefined): boolean {
  return String(a ?? '').trim() === String(b ?? '').trim();
}

function normId(v: string | null | undefined): string {
  return String(v ?? '').trim();
}

interface MessagesState {
  // Conversation list
  conversations: ApiConversation[];
  conversationsLoading: boolean;

  // Active conversation messages
  activeConversationId: string | null;
  messages: ApiMessage[];
  messagesLoading: boolean;
  hasMoreMessages: boolean;

  // Peer profiles cache (userId -> profile)
  peerProfiles: Record<string, PeerProfile>;

  // Friends list
  friends: FriendProfile[];
  friendsError: string | null;

  // System support conversation
  supportAssignment: SupportAssignmentDetail | null;

  /** 待处理的好友申请（收到的） */
  incomingFriendRequests: ApiFriendRequest[];
  /** 已发出、待对方处理 */
  outgoingFriendRequests: ApiFriendRequest[];

  // Unread
  totalUnread: number;

  // WebSocket
  wsConnected: boolean;
  wsStatus: ChatConnectionStatus;

  // Actions
  loadConversations: () => Promise<void>;
  loadMessages: (conversationId: string, previousActiveId?: string | null) => Promise<void>;
  loadMoreMessages: () => Promise<void>;
  sendMessage: (payload: {
    content?: string;
    messageType?: ApiMessage['message_type'];
    mediaUrl?: string;
    metadata?: Record<string, unknown>;
  }) => Promise<void>;
  retryMessage: (messageId: string) => Promise<void>;
  markConversationRead: (conversationId: string) => Promise<void>;
  setActiveConversation: (id: string | null) => void;
  connectWs: () => Promise<void>;
  disconnectWs: () => void;
  handleNewMessage: (message: ApiMessage) => void;
  loadFriends: () => Promise<void>;
  loadFriendRequests: () => Promise<void>;
  loadUnreadCount: () => Promise<void>;
  /** 当前会话静默拉取（给接收方兜底：WS 未推送时仍能看见新消息） */
  refreshActiveMessages: () => Promise<void>;
  flushQueuedMessages: () => Promise<void>;
  mergePeerProfiles: (profiles: Record<string, PeerProfile>) => void;
}

export const useMessagesStore = create<MessagesState>((set, get) => {
  // WS new message handler reference (for cleanup)
  const wsMessageHandler = (message: ApiMessage) => {
    get().handleNewMessage(message);
  };
  let wsBound = false;

  const isRetriableSendError = (e: unknown): boolean => {
    const status = (e as any)?.response?.status;
    const message = String((e as any)?.message ?? '').toLowerCase();
    return (
      status == null ||
      status >= 500 ||
      message.includes('network error') ||
      message.includes('timeout') ||
      message.includes('failed to fetch')
    );
  };

  const sendStoredMessage = async (message: ApiMessage) => {
    await sendMessageHttp({
      conversation_id: message.conversation_id,
      content: message.content,
      message_type: message.message_type,
      media_url: message.media_url,
      metadata: message.metadata,
      reply_to_message_id: message.reply_to_message_id,
      reply_to_sender_name: message.reply_to_sender_name,
      reply_to_content: message.reply_to_content,
    });
  };

  return {
    conversations: [],
    conversationsLoading: false,
    activeConversationId: null,
    messages: [],
    messagesLoading: false,
    hasMoreMessages: true,
    peerProfiles: {},
    friends: [],
    friendsError: null,
    supportAssignment: null,
    incomingFriendRequests: [],
    outgoingFriendRequests: [],
    totalUnread: 0,
    wsConnected: false,
    wsStatus: 'disconnected',

    mergePeerProfiles: (profiles) => {
      if (!profiles || Object.keys(profiles).length === 0) return;
      set((state) => ({
        peerProfiles: { ...state.peerProfiles, ...profiles },
      }));
    },

    loadConversations: async () => {
      set({ conversationsLoading: true });
      try {
        let supportAssignment: SupportAssignmentDetail | null = null;
        const currentUser = useAuthStore.getState().user;
        if (!currentUser?.isSupportAgent) {
          try {
            supportAssignment = await ensureMySupportAssignment();
          } catch (supportErr: any) {
            const status = supportErr?.response?.status;
            if (status && status !== 404) {
              console.warn('[MessagesStore] ensure support assignment failed:', supportErr);
            }
          }
        }
        if (
          supportAssignment?.assignment &&
          currentUser?.uid &&
          (
            supportAssignment.assignment.customer_uid === supportAssignment.assignment.agent_uid ||
            supportAssignment.assignment.agent_uid === currentUser.uid
          )
        ) {
          supportAssignment = null;
        }

        const conversations = await fetchConversations();
        set({ conversations, conversationsLoading: false, supportAssignment });

        // Fetch peer profiles for direct conversations
        const peerIds = conversations
          .filter((c) => c.type === 'direct' && c.peer_id)
          .map((c) => c.peer_id!)
          .filter((id) => !get().peerProfiles[id]);

        if (peerIds.length > 0) {
          const profiles = await fetchUserProfilesBatch(peerIds);
          set((state) => ({
            peerProfiles: { ...state.peerProfiles, ...profiles },
          }));
        }

        const ids = conversations.map((c) => c.id).filter(Boolean);
        if (chatWs.connected && ids.length > 0) {
          chatWs.subscribe(ids);
        }
      } catch (e) {
        console.error('[MessagesStore] loadConversations failed:', e);
        set({ conversationsLoading: false });
      }
    },

    loadMessages: async (conversationId: string, previousActiveId: string | null = null) => {
      const isSwitch = !sameConvoId(previousActiveId, conversationId);
      set({
        activeConversationId: conversationId,
        messagesLoading: true,
        messages: isSwitch ? [] : get().messages,
        hasMoreMessages: isSwitch ? true : get().hasMoreMessages,
      });
      try {
        const messages = await fetchMessages(conversationId, 50);
        set((state) => {
          if (!sameConvoId(state.activeConversationId, conversationId)) return state;
          return {
            messages,
            messagesLoading: false,
            hasMoreMessages: messages.length >= 50,
          };
        });
        if (chatWs.connected) {
          chatWs.subscribe([conversationId]);
        }
        // Mark as read
        markAsRead(conversationId).catch(() => {});
        // Update local unread count
        set((state) => ({
          conversations: state.conversations.map((c) =>
            sameConvoId(c.id, conversationId) ? { ...c, unread_count: 0 } : c,
          ),
          totalUnread: Math.max(
            0,
            state.totalUnread -
              (state.conversations.find((c) => sameConvoId(c.id, conversationId))?.unread_count ?? 0),
          ),
        }));
      } catch (e) {
        console.error('[MessagesStore] loadMessages failed:', e);
        set((state) => {
          if (!sameConvoId(state.activeConversationId, conversationId)) return state;
          return { messagesLoading: false };
        });
      }
    },

    loadMoreMessages: async () => {
      const { activeConversationId, messages, hasMoreMessages, messagesLoading } = get();
      if (!activeConversationId || !hasMoreMessages || messagesLoading) return;

      const oldest = messages[0];
      if (!oldest) return;

      set({ messagesLoading: true });
      try {
        const older = await fetchMessages(activeConversationId, 50, oldest.created_at);
        set((state) => {
          if (!sameConvoId(state.activeConversationId, activeConversationId)) {
            return state;
          }
          return {
            messages: [...older, ...state.messages],
            messagesLoading: false,
            hasMoreMessages: older.length >= 50,
          };
        });
      } catch (e) {
        console.error('[MessagesStore] loadMoreMessages failed:', e);
        set({ messagesLoading: false });
      }
    },

    sendMessage: async ({ content = '', messageType = 'text', mediaUrl, metadata }) => {
      const { activeConversationId } = get();
      const text = content.trim();
      const hasMetadata = metadata && Object.keys(metadata).length > 0;
      if (!activeConversationId || (!text && !mediaUrl && !hasMetadata)) return;

      const u = useAuthStore.getState().user;
      const tempId = `opt-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
      const optimistic: ApiMessage = {
        id: tempId,
        conversation_id: activeConversationId,
        sender_id: u?.uid ?? '',
        sender_name: u?.displayName ?? '',
        content: text,
        message_type: (messageType || 'text') as ApiMessage['message_type'],
        media_url: mediaUrl,
        metadata,
        created_at: new Date().toISOString(),
        local_status: 'sending',
      };

      set((s) => ({ messages: [...s.messages, optimistic] }));

      const pullServer = async () => {
        try {
          let fresh = await fetchMessages(activeConversationId, 50);
          if (fresh.length === 0) {
            await new Promise((r) => setTimeout(r, 700));
            fresh = await fetchMessages(activeConversationId, 50);
          }
          set((state) => {
            const hadOptimistic = state.messages.some((m) => m.id === tempId);
            if (fresh.length === 0 && hadOptimistic) {
              return state;
            }
            return {
              messages: fresh,
              hasMoreMessages: fresh.length >= 50,
            };
          });
          markAsRead(activeConversationId).catch(() => {});
        } catch (e) {
          console.error('[MessagesStore] pull messages after send failed:', e);
        }
      };

      try {
        if (chatWs.connected) {
          chatWs.subscribe([activeConversationId]);
        }
        await sendMessageHttp({
          conversation_id: activeConversationId,
          content: text,
          message_type: messageType,
          media_url: mediaUrl,
          metadata,
        });
        await pullServer();
      } catch (e) {
        console.error('[MessagesStore] sendMessage failed:', e);
        set((s) => ({
          messages: s.messages.map((m) =>
            m.id === tempId
              ? {
                  ...m,
                  local_status: isRetriableSendError(e) ? 'queued' : 'failed',
                  local_error:
                    e instanceof Error
                      ? e.message
                      : (e as any)?.response?.data?.error || '发送失败',
                }
              : m,
          ),
        }));
      }
    },

    retryMessage: async (messageId: string) => {
      const { activeConversationId, messages } = get();
      const failed = messages.find((m) => m.id === messageId);
      if (!activeConversationId || !failed || failed.local_status !== 'failed') return;

      set((state) => ({
        messages: state.messages.map((m) =>
          m.id === messageId
            ? {
                ...m,
                local_status: 'sending',
                local_error: undefined,
              }
            : m,
        ),
      }));

      const pullServer = async () => {
        try {
          const fresh = await fetchMessages(activeConversationId, 50);
          set((state) => {
            if (!sameConvoId(state.activeConversationId, activeConversationId)) return state;
            return {
              messages: fresh,
              hasMoreMessages: fresh.length >= 50,
            };
          });
          markAsRead(activeConversationId).catch(() => {});
        } catch (e) {
          console.error('[MessagesStore] retry pull failed:', e);
        }
      };

        try {
        await sendStoredMessage(failed);
        await pullServer();
      } catch (e) {
        console.error('[MessagesStore] retryMessage failed:', e);
        set((state) => ({
          messages: state.messages.map((m) =>
            m.id === messageId
              ? {
                  ...m,
                  local_status: isRetriableSendError(e) ? 'queued' : 'failed',
                  local_error:
                    e instanceof Error
                      ? e.message
                      : (e as any)?.response?.data?.error || '重试失败',
                }
              : m,
          ),
        }));
      }
    },

    markConversationRead: async (conversationId: string) => {
      try {
        await markAsRead(conversationId);
        set((state) => ({
          conversations: state.conversations.map((c) =>
            c.id === conversationId ? { ...c, unread_count: 0 } : c,
          ),
        }));
      } catch (e) {
        console.error('[MessagesStore] markAsRead failed:', e);
      }
    },

    setActiveConversation: (id: string | null) => {
      if (!id) {
        set({ activeConversationId: null, messages: [] });
        return;
      }
      const previousActiveId = get().activeConversationId;
      get().loadMessages(id, previousActiveId);
    },

    connectWs: async () => {
      if (!wsBound) {
        chatWs.onNewMessage(wsMessageHandler);
        wsBound = true;
      }
      chatWs.setConnectionStateHandler((status) => {
        const open = status === 'connected';
        set({ wsConnected: open, wsStatus: status });
        if (!open) return;

        // Re-sync key state after reconnect so we don't rely on missed WS frames.
        void get().loadConversations();
        void get().loadUnreadCount();
        void get().loadFriends();
        void get().loadFriendRequests();
        void get().flushQueuedMessages();
        const activeId = get().activeConversationId;
        if (activeId) {
          void get().refreshActiveMessages();
        }
      });
      const ok = await chatWs.connect();
      set({ wsConnected: ok, wsStatus: ok ? 'connected' : 'disconnected' });

      const { conversations } = get();
      const ids = conversations.map((c) => c.id).filter(Boolean);
      if (ok && ids.length > 0) {
        chatWs.subscribe(ids);
      }
    },

    disconnectWs: () => {
      chatWs.setConnectionStateHandler(null);
      if (wsBound) {
        chatWs.offNewMessage(wsMessageHandler);
        wsBound = false;
      }
      chatWs.disconnect();
      set({ wsConnected: false, wsStatus: 'disconnected' });
    },

    handleNewMessage: (message: ApiMessage) => {
      const { activeConversationId } = get();
      const selfId = useAuthStore.getState().user?.uid;
      const isActive = sameConvoId(message.conversation_id, activeConversationId);
      const hasConversation = get().conversations.some((c) =>
        sameConvoId(c.id, message.conversation_id),
      );
      const isOwnMessage = normId(message.sender_id) === normId(selfId);

      set((state) => {
        const dup = state.messages.some((m) => m.id === message.id);
        const newMessages =
          isActive && !dup ? [...state.messages, message] : state.messages;

        const newConversations = state.conversations.map((c) => {
          if (!sameConvoId(c.id, message.conversation_id)) return c;
          return {
            ...c,
            last_message: message.content,
            last_sender_name: message.sender_name,
            last_time: message.created_at,
            unread_count: isActive || isOwnMessage ? 0 : c.unread_count + 1,
          };
        });

        newConversations.sort((a, b) => {
          const ta = a.last_time ? new Date(a.last_time).getTime() : 0;
          const tb = b.last_time ? new Date(b.last_time).getTime() : 0;
          return tb - ta;
        });

        const newTotalUnread = isActive || isOwnMessage
          ? state.totalUnread
          : state.totalUnread + 1;

        return {
          messages: newMessages,
          conversations: newConversations,
          totalUnread: newTotalUnread,
        };
      });

      // Messages WS is connected globally, but the conversation list is only
      // loaded when the messages screen mounts. If the receiver hasn't opened
      // that tab yet, an incoming message can land before we know about the
      // conversation locally, which looks like "the other side didn't receive".
      if (!hasConversation) {
        void get().loadConversations();
        void get().loadUnreadCount();
      }

      if (isActive && activeConversationId) {
        markAsRead(activeConversationId).catch(() => {});
      }
    },

    loadFriends: async () => {
      try {
        const friends = await fetchFriends();
        console.log('[MessagesStore] loadFriends success:', friends.length);
        set({ friends, friendsError: null });
      } catch (e) {
        console.error('[MessagesStore] loadFriends failed:', e);
        set({ friendsError: e instanceof Error ? e.message : 'loadFriends failed' });
      }
    },

    loadFriendRequests: async () => {
      try {
        const [incoming, outgoing] = await Promise.all([
          fetchIncomingFriendRequests(),
          fetchOutgoingFriendRequests(),
        ]);
        set({ incomingFriendRequests: incoming, outgoingFriendRequests: outgoing });
      } catch (e) {
        console.error('[MessagesStore] loadFriendRequests failed:', e);
      }
    },

    loadUnreadCount: async () => {
      try {
        const totalUnread = await fetchUnreadCount();
        set({ totalUnread });
      } catch (e) {
        console.error('[MessagesStore] loadUnreadCount failed:', e);
      }
    },

    refreshActiveMessages: async () => {
      const aid = get().activeConversationId;
      if (!aid) return;
      try {
        const fresh = await fetchMessages(aid, 50);
        set((state) => {
          if (!sameConvoId(state.activeConversationId, aid)) return state;
          if (fresh.length === 0 && state.messages.length > 0) {
            return state;
          }
          const oldLast = state.messages[state.messages.length - 1]?.id;
          const newLast = fresh[fresh.length - 1]?.id;
          if (
            fresh.length > 0 &&
            oldLast === newLast &&
            state.messages.length === fresh.length
          ) {
            return state;
          }
          return {
            messages: fresh,
            hasMoreMessages: fresh.length >= 50,
          };
        });
      } catch (e) {
        console.error('[MessagesStore] refreshActiveMessages failed:', e);
      }
    },

    flushQueuedMessages: async () => {
      const { activeConversationId, messages } = get();
      const queued = messages.filter(
        (m) => sameConvoId(m.conversation_id, activeConversationId) && m.local_status === 'queued',
      );
      if (queued.length === 0) return;

      for (const queuedMessage of queued) {
        set((state) => ({
          messages: state.messages.map((m) =>
            m.id === queuedMessage.id
              ? { ...m, local_status: 'sending', local_error: undefined }
              : m,
          ),
        }));

        try {
          await sendStoredMessage(queuedMessage);
          const fresh = await fetchMessages(queuedMessage.conversation_id, 50);
          set((state) => {
            if (!sameConvoId(state.activeConversationId, queuedMessage.conversation_id)) return state;
            return {
              messages: fresh,
              hasMoreMessages: fresh.length >= 50,
            };
          });
          markAsRead(queuedMessage.conversation_id).catch(() => {});
        } catch (e) {
          set((state) => ({
            messages: state.messages.map((m) =>
              m.id === queuedMessage.id
                ? {
                    ...m,
                    local_status: isRetriableSendError(e) ? 'queued' : 'failed',
                    local_error:
                      e instanceof Error
                        ? e.message
                        : (e as any)?.response?.data?.error || '自动重发失败',
                  }
                : m,
            ),
          }));
        }
      }
    },
  };
});
