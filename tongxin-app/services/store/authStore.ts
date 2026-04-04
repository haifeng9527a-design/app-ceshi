import { create } from 'zustand';
import apiClient, { getStoredToken, saveToken, clearToken } from '../api/client';

export interface UserProfile {
  uid: string;
  email: string | null;
  displayName: string | null;
  photoURL: string | null;
  emailVerified: boolean;
  // From backend
  shortId?: string;
  role?: string;
  signature?: string;
}

interface AuthState {
  // State
  user: UserProfile | null;
  loading: boolean;
  initializing: boolean;
  error: string | null;

  // Actions
  initialize: () => () => void; // returns unsubscribe
  signInWithEmail: (email: string, password: string) => Promise<void>;
  registerWithEmail: (email: string, password: string, displayName: string) => Promise<void>;
  signInWithGoogle: () => Promise<void>;
  signInWithApple: () => Promise<void>;
  signOut: () => Promise<void>;
  resendVerification: () => Promise<void>;
  clearError: () => void;
  syncProfile: () => Promise<void>;
  getIdToken: () => Promise<string | null>;
}

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  loading: false,
  initializing: true,
  error: null,

  initialize: () => {
    // Check for existing JWT token on startup
    (async () => {
      try {
        const token = await getStoredToken();
        if (token) {
          // Validate token by fetching profile
          const { data } = await apiClient.get('/api/auth/profile');
          const profile = backendUserToProfile(data);
          set({ user: profile, initializing: false });
        } else {
          set({ user: null, initializing: false });
        }
      } catch {
        // Token expired or invalid
        await clearToken();
        set({ user: null, initializing: false });
      }
    })();

    // Return no-op unsubscribe (no Firebase listener to clean up)
    return () => {};
  },

  signInWithEmail: async (email, password) => {
    set({ loading: true, error: null });
    try {
      const { data } = await apiClient.post('/api/auth/login', { email, password });
      // data: { token, user }
      await saveToken(data.token);
      const profile = backendUserToProfile(data.user);
      set({ user: profile, loading: false });
    } catch (e: any) {
      const msg = e.response?.data?.error || e.message || 'Login failed';
      set({ loading: false, error: msg });
    }
  },

  registerWithEmail: async (email, password, displayName) => {
    set({ loading: true, error: null });
    try {
      const { data } = await apiClient.post('/api/auth/register', {
        email,
        password,
        display_name: displayName,
      });
      // data: { token, user }
      await saveToken(data.token);
      const profile = backendUserToProfile(data.user);
      set({ user: profile, loading: false });
    } catch (e: any) {
      const msg = e.response?.data?.error || e.message || 'Registration failed';
      set({ loading: false, error: msg });
    }
  },

  signInWithGoogle: async () => {
    set({ loading: false, error: 'Google sign-in not yet available' });
  },

  signInWithApple: async () => {
    set({ loading: false, error: 'Apple sign-in not yet available' });
  },

  signOut: async () => {
    set({ loading: true, error: null });
    try {
      await clearToken();
      set({ user: null, loading: false });
    } catch (e: any) {
      set({ loading: false, error: e.message });
    }
  },

  resendVerification: async () => {
    // Not applicable for JWT auth
  },

  clearError: () => set({ error: null }),

  syncProfile: async () => {
    try {
      const { data } = await apiClient.get('/api/auth/profile');
      const profile = backendUserToProfile(data);
      set({ user: profile });
    } catch (e) {
      console.warn('[Auth] profile sync failed:', e);
    }
  },

  getIdToken: async () => {
    return await getStoredToken();
  },
}));

/** Convert backend user object to UserProfile */
function backendUserToProfile(user: any): UserProfile {
  return {
    uid: user.uid || user.id,
    email: user.email || null,
    displayName: user.display_name || user.displayName || null,
    photoURL: user.avatar_url || user.photoURL || null,
    emailVerified: true,
    shortId: user.short_id,
    role: user.role,
    signature: user.bio || user.signature,
  };
}
