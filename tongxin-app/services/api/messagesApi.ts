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
  /** Server: users.is_trader for direct peer (from Postgres) */
  peer_is_trader?: boolean;
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
  /** Strategy cards / AI payloads (JSON object) */
  metadata?: Record<string, unknown>;
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

/** Server: friend_requests row */
export interface ApiFriendRequest {
  id: string;
  from_user_id: string;
  to_user_id: string;
  status: string;
  message?: string;
  created_at: string;
}

function mapFriendProfile(raw: any): FriendProfile {
  const user_id = String(raw?.user_id ?? raw?.uid ?? raw?.id ?? '').trim();
  return {
    user_id,
    display_name: String(raw?.display_name ?? ''),
    email: String(raw?.email ?? ''),
    avatar_url: raw?.avatar_url,
    status: raw?.status,
    short_id: raw?.short_id,
    role: raw?.role,
    last_online_at: raw?.last_online_at,
  };
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
  if (Array.isArray(data)) return data;
  if (data && typeof data === 'object' && Array.isArray((data as { messages?: unknown }).messages)) {
    return (data as { messages: ApiMessage[] }).messages;
  }
  return [];
}

export async function searchConversationMessages(
  conversationId: string,
  q: string,
  limit = 40,
): Promise<ApiMessage[]> {
  const { data } = await apiClient.get(`/api/conversations/${conversationId}/messages/search`, {
    params: { q, limit },
  });
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
  const list = Array.isArray(data) ? data : [];
  const map: Record<string, PeerProfile> = {};
  for (const raw of list) {
    const id = String(raw?.user_id ?? raw?.uid ?? raw?.id ?? '').trim();
    if (!id) continue;
    map[id] = {
      display_name: raw.display_name ?? '',
      avatar_url: raw.avatar_url ?? null,
      email: raw.email ?? null,
      short_id: raw.short_id ?? null,
    };
  }
  return map;
}

/* ════════════════════════════════════════
   Friends
   ════════════════════════════════════════ */

export async function fetchFriends(): Promise<FriendProfile[]> {
  const { data } = await apiClient.get('/api/friends');
  const list = Array.isArray(data) ? data : [];
  return list.map(mapFriendProfile);
}

export async function searchUsers(query: string): Promise<FriendProfile[]> {
  const { data } = await apiClient.get('/api/friends/search', { params: { q: query } });
  const list = Array.isArray(data) ? data : [];
  return list.map(mapFriendProfile);
}

export async function sendFriendRequest(targetUserId: string): Promise<{ id?: string }> {
  const { data, status } = await apiClient.post('/api/friends/requests', {
    target_user_id: targetUserId,
  });
  if (status !== 201 && status !== 200) {
    throw new Error(`unexpected status ${status}`);
  }
  return data ?? {};
}

export async function fetchIncomingFriendRequests(): Promise<ApiFriendRequest[]> {
  const { data } = await apiClient.get('/api/friends/incoming');
  return Array.isArray(data) ? data : [];
}

export async function fetchOutgoingFriendRequests(): Promise<ApiFriendRequest[]> {
  const { data } = await apiClient.get('/api/friends/outgoing');
  return Array.isArray(data) ? data : [];
}

export async function acceptFriendRequest(requestId: string): Promise<void> {
  await apiClient.post('/api/friends/accept', { request_id: requestId });
}

export async function rejectFriendRequest(requestId: string): Promise<void> {
  await apiClient.post('/api/friends/reject', { request_id: requestId });
}
