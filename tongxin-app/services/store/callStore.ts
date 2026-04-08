import { create } from 'zustand';
import { acceptCall, endCall, rejectCall, startCall, type CallRecord } from '../api/callsApi';
import type { CallWsPayload } from '../websocket/chatWs';
import { useAuthStore } from './authStore';

interface CallStoreState {
  currentCall: CallRecord | null;
  incomingCall: CallRecord | null;
  currentConversationId: string | null;
  currentConversationName: string | null;
  pending: boolean;
  startVoiceCall: (conversationId: string, conversationName: string) => Promise<void>;
  acceptIncomingCall: () => Promise<void>;
  rejectIncomingCall: () => Promise<void>;
  endCurrentCall: (reason?: string) => Promise<void>;
  handleCallEvent: (payload: CallWsPayload) => void;
  clearIncomingCall: () => void;
}

export const useCallStore = create<CallStoreState>((set, get) => ({
  currentCall: null,
  incomingCall: null,
  currentConversationId: null,
  currentConversationName: null,
  pending: false,

  startVoiceCall: async (conversationId, conversationName) => {
    set({ pending: true });
    try {
      const call = await startCall(conversationId, 'voice');
      set({
        currentCall: call,
        currentConversationId: conversationId,
        currentConversationName: conversationName,
        incomingCall: null,
        pending: false,
      });
    } catch (e) {
      set({ pending: false });
      throw e;
    }
  },

  acceptIncomingCall: async () => {
    const incoming = get().incomingCall;
    if (!incoming) return;
    set({ pending: true });
    try {
      const call = await acceptCall(incoming.id);
      set({
        currentCall: call,
        currentConversationId: call.conversation_id,
        incomingCall: null,
        pending: false,
      });
    } catch (e) {
      set({ pending: false });
      throw e;
    }
  },

  rejectIncomingCall: async () => {
    const incoming = get().incomingCall;
    if (!incoming) return;
    set({ pending: true });
    try {
      await rejectCall(incoming.id, 'declined');
      set({ incomingCall: null, pending: false });
    } catch (e) {
      set({ pending: false });
      throw e;
    }
  },

  endCurrentCall: async (reason = 'hangup') => {
    const call = get().currentCall;
    if (!call) return;
    set({ pending: true });
    try {
      await endCall(call.id, reason);
      set({
        currentCall: null,
        currentConversationId: null,
        currentConversationName: null,
        pending: false,
      });
    } catch (e) {
      set({ pending: false });
      throw e;
    }
  },

  handleCallEvent: (payload) => {
    const selfId = useAuthStore.getState().user?.uid;
    const actorId = payload.actor_id ?? '';
    const isSelfActor = !!selfId && actorId === selfId;

    switch (payload.type) {
      case 'call_invite':
        if (isSelfActor) {
          set({
            currentCall: payload.call,
            currentConversationId: payload.call.conversation_id,
          });
        } else {
          set({
            incomingCall: payload.call,
            currentConversationId: payload.call.conversation_id,
          });
        }
        break;
      case 'call_accepted':
        set({
          currentCall: payload.call,
          incomingCall: null,
          currentConversationId: payload.call.conversation_id,
        });
        break;
      case 'call_rejected':
      case 'call_ended':
        set((state) => ({
          currentCall: state.currentCall?.id === payload.call.id ? null : state.currentCall,
          incomingCall: state.incomingCall?.id === payload.call.id ? null : state.incomingCall,
          currentConversationId:
            state.currentCall?.id === payload.call.id || state.incomingCall?.id === payload.call.id
              ? null
              : state.currentConversationId,
          currentConversationName:
            state.currentCall?.id === payload.call.id ? null : state.currentConversationName,
        }));
        break;
      default:
        break;
    }
  },

  clearIncomingCall: () => set({ incomingCall: null }),
}));
