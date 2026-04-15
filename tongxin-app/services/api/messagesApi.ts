import messagesClient from './messagesClient';

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
  message_type: 'text' | 'image' | 'video' | 'audio' | 'system_join' | 'system_leave' | 'teacher_share' | 'red_packet';
  media_url?: string;
  /** Strategy cards / AI payloads (JSON object) */
  metadata?: Record<string, unknown>;
  duration_ms?: number;
  created_at: string;
  reply_to_message_id?: string;
  reply_to_sender_name?: string;
  reply_to_content?: string;
  local_status?: 'sending' | 'queued' | 'failed';
  local_error?: string;
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

export interface SupportAssignment {
  id: string;
  customer_uid: string;
  agent_uid: string;
  assigned_by?: string | null;
  status: 'active' | 'transferred' | 'closed';
  conversation_id: string;
  created_at: string;
  updated_at: string;
}

export interface SupportAssignmentDetail {
  assignment: SupportAssignment | null;
  agent_online?: boolean;
  agent: {
    uid: string;
    display_name: string;
    email: string;
    avatar_url?: string;
    role?: string;
    status?: string;
  } | null;
}

export type ChatRelationshipStatus =
  | 'self'
  | 'friend'
  | 'pending_outgoing'
  | 'pending_incoming'
  | 'not_friend'
  | 'support';

export interface ChatTraderSummary {
  is_trader: boolean;
  allow_copy_trading: boolean;
  win_rate: number;
  copiers_count: number;
  total_trades: number;
  total_pnl: number;
}

