import apiClient from './client';

/* ════════════════════════════════════════
   Types
   ════════════════════════════════════════ */

export interface ApiConversation {
  id: string;
  type: 'direct' | 'group';
  title?: string;
  avatar_url?: string;
  last_message?: string;
  last_sender_name?: string;
  last_time?: string;
  unread_count: number;
  peer_id?: string;
  announcement?: string;
  created_at?: string;
}

export interface ApiMessage {
  id: string;
  conversation_id: string;
  sender_id: string;
  sender_name: string;
  content: string;
  message_type: 'text' | 'image' | 'video' | 'audio' | 'system_join' | 'system_leave' | 'teacher_share';
  media_url?: string;
  duration_ms?: number;
  created_at: string;
  reply_to_message_id?: string;
  reply_to_sender_name?: string;
  reply_to_content?: string;
}

export interface PeerProfile {
  display_name: string;
  avatar_url: string | null;
  email: string | null;
  short_id: string | null;
}

export interface FriendProfile {
  user_id: string;
  display_name: string;
  email: string;
  avatar_url?: string;
  status?: string;
  short_id?: string;
  role?: string;
  last_online_at?: string;
}

export interface GroupInfo {
  conversation_id: string;
  title: string;
  announcement?: string;
  avatar_url?: string;
  member_count: number;
  my_role: string;
  members: {
    user_id: string;
    role: string;
    display_name?: string;
    avatar_url?: string;
    short_id?: string;
  }[];
}

/* ════════════════════════════════════════
   Conversations
   ════════════════════════════════════════ */

export async function fetchConversations(): Promise<ApiConversation[]> {
  const { data } = await apiClient.get('/api/conversations');
  return data || [];
}

export async function fetchConversation(id: string): Promise<ApiConversation | null> {
  const { data } = await apiClient.get(`/api/conversations/${id}`);
  return data || null;
}

export async function fetchMessages(
  conversationId: string,
  limit = 50,
  before?: string,
): Promise<ApiMessage[]> {
  const params: Record<string, any> = { limit };
  if (before) params.before = before;
  const { data } = await apiClient.get(`/api/conversations/${conversationId}/messages`, { params });
  return data || [];
}

export async function markAsRead(conversationId: string): Promise<void> {
  await apiClient.patch(`/api/conversations/${conversationId}/read`);
}

export async function fetchUnreadCount(): Promise<number> {
  const { data } = await apiClient.get('/api/conversations/unread-count');
  return data?.count ?? 0;
}

export async function createDirectConversation(peerId: string): Promise<{ id: string; created: boolean }> {
  const { data } = await apiClient.post('/api/conversations/direct', { peer_id: peerId });
  return data;
}

export async function createGroupConversation(
  title: string,
  memberUserIds: string[],
): Promise<{ id: string; title: string }> {
  const { data } = await apiClient.post('/api/conversations/group', {
    title,
    member_user_ids: memberUserIds,
  });
  return data;
}

export async function fetchGroupInfo(conversationId: string): Promise<GroupInfo | null> {
  const { data } = await apiClient.get(`/api/conversations/${conversationId}/group-info`);
  return data || null;
}

/* ════════════════════════════════════════
   Messages
   ════════════════════════════════════════ */

export async function sendMessageHttp(body: {
  conversation_id: string;
  content: string;
  message_type?: string;
  media_url?: string;
  reply_to_message_id?: string;
  reply_to_sender_name?: string;
  reply_to_content?: string;
}): Promise<{ id: string; created_at: string }> {
  const { data } = await apiClient.post('/api/messages', body);
  return data;
}

export async function deleteMessage(messageId: string): Promise<void> {
  await apiClient.delete(`/api/messages/${messageId}`);
}

/* ════════════════════════════════════════
   User Profiles (batch)
   ════════════════════════════════════════ */

export async function fetchUserProfilesBatch(
  userIds: string[],
): Promise<Record<string, PeerProfile>> {
  if (userIds.length === 0) return {};
  const { data } = await apiClient.get('/api/user-profiles/batch', {
    params: { ids: userIds.join(',') },
  });
  return data || {};
}

/* ════════════════════════════════════════
   Friends
   ════════════════════════════════════════ */

export async function fetchFriends(): Promise<FriendProfile[]> {
  const { data } = await apiClient.get('/api/friends');
  return data || [];
}

export async function searchUsers(query: string): Promise<FriendProfile[]> {
  const { data } = await apiClient.get('/api/friends/search', { params: { q: query } });
  return data || [];
}

export async function sendFriendRequest(targetUserId: string): Promise<void> {
  await apiClient.post('/api/friends/requests', { target_user_id: targetUserId });
}
