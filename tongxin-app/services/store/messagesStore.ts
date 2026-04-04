import { create } from 'zustand';
import {
  fetchConversations,
  fetchMessages,
  sendMessageHttp,
  markAsRead,
  fetchUnreadCount,
  fetchUserProfilesBatch,
  fetchFriends,
  type ApiConversation,
  type ApiMessage,
  type PeerProfile,
  type FriendProfile,
} from '../api/messagesApi';
import { chatWs } from '../websocket/chatWs';

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

  // Unread
  totalUnread: number;

  // WebSocket
  wsConnected: boolean;

  // Actions
  loadConversations: () => Promise<void>;
  loadMessages: (conversationId: string) => Promise<void>;
  loadMoreMessages: () => Promise<void>;
  sendMessage: (content: string, messageType?: string) => Promise<void>;
  markConversationRead: (conversationId: string) => Promise<void>;
  setActiveConversation: (id: string | null) => void;
  connectWs: () => Promise<void>;
  disconnectWs: () => void;
  handleNewMessage: (message: ApiMessage) => void;
  loadFriends: () => Promise<void>;
  loadUnreadCount: () => Promise<void>;
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
      } catch (e) {
        console.error('[MessagesStore] loadConversations failed:', e);
        set({ conversationsLoading: false });
      }
    },

    loadMessages: async (conversationId: string) => {
      set({
        activeConversationId: conversationId,
        messagesLoading: true,
        messages: [],
        hasMoreMessages: true,
      });
      try {
        const messages = await fetchMessages(conversationId, 50);
        set({ messages, messagesLoading: false, hasMoreMessages: messages.length >= 50 });
        // Mark as read
        markAsRead(conversationId).catch(() => {});
        // Update local unread count
        set((state) => ({
          conversations: state.conversations.map((c) =>
            c.id === conversationId ? { ...c, unread_count: 0 } : c,
          ),
          totalUnread: Math.max(
            0,
            state.totalUnread -
              (state.conversations.find((c) => c.id === conversationId)?.unread_count ?? 0),
          ),
        }));
      } catch (e) {
        console.error('[MessagesStore] loadMessages failed:', e);
        set({ messagesLoading: false });
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
      if (!activeConversationId || !content.trim()) return;

      // Prefer WS, fallback to HTTP
      if (chatWs.connected) {
        chatWs.sendMessage(activeConversationId, content, messageType);
      } else {
        try {
          await sendMessageHttp({
            conversation_id: activeConversationId,
            content,
            message_type: messageType,
          });
        } catch (e) {
          console.error('[MessagesStore] sendMessage HTTP failed:', e);
        }
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
      set({ activeConversationId: id });
      if (id) {
        get().loadMessages(id);
      }
    },

    connectWs: async () => {
      chatWs.onNewMessage(wsMessageHandler);
      await chatWs.connect();
      set({ wsConnected: chatWs.connected });

      // Subscribe to all conversation IDs
      const { conversations } = get();
      const ids = conversations.map((c) => c.id).filter(Boolean);
      if (ids.length > 0) {
        chatWs.subscribe(ids);
      }
    },

    disconnectWs: () => {
      chatWs.offNewMessage(wsMessageHandler);
      chatWs.disconnect();
      set({ wsConnected: false });
    },

    handleNewMessage: (message: ApiMessage) => {
      const { activeConversationId } = get();

      set((state) => {
        // If message belongs to active conversation, append it
        const isActive = message.conversation_id === activeConversationId;
        const newMessages = isActive
          ? [...state.messages, message]
          : state.messages;

        // Update conversation list
        const newConversations = state.conversations.map((c) => {
          if (c.id !== message.conversation_id) return c;
          return {
            ...c,
            last_message: message.content,
            last_sender_name: message.sender_name,
            last_time: message.created_at,
            unread_count: isActive ? 0 : c.unread_count + 1,
          };
        });

        // Sort conversations by last_time descending
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

      // Auto mark-read if active
      if (message.conversation_id === activeConversationId) {
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

    loadUnreadCount: async () => {
      try {
        const totalUnread = await fetchUnreadCount();
        set({ totalUnread });
      } catch (e) {
        console.error('[MessagesStore] loadUnreadCount failed:', e);
      }
    },
  };
});