export interface ChatUserProfile {
  uid: string;
  display_name: string;
  avatar_url?: string;
  email?: string;
  short_id?: string;
  bio?: string;
  role?: string;
  status?: string;
  online: boolean;
  is_self: boolean;
  is_support_agent: boolean;
  relationship_status: ChatRelationshipStatus;
  relationship_request_id?: string;
  can_add_friend: boolean;
  can_accept_friend: boolean;
  trader_summary?: ChatTraderSummary | null;
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
  created_at?: string;
  created_by?: string;
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

export interface UpdateGroupInfoRequest {
  title?: string;
  avatar_url?: string;
}

/* ════════════════════════════════════════
   Conversations
   ════════════════════════════════════════ */

export async function fetchConversations(): Promise<ApiConversation[]> {
  const { data } = await messagesClient.get('/api/conversations');
  return data || [];
}

export async function fetchMySupportAssignment(): Promise<SupportAssignmentDetail> {
  const { data } = await messagesClient.get('/api/support/me');
  return data;
}

export async function ensureMySupportAssignment(): Promise<SupportAssignmentDetail> {
  const { data } = await messagesClient.post('/api/support/me/ensure');
  return data;
}

export async function fetchConversation(id: string): Promise<ApiConversation | null> {
  const { data } = await messagesClient.get(`/api/conversations/${id}`);
  return data || null;
}

export async function fetchChatUserProfile(uid: string): Promise<ChatUserProfile> {
  const { data } = await messagesClient.get(`/api/users/${encodeURIComponent(uid)}/chat-profile`);
  return data;
}

export async function fetchMessages(
  conversationId: string,
  limit = 50,
  before?: string,
): Promise<ApiMessage[]> {
  const params: Record<string, any> = { limit };
  if (before) params.before = before;
  const { data } = await messagesClient.get(`/api/conversations/${conversationId}/messages`, { params });
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
  const { data } = await messagesClient.get(`/api/conversations/${conversationId}/messages/search`, {
    params: { q, limit },
  });
  return data || [];
}

export async function markAsRead(conversationId: string): Promise<void> {
  await messagesClient.patch(`/api/conversations/${conversationId}/read`);
}

export async function fetchUnreadCount(): Promise<number> {
  const { data } = await messagesClient.get('/api/conversations/unread-count');
  return data?.count ?? 0;
}

export async function createDirectConversation(peerId: string): Promise<{ id: string; created: boolean }> {
  const { data } = await messagesClient.post('/api/conversations/direct', { peer_id: peerId });
  return data;
}

export async function createGroupConversation(
  title: string,
  memberUserIds: string[],
): Promise<{ id: string; title: string }> {
  const { data } = await messagesClient.post('/api/conversations/group', {
    title,
    member_ids: memberUserIds,
  });
  return data;
}

export async function fetchGroupInfo(conversationId: string): Promise<GroupInfo | null> {
  const { data } = await messagesClient.get(`/api/conversations/${conversationId}/group-info`);
  if (!data || typeof data !== 'object') return null;
  const conversation = (data as any).conversation ?? data;
  const membersRaw = Array.isArray((data as any).members) ? (data as any).members : [];
  return {
    conversation_id: String(conversation?.id ?? conversationId),
    title: String(conversation?.title ?? ''),
    announcement: conversation?.announcement ?? undefined,
    avatar_url: conversation?.avatar_url ?? undefined,
    created_at: conversation?.created_at ?? undefined,
    created_by: conversation?.created_by ?? undefined,
    member_count: membersRaw.length,
    my_role: String((membersRaw.find((m: any) => m?.is_me)?.role ?? '') || ''),
    members: membersRaw.map((m: any) => ({
      user_id: String(m?.user_id ?? ''),
      role: String(m?.role ?? ''),
      display_name: m?.display_name ?? undefined,
      avatar_url: m?.avatar_url ?? undefined,
      short_id: m?.short_id ?? undefined,
    })),
  };
}

export async function updateGroupInfo(
  conversationId: string,
  body: UpdateGroupInfoRequest,
): Promise<void> {
  await messagesClient.put(`/api/conversations/${conversationId}/group-info`, body);
}

export async function addGroupMembers(
  conversationId: string,
  memberIds: string[],
): Promise<void> {
  await messagesClient.post(`/api/conversations/${conversationId}/members`, {
    member_ids: memberIds,
  });
}

export async function removeGroupMember(
  conversationId: string,
  userId: string,
): Promise<void> {
  await messagesClient.delete(`/api/conversations/${conversationId}/members/${encodeURIComponent(userId)}`);
}

export async function updateGroupMemberRole(
  conversationId: string,
  userId: string,
  role: 'admin' | 'member',
): Promise<void> {
  await messagesClient.patch(`/api/conversations/${conversationId}/members/${encodeURIComponent(userId)}/role`, {
    role,
  });
}

export async function dissolveGroup(conversationId: string): Promise<void> {
  await messagesClient.delete(`/api/conversations/${conversationId}`);
}

/* ════════════════════════════════════════
   Messages
   ════════════════════════════════════════ */

export async function sendMessageHttp(body: {
  conversation_id: string;
  content: string;
  message_type?: string;
  media_url?: string;
  metadata?: Record<string, unknown>;
  reply_to_message_id?: string;
  reply_to_sender_name?: string;
  reply_to_content?: string;
}): Promise<{ id: string; created_at: string }> {
  const { data } = await messagesClient.post('/api/messages', body);
  return data;
}

export async function uploadMessageAsset(file: File): Promise<{ url: string; filename: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await messagesClient.post('/api/upload', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
  return data;
}

export async function deleteMessage(messageId: string): Promise<void> {
  await messagesClient.delete(`/api/messages/${messageId}`);
}

/* ════════════════════════════════════════
   User Profiles (batch)
   ════════════════════════════════════════ */

export async function fetchUserProfilesBatch(
  userIds: string[],
): Promise<Record<string, PeerProfile>> {
  if (userIds.length === 0) return {};
  const { data } = await messagesClient.get('/api/user-profiles/batch', {
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
  const { data } = await messagesClient.get('/api/friends');
  const list = Array.isArray(data) ? data : [];
  return list.map(mapFriendProfile);
}

export async function searchUsers(query: string): Promise<FriendProfile[]> {
  const { data } = await messagesClient.get('/api/friends/search', { params: { q: query } });
  const list = Array.isArray(data) ? data : [];
  return list.map(mapFriendProfile);
}

export async function sendFriendRequest(targetUserId: string): Promise<{ id?: string }> {
  const { data, status } = await messagesClient.post('/api/friends/requests', {
    target_user_id: targetUserId,
  });
  if (status !== 201 && status !== 200) {
    throw new Error(`unexpected status ${status}`);
  }
  return data ?? {};
}

export async function fetchIncomingFriendRequests(): Promise<ApiFriendRequest[]> {
  const { data } = await messagesClient.get('/api/friends/incoming');
  return Array.isArray(data) ? data : [];
}

export async function fetchOutgoingFriendRequests(): Promise<ApiFriendRequest[]> {
  const { data } = await messagesClient.get('/api/friends/outgoing');
  return Array.isArray(data) ? data : [];
}

export async function acceptFriendRequest(requestId: string): Promise<void> {
  await messagesClient.post('/api/friends/accept', { request_id: requestId });
}

export async function rejectFriendRequest(requestId: string): Promise<void> {
  await messagesClient.post('/api/friends/reject', { request_id: requestId });
}
