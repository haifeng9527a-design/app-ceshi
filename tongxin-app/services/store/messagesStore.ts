import { create } from 'zustand';
import {
  fetchConversations,
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
} from '../api/messagesApi';
import { chatWs } from '../websocket/chatWs';
import { useAuthStore } from './authStore';

/** 会话 id 可能来自不同路径，避免严格 === 导致新消息无法并入当前聊天 */
function sameConvoId(a: string | null | undefined, b: string | null | undefined): boolean {
  return String(a ?? '').trim() === String(b ?? '').trim();
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

  /** 待处理的好友申请（收到的） */
  incomingFriendRequests: ApiFriendRequest[];
  /** 已发出、待对方处理 */
  outgoingFriendRequests: ApiFriendRequest[];

  // Unread
  totalUnread: number;

  // WebSocket
  wsConnected: boolean;

  // Actions
  loadConversations: () => Promise<void>;
  loadMessages: (conversationId: string, previousActiveId?: string | null) => Promise<void>;
  loadMoreMessages: () => Promise<void>;
  sendMessage: (content: string, messageType?: string) => Promise<void>;
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
}

export const useMessagesStore = create<MessagesState>((set, get) => {
  // WS new message handler reference (for cleanup)
  const wsMessageHandler = (message: ApiMessage) => {
    get().handleNewMessage(message);
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
    incomingFriendRequests: [],
    outgoingFriendRequests: [],
    totalUnread: 0,
    wsConnected: false,

    loadConversations: async () => {
      set({ conversationsLoading: true });
      try {
        const conversations = await fetchConversations();
        set({ conversations, conversationsLoading: false });

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
        set((state) => ({
          messages: [...older, ...state.messages],
          messagesLoading: false,
          hasMoreMessages: older.length >= 50,
        }));
      } catch (e) {
        console.error('[MessagesStore] loadMoreMessages failed:', e);
        set({ messagesLoading: false });
      }
    },

    sendMessage: async (content: string, messageType = 'text') => {
      const { activeConversationId } = get();
      const text = content.trim();
      if (!activeConversationId || !text) return;

      const u = useAuthStore.getState().user;
      const tempId = `opt-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
      const optimistic: ApiMessage = {
        id: tempId,
        conversation_id: activeConversationId,
        sender_id: u?.uid ?? '',
        sender_name: u?.displayName ?? '',
        content: text,
        message_type: (messageType || 'text') as ApiMessage['message_type'],
        created_at: new Date().toISOString(),
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
          chatWs.sendMessage(activeConversationId, text, messageType);
          await new Promise((r) => setTimeout(r, 450));
          await pullServer();
          return;
        }

        await sendMessageHttp({
          conversation_id: activeConversationId,
          content: text,
          message_type: messageType,
        });
        await pullServer();
      } catch (e) {
        console.error('[MessagesStore] sendMessage failed:', e);
        set((s) => ({
          messages: s.messages.filter((m) => m.id !== tempId),
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
      chatWs.onNewMessage(wsMessageHandler);
      chatWs.setConnectionStateHandler((open) => set({ wsConnected: open }));
      const ok = await chatWs.connect();
      set({ wsConnected: ok });

      const { conversations } = get();
      const ids = conversations.map((c) => c.id).filter(Boolean);
      if (ok && ids.length > 0) {
        chatWs.subscribe(ids);
      }
    },

    disconnectWs: () => {
      chatWs.setConnectionStateHandler(null);
      chatWs.offNewMessage(wsMessageHandler);
      chatWs.disconnect();
      set({ wsConnected: false });
    },

    handleNewMessage: (message: ApiMessage) => {
      const { activeConversationId } = get();
      const isActive = sameConvoId(message.conversation_id, activeConversationId);
      const hasConversation = get().conversations.some((c) =>
        sameConvoId(c.id, message.conversation_id),
      );

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
            unread_count: isActive ? 0 : c.unread_count + 1,
          };
        });

        newConversations.sort((a, b) => {
          const ta = a.last_time ? new Date(a.last_time).getTime() : 0;
          const tb = b.last_time ? new Date(b.last_time).getTime() : 0;
          return tb - ta;
        });

        const newTotalUnread = isActive
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
        set({ friends });
      } catch (e) {
        console.error('[MessagesStore] loadFriends failed:', e);
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
  };
});
