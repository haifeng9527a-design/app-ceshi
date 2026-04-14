import { create } from 'zustand';
import {
  listMyFeedbacks,
  markFeedbackRead,
  getFeedbackUnreadCount,
  type Feedback,
} from '../api/feedbackApi';

interface FeedbackState {
  items: Feedback[];
  total: number;
  unreadCount: number;
  loading: boolean;
  error: string | null;

  fetchList: () => Promise<void>;
  fetchUnreadCount: () => Promise<void>;
  markRead: (id: string) => Promise<void>;
  reset: () => void;
}

export const useFeedbackStore = create<FeedbackState>((set, get) => ({
  items: [],
  total: 0,
  unreadCount: 0,
  loading: false,
  error: null,

  async fetchList() {
    set({ loading: true, error: null });
    try {
      const { feedbacks, total } = await listMyFeedbacks(50, 0);
      const unread = feedbacks.filter((f) => f.user_unread).length;
      set({ items: feedbacks || [], total: total ?? 0, unreadCount: unread, loading: false });
    } catch (e: any) {
      console.error('[feedbackStore] fetchList failed:', e);
      set({ loading: false, error: e?.message || 'failed to load' });
    }
  },

  async fetchUnreadCount() {
    try {
      const n = await getFeedbackUnreadCount();
      set({ unreadCount: n });
    } catch (e) {
      // 静默失败：红点拿不到不影响主流程
      console.warn('[feedbackStore] fetchUnreadCount failed:', e);
    }
  },

  async markRead(id: string) {
    // 先本地乐观更新，再调用接口
    const state = get();
    const already = state.items.find((f) => f.id === id);
    if (!already?.user_unread) return;

    set({
      items: state.items.map((f) => (f.id === id ? { ...f, user_unread: false } : f)),
      unreadCount: Math.max(0, state.unreadCount - 1),
    });
    try {
      await markFeedbackRead(id);
    } catch (e) {
      console.warn('[feedbackStore] markRead failed (will retry on next fetch):', e);
    }
  },

  reset() {
    set({ items: [], total: 0, unreadCount: 0, loading: false, error: null });
  },
}));
