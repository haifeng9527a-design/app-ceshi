import { useState, useRef, useEffect, useMemo, useCallback } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  useWindowDimensions,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Modal,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import { useMessagesStore } from '../../services/store/messagesStore';
import {
  createGroupConversation,
  type ApiConversation,
  type ApiMessage,
  type PeerProfile,
  type FriendProfile,
} from '../../services/api/messagesApi';

/* ════════════════════════════════════════
   UI-layer types (unchanged from design)
   ════════════════════════════════════════ */

interface Conversation {
  id: string;
  name: string;
  lastMessage: string;
  time: string;
  unread: number;
  online?: boolean;
  pinned?: boolean;
  verified?: boolean;
  badge?: string;
  isGroup?: boolean;
  members?: number;
  isSupport?: boolean;
}

interface ChatMessage {
  id: string;
  senderId: string;
  senderName: string;
  text: string;
  time: string;
  date?: string;
}

/* ════════════════════════════════════════
   Data mapping helpers
   ════════════════════════════════════════ */

function formatRelativeTime(isoString?: string): string {
  if (!isoString) return '';
  const diff = Date.now() - new Date(isoString).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  const days = Math.floor(hrs / 24);
  return `${days}d`;
}

function formatMessageTime(isoString: string): string {
  const d = new Date(isoString);
  const h = d.getHours();
  const m = d.getMinutes().toString().padStart(2, '0');
  const ampm = h >= 12 ? 'PM' : 'AM';
  const h12 = h % 12 || 12;
  return `${h12}:${m} ${ampm}`;
}

function formatDateLabel(isoString: string): string {
  const d = new Date(isoString);
  const now = new Date();
  const isToday =
    d.getDate() === now.getDate() &&
    d.getMonth() === now.getMonth() &&
    d.getFullYear() === now.getFullYear();
  if (isToday) return 'Today';
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    d.getDate() === yesterday.getDate() &&
    d.getMonth() === yesterday.getMonth() &&
    d.getFullYear() === yesterday.getFullYear();
  if (isYesterday) return 'Yesterday';
  return d.toLocaleDateString();
}

function mapConversation(
  c: ApiConversation,
  peerProfiles: Record<string, PeerProfile>,
): Conversation {
  const isGroup = c.type === 'group';
  const peer = c.peer_id ? peerProfiles[c.peer_id] : undefined;
  const name = isGroup ? (c.title || 'Group') : (peer?.display_name || 'User');

  return {
    id: c.id,
    name,
    lastMessage: c.last_message || '',
    time: formatRelativeTime(c.last_time),
    unread: c.unread_count || 0,
    isGroup,
  };
}

function mapMessages(
  apiMessages: ApiMessage[],
  currentUserId: string,
): ChatMessage[] {
  const result: ChatMessage[] = [];
  let lastDate = '';

  for (const msg of apiMessages) {
    // System messages
    if (msg.message_type === 'system_join' || msg.message_type === 'system_leave') {
      result.push({
        id: msg.id,
        senderId: 'system',
        senderName: '',
        text: msg.content,
        time: '',
        date: msg.content,
      });
      continue;
    }

    // Date dividers
    const msgDate = formatDateLabel(msg.created_at);
    if (msgDate !== lastDate) {
      lastDate = msgDate;
      result.push({
        id: `date-${msg.id}`,
        senderId: 'system',
        senderName: '',
        text: '',
        time: '',
        date: msgDate,
      });
    }

    result.push({
      id: msg.id,
      senderId: msg.sender_id === currentUserId ? 'me' : msg.sender_id,
      senderName: msg.sender_name,
      text: msg.content,
      time: formatMessageTime(msg.created_at),
    });
  }

  return result;
}

/* ════════════════════════════════════════
   Filter tabs
   ════════════════════════════════════════ */

type ConvoFilter = 'all' | 'traders' | 'groups';

const FILTERS: { key: ConvoFilter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'traders', label: 'Traders' },
  { key: 'groups', label: 'Groups' },
];

/* ════════════════════════════════════════
   Helper: Avatar
   ════════════════════════════════════════ */

function AvatarCircle({
  name,
  size = 40,
  online,
  badge,
}: {
  name: string;
  size?: number;
  online?: boolean;
  badge?: string;
}) {
  const letter = (name || '?').charAt(0).toUpperCase();
  const hue = name.split('').reduce((a, c) => a + c.charCodeAt(0), 0) % 360;
  const bg = `hsl(${hue}, 40%, 25%)`;
  const fg = `hsl(${hue}, 60%, 75%)`;

  return (
    <View style={{ position: 'relative' }}>
      <View
        style={[
          styles.avatar,
          {
            width: size,
            height: size,
            borderRadius: size / 2,
            backgroundColor: bg,
          },
        ]}
      >
        <Text style={[styles.avatarText, { color: fg, fontSize: size * 0.4 }]}>
          {letter}
        </Text>
      </View>
      {online && (
        <View
          style={[
            styles.onlineDot,
            {
              width: size * 0.3,
              height: size * 0.3,
              borderRadius: size * 0.15,
              bottom: 0,
              right: 0,
            },
          ]}
        />
      )}
      {badge && (
        <View style={styles.badgeTag}>
          <Text style={styles.badgeTagText}>{badge}</Text>
        </View>
      )}
    </View>
  );
}

/* ════════════════════════════════════════
   Sub-component: Create Group Modal
   ════════════════════════════════════════ */

function CreateGroupModal({
  visible,
  onClose,
  onGroupCreated,
  friends,
}: {
  visible: boolean;
  onClose: () => void;
  onGroupCreated: (conversationId: string) => void;
  friends: FriendProfile[];
}) {
  const [groupName, setGroupName] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [creating, setCreating] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  const filteredFriends = useMemo(() => {
    if (!searchQuery.trim()) return friends;
    const q = searchQuery.toLowerCase();
    return friends.filter(
      (f) =>
        f.display_name.toLowerCase().includes(q) ||
        f.email?.toLowerCase().includes(q),
    );
  }, [friends, searchQuery]);

  const toggleSelect = (userId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const handleCreate = useCallback(async () => {
    if (selectedIds.size < 1 || !groupName.trim()) return;
    setCreating(true);
    try {
      const result = await createGroupConversation(groupName.trim(), Array.from(selectedIds));
      onGroupCreated(result.id);
      onClose();
      setGroupName('');
      setSelectedIds(new Set());
    } catch (e) {
      console.error('[CreateGroup] Failed:', e);
    } finally {
      setCreating(false);
    }
  }, [selectedIds, groupName, onGroupCreated, onClose]);

  if (!visible) return null;

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <View style={modalStyles.overlay}>
        <View style={modalStyles.container}>
          {/* Header */}
          <View style={modalStyles.header}>
            <Text style={modalStyles.title}>创建群聊</Text>
            <TouchableOpacity onPress={onClose} activeOpacity={0.7}>
              <Text style={modalStyles.closeBtn}>✕</Text>
            </TouchableOpacity>
          </View>

          {/* Group Name */}
          <View style={modalStyles.fieldGroup}>
            <Text style={modalStyles.fieldLabel}>群名称</Text>
            <TextInput
              style={modalStyles.fieldInput}
              placeholder="输入群聊名称"
              placeholderTextColor={Colors.textMuted}
              value={groupName}
              onChangeText={setGroupName}
            />
          </View>

          {/* Search friends */}
          <View style={[modalStyles.searchBox, { marginHorizontal: 20, marginBottom: 8 }]}>
            <Text style={{ fontSize: 14, marginRight: 8 }}>🔍</Text>
            <TextInput
              style={modalStyles.searchInput}
              placeholder="搜索好友..."
              placeholderTextColor={Colors.textMuted}
              value={searchQuery}
              onChangeText={setSearchQuery}
              autoCapitalize="none"
            />
          </View>

          {/* Selected count */}
          <Text style={[modalStyles.sectionLabel, { marginTop: 4 }]}>
            选择成员 ({selectedIds.size} 已选)
          </Text>

          {/* Friends list with checkboxes */}
          <ScrollView style={modalStyles.list} showsVerticalScrollIndicator={false}>
            {filteredFriends.map((f) => {
              const selected = selectedIds.has(f.user_id);
              return (
                <TouchableOpacity
                  key={f.user_id}
                  style={modalStyles.userRow}
                  activeOpacity={0.7}
                  onPress={() => toggleSelect(f.user_id)}
                >
                  <View
                    style={[
                      modalStyles.checkbox,
                      selected && modalStyles.checkboxSelected,
                    ]}
                  >
                    {selected && <Text style={modalStyles.checkmark}>✓</Text>}
                  </View>
                  <AvatarCircle name={f.display_name} size={40} />
                  <View style={{ flex: 1, gap: 2 }}>
                    <Text style={modalStyles.userName}>{f.display_name}</Text>
                    <Text style={modalStyles.userSub}>
                      {f.short_id ? `ID: ${f.short_id}` : f.email || ''}
                    </Text>
                  </View>
                </TouchableOpacity>
              );
            })}

            {filteredFriends.length === 0 && (
              <View style={{ padding: 40, alignItems: 'center' }}>
                <Text style={{ color: Colors.textMuted, fontSize: 14 }}>暂无好友</Text>
              </View>
            )}
          </ScrollView>

          {/* Create Button */}
          <View style={modalStyles.footer}>
            <TouchableOpacity
              style={[
                modalStyles.createBtn,
                (selectedIds.size < 1 || !groupName.trim()) && modalStyles.createBtnDisabled,
              ]}
              onPress={handleCreate}
              disabled={creating || selectedIds.size < 1 || !groupName.trim()}
              activeOpacity={0.8}
            >
              {creating ? (
                <ActivityIndicator size="small" color={Colors.background} />
              ) : (
                <Text style={modalStyles.createBtnText}>
                  创建群聊 ({selectedIds.size})
                </Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

/* ════════════════════════════════════════
   Sub-component: Conversation List
   ════════════════════════════════════════ */

function ConversationList({
  conversations,
  activeId,
  onSelect,
  filter,
  onFilterChange,
  loading,
  onAddFriend,
  onCreateGroup,
}: {
  conversations: Conversation[];
  activeId: string;
  onSelect: (c: Conversation) => void;
  filter: ConvoFilter;
  onFilterChange: (f: ConvoFilter) => void;
  loading?: boolean;
  onAddFriend: () => void;
  onCreateGroup: () => void;
}) {
  const { t } = useTranslation();

  const filtered = conversations.filter((c) => {
    if (filter === 'traders') return !c.isGroup && !c.isSupport;
    if (filter === 'groups') return c.isGroup;
    return true;
  });

  return (
    <View style={styles.listPanel}>
      {/* Header */}
      <View style={styles.listHeader}>
        <Text style={styles.listTitle}>{t('messages.title')}</Text>
        <View style={styles.headerActions}>
          <TouchableOpacity style={styles.headerActionBtn} activeOpacity={0.7} onPress={onAddFriend}>
            <Text style={styles.headerActionIcon}>👤+</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.headerActionBtn} activeOpacity={0.7} onPress={onCreateGroup}>
            <Text style={styles.headerActionIcon}>👥+</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.headerActionBtn} activeOpacity={0.7}>
            <Text style={styles.headerActionIcon}>🔔</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Search */}
      <View style={styles.searchBox}>
        <Text style={styles.searchIcon}>🔍</Text>
        <TextInput
          style={styles.searchInput}
          placeholder={t('common.search')}
          placeholderTextColor={Colors.textMuted}
        />
      </View>

      {/* Filter Tabs */}
      <View style={styles.filterRow}>
        {FILTERS.map((f) => (
          <TouchableOpacity
            key={f.key}
            style={[styles.filterTab, filter === f.key && styles.filterTabActive]}
            activeOpacity={0.7}
            onPress={() => onFilterChange(f.key)}
          >
            <Text
              style={[
                styles.filterTabText,
                filter === f.key && styles.filterTabTextActive,
              ]}
            >
              {f.label}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* Conversations */}
      <ScrollView style={styles.convoScroll} showsVerticalScrollIndicator={false}>
        {loading && (
          <View style={{ padding: 20, alignItems: 'center' }}>
            <ActivityIndicator color={Colors.primary} />
          </View>
        )}
        {!loading && filtered.length === 0 && (
          <View style={{ padding: 40, alignItems: 'center' }}>
            <Text style={{ color: Colors.textMuted, fontSize: 14 }}>
              {t('messages.noConversations')}
            </Text>
          </View>
        )}
        {filtered.map((c) => (
          <ConvoRow
            key={c.id}
            convo={c}
            active={c.id === activeId}
            onPress={() => onSelect(c)}
          />
        ))}
      </ScrollView>
    </View>
  );
}

/* Single conversation row */
function ConvoRow({
  convo,
  active,
  onPress,
}: {
  convo: Conversation;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity
      style={[
        styles.convoRow,
        active && styles.convoRowActive,
        convo.pinned && styles.convoRowPinned,
      ]}
      activeOpacity={0.7}
      onPress={onPress}
    >
      {convo.pinned && <View style={styles.pinnedBorder} />}
      <AvatarCircle name={convo.name} size={44} online={convo.online} />
      <View style={styles.convoInfo}>
        <View style={styles.convoNameRow}>
          <Text style={styles.convoName} numberOfLines={1}>
            {convo.isGroup ? '👥 ' : ''}{convo.name}
          </Text>
          {convo.verified && <Text style={styles.verifiedIcon}>✓</Text>}
          {convo.badge && (
            <View style={styles.convoTagBadge}>
              <Text style={styles.convoTagBadgeText}>{convo.badge}</Text>
            </View>
          )}
        </View>
        <Text style={styles.convoLastMsg} numberOfLines={1}>
          {convo.lastMessage}
        </Text>
        {convo.isGroup && convo.members != null && (
          <Text style={styles.memberCount}>{convo.members} members</Text>
        )}
      </View>
      <View style={styles.convoMeta}>
        <Text style={styles.convoTime}>{convo.time}</Text>
        {convo.unread > 0 && (
          <View style={styles.unreadBadge}>
            <Text style={styles.unreadText}>{convo.unread}</Text>
          </View>
        )}
      </View>
    </TouchableOpacity>
  );
}

/* ════════════════════════════════════════
   Sub-component: Chat Detail Panel
   ════════════════════════════════════════ */

function ChatPanel({
  conversation,
  messages,
  onBack,
  showBack,
  onSend,
  loading,
  onLoadMore,
  hasMore,
}: {
  conversation: Conversation;
  messages: ChatMessage[];
  onBack?: () => void;
  showBack?: boolean;
  onSend: (text: string) => void;
  loading?: boolean;
  onLoadMore?: () => void;
  hasMore?: boolean;
}) {
  const { t } = useTranslation();
  const [inputText, setInputText] = useState('');
  const scrollRef = useRef<ScrollView>(null);

  useEffect(() => {
    setTimeout(() => scrollRef.current?.scrollToEnd({ animated: false }), 100);
  }, [messages.length]);

  const handleSend = () => {
    const text = inputText.trim();
    if (!text) return;
    onSend(text);
    setInputText('');
  };

  const handleScroll = useCallback(
    (e: any) => {
      // Load more when scrolled near top
      if (hasMore && onLoadMore && e.nativeEvent.contentOffset.y < 50) {
        onLoadMore();
      }
    },
    [hasMore, onLoadMore],
  );

  return (
    <KeyboardAvoidingView
      style={styles.chatPanel}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={90}
    >
      {/* Chat Header */}
      <View style={styles.chatHeader}>
        {showBack && (
          <TouchableOpacity onPress={onBack} style={styles.backBtn} activeOpacity={0.7}>
            <Text style={styles.backArrow}>←</Text>
          </TouchableOpacity>
        )}
        <AvatarCircle name={conversation.name} size={36} online={conversation.online} />
        <View style={styles.chatHeaderInfo}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
            <Text style={styles.chatHeaderName}>{conversation.name}</Text>
            {conversation.verified && <Text style={styles.verifiedIcon}>✓</Text>}
          </View>
          <Text style={styles.chatHeaderStatus}>
            {conversation.online ? t('messages.online') : t('messages.offline')}
          </Text>
        </View>
        <View style={{ flex: 1 }} />
        <TouchableOpacity style={styles.chatActionBtn} activeOpacity={0.7}>
          <Text style={styles.chatActionBtnText}>🔍 {t('messages.searchMessages')}</Text>
        </TouchableOpacity>
      </View>

      {/* Messages */}
      <ScrollView
        ref={scrollRef}
        style={styles.messagesScroll}
        contentContainerStyle={styles.messagesContent}
        showsVerticalScrollIndicator={false}
        onScroll={handleScroll}
        scrollEventThrottle={200}
      >
        {loading && (
          <View style={{ padding: 12, alignItems: 'center' }}>
            <ActivityIndicator color={Colors.primary} size="small" />
          </View>
        )}
        {messages.map((msg) => {
          if (msg.date) {
            return (
              <View key={msg.id} style={styles.dateDivider}>
                <View style={styles.dateLine} />
                <Text style={styles.dateText}>{msg.date}</Text>
                <View style={styles.dateLine} />
              </View>
            );
          }

          const isMe = msg.senderId === 'me';

          return (
            <View
              key={msg.id}
              style={[
                styles.messageBubbleWrap,
                isMe ? styles.bubbleRight : styles.bubbleLeft,
              ]}
            >
              {!isMe && (
                <AvatarCircle name={msg.senderName || conversation.name} size={28} />
              )}
              <View
                style={[
                  styles.messageBubble,
                  isMe ? styles.bubbleMe : styles.bubbleOther,
                ]}
              >
                {!isMe && conversation.isGroup && (
                  <Text style={styles.senderLabel}>{msg.senderName}</Text>
                )}
                <Text
                  style={[
                    styles.messageText,
                    isMe ? styles.messageTextMe : styles.messageTextOther,
                  ]}
                >
                  {msg.text}
                </Text>
                <Text style={styles.messageTime}>{msg.time}</Text>
              </View>
            </View>
          );
        })}
      </ScrollView>

      {/* Input Bar */}
      <View style={styles.inputBar}>
        <TouchableOpacity style={styles.inputIconBtn} activeOpacity={0.7}>
          <Text style={styles.inputIconText}>＋</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.inputIconBtn} activeOpacity={0.7}>
          <Text style={styles.inputIconText}>😊</Text>
        </TouchableOpacity>
        <TextInput
          style={styles.chatInput}
          placeholder={t('messages.inputPlaceholder')}
          placeholderTextColor={Colors.textMuted}
          value={inputText}
          onChangeText={setInputText}
          multiline
          onSubmitEditing={handleSend}
        />
        <TouchableOpacity style={styles.inputIconBtn} activeOpacity={0.7}>
          <Text style={styles.inputIconText}>🎤</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.sendBtn, !inputText.trim() && styles.sendBtnDisabled]}
          activeOpacity={0.7}
          onPress={handleSend}
        >
          <Text style={styles.sendBtnText}>➤</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

/* ════════════════════════════════════════
   Sub-component: Peer Info Sidebar
   ════════════════════════════════════════ */

function PeerSidebar({ profile }: { profile: PeerProfile }) {
  return (
    <View style={styles.traderPanel}>
      <ScrollView showsVerticalScrollIndicator={false}>
        <View style={styles.traderHeader}>
          <AvatarCircle name={profile.display_name} size={72} />
          <Text style={styles.traderName}>{profile.display_name}</Text>
          {profile.short_id && (
            <Text style={styles.traderHandle}>ID: {profile.short_id}</Text>
          )}
          {profile.email && (
            <Text style={styles.traderHandle}>{profile.email}</Text>
          )}
        </View>
        <TouchableOpacity style={styles.viewProfileBtn} activeOpacity={0.8}>
          <Text style={styles.viewProfileText}>View Profile</Text>
        </TouchableOpacity>
      </ScrollView>
    </View>
  );
}

/* ════════════════════════════════════════
   Main Screen
   ════════════════════════════════════════ */

export default function MessagesScreen() {
  const { width } = useWindowDimensions();
  const isDesktop = width >= 1024;
  const isXL = width >= 1280;
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();

  const {
    conversations: apiConversations,
    conversationsLoading,
    activeConversationId,
    messages: apiMessages,
    messagesLoading,
    hasMoreMessages,
    peerProfiles,
    friends,
    wsConnected,
    loadConversations,
    setActiveConversation,
    sendMessage,
    loadMoreMessages,
    connectWs,
    disconnectWs,
    loadFriends,
  } = useMessagesStore();

  const [filter, setFilter] = useState<ConvoFilter>('all');
  const [mobileShowChat, setMobileShowChat] = useState(false);
  const [showCreateGroup, setShowCreateGroup] = useState(false);

  // Initialize on mount
  useEffect(() => {
    if (!user) return;
    loadConversations();
    loadFriends();
    connectWs();
    return () => {
      disconnectWs();
    };
  }, [user?.uid]);

  // Map API conversations to UI conversations
  const uiConversations = useMemo(
    () => apiConversations.map((c) => mapConversation(c, peerProfiles)),
    [apiConversations, peerProfiles],
  );

  // Map API messages to UI messages
  const uiMessages = useMemo(
    () => (user ? mapMessages(apiMessages, user.uid) : []),
    [apiMessages, user?.uid],
  );

  // Active conversation UI object
  const activeConvo = useMemo(
    () => uiConversations.find((c) => c.id === activeConversationId) ?? null,
    [uiConversations, activeConversationId],
  );

  // Active conversation's peer profile (for sidebar)
  const activePeerProfile = useMemo(() => {
    const apiConvo = apiConversations.find((c) => c.id === activeConversationId);
    if (!apiConvo?.peer_id) return null;
    return peerProfiles[apiConvo.peer_id] ?? null;
  }, [apiConversations, activeConversationId, peerProfiles]);

  const handleSelectConversation = (c: Conversation) => {
    setActiveConversation(c.id);
    if (!isDesktop) setMobileShowChat(true);
  };

  const handleBack = () => {
    setMobileShowChat(false);
    setActiveConversation(null);
  };

  const handleSend = (text: string) => {
    sendMessage(text);
  };

  const handleNewConversation = (conversationId: string) => {
    loadConversations();
    setActiveConversation(conversationId);
    if (!isDesktop) setMobileShowChat(true);
  };

  // Not logged in
  if (!user) {
    return (
      <View style={styles.emptyChat}>
        <Text style={styles.emptyChatIcon}>🔐</Text>
        <Text style={styles.emptyChatTitle}>{t('messages.loginRequired')}</Text>
        <TouchableOpacity
          style={styles.loginBtn}
          activeOpacity={0.8}
          onPress={() => router.push('/(auth)/login' as any)}
        >
          <Text style={styles.loginBtnText}>{t('messages.loginButton')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const showList = isDesktop || !mobileShowChat;
  const showChat = isDesktop || mobileShowChat;

  return (
    <View style={styles.container}>
      {/* Conversation List */}
      {showList && (
        <ConversationList
          conversations={uiConversations}
          activeId={activeConversationId ?? ''}
          onSelect={handleSelectConversation}
          filter={filter}
          onFilterChange={setFilter}
          loading={conversationsLoading}
          onAddFriend={() => router.push('/add-friend' as any)}
          onCreateGroup={() => { loadFriends(); setShowCreateGroup(true); }}
        />
      )}

      {/* Create Group Modal */}
      <CreateGroupModal
        visible={showCreateGroup}
        onClose={() => setShowCreateGroup(false)}
        onGroupCreated={handleNewConversation}
        friends={friends}
      />

      {/* Chat Panel */}
      {showChat && activeConvo && (
        <ChatPanel
          conversation={activeConvo}
          messages={uiMessages}
          onBack={handleBack}
          showBack={!isDesktop}
          onSend={handleSend}
          loading={messagesLoading}
          onLoadMore={loadMoreMessages}
          hasMore={hasMoreMessages}
        />
      )}

      {/* Empty state (desktop, no selection) */}
      {showChat && !activeConvo && isDesktop && (
        <View style={styles.emptyChat}>
          <Text style={styles.emptyChatIcon}>💬</Text>
          <Text style={styles.emptyChatTitle}>{t('messages.selectConversation')}</Text>
          <Text style={styles.emptyChatSub}>{t('messages.selectConversationHint')}</Text>
        </View>
      )}

      {/* Peer Sidebar (XL desktop, direct conversations) */}
      {isXL && activePeerProfile && (
        <PeerSidebar profile={activePeerProfile} />
      )}
    </View>
  );
}

/* ════════════════════════════════════════
   Styles
   ════════════════════════════════════════ */

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'row',
    backgroundColor: Colors.background,
  },

  /* ── Conversation List Panel ── */
  listPanel: {
    width: 360,
    maxWidth: '100%',
    borderRightWidth: 1,
    borderRightColor: Colors.border,
    backgroundColor: Colors.surface,
  },
  listHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 12,
  },
  listTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '700',
  },
  headerActions: {
    flexDirection: 'row',
    gap: 4,
  },
  headerActionBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerActionIcon: {
    fontSize: 18,
    color: Colors.textSecondary,
  },
  searchBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surfaceAlt,
    borderRadius: Sizes.borderRadiusSm,
    marginHorizontal: 16,
    paddingHorizontal: 12,
    paddingVertical: 8,
    marginBottom: 12,
  },
  searchIcon: {
    fontSize: 14,
    marginRight: 8,
  },
  searchInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 14,
    padding: 0,
  },
  filterRow: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    gap: 8,
    marginBottom: 12,
  },
  filterTab: {
    paddingVertical: 6,
    paddingHorizontal: 16,
    borderRadius: 20,
    backgroundColor: Colors.surfaceAlt,
  },
  filterTabActive: {
    backgroundColor: Colors.primaryDim,
  },
  filterTabText: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '500',
  },
  filterTabTextActive: {
    color: Colors.primary,
  },
  sectionLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 6,
  },
  convoScroll: {
    flex: 1,
  },

  /* ── Conversation Row ── */
  convoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    gap: 12,
    position: 'relative',
  },
  convoRowActive: {
    backgroundColor: Colors.surfaceAlt,
  },
  convoRowPinned: {
    borderLeftWidth: 3,
    borderLeftColor: Colors.primary,
  },
  pinnedBorder: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: 3,
    backgroundColor: Colors.primary,
  },
  convoInfo: {
    flex: 1,
    gap: 2,
  },
  convoNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  convoName: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '600',
    flexShrink: 1,
  },
  verifiedIcon: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  convoTagBadge: {
    backgroundColor: Colors.primaryDim,
    borderRadius: 4,
    paddingHorizontal: 6,
    paddingVertical: 1,
  },
  convoTagBadgeText: {
    color: Colors.primary,
    fontSize: 10,
    fontWeight: '700',
  },
  convoLastMsg: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  memberCount: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  convoMeta: {
    alignItems: 'flex-end',
    gap: 6,
  },
  convoTime: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  unreadBadge: {
    backgroundColor: Colors.primary,
    borderRadius: 10,
    minWidth: 20,
    height: 20,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 6,
  },
  unreadText: {
    color: Colors.textOnPrimary,
    fontSize: 11,
    fontWeight: '700',
  },

  /* ── Avatar ── */
  avatar: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    fontWeight: '700',
  },
  onlineDot: {
    position: 'absolute',
    backgroundColor: Colors.online,
    borderWidth: 2,
    borderColor: Colors.surface,
  },
  badgeTag: {
    position: 'absolute',
    top: -4,
    right: -8,
    backgroundColor: Colors.primary,
    borderRadius: 4,
    paddingHorizontal: 4,
    paddingVertical: 1,
  },
  badgeTagText: {
    color: Colors.textOnPrimary,
    fontSize: 8,
    fontWeight: '700',
  },

  /* ── Chat Panel ── */
  chatPanel: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  chatHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    backgroundColor: Colors.surface,
    gap: 12,
  },
  backBtn: {
    marginRight: 4,
  },
  backArrow: {
    color: Colors.textActive,
    fontSize: 22,
  },
  chatHeaderInfo: {
    gap: 2,
  },
  chatHeaderName: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '600',
  },
  chatHeaderStatus: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  chatActionBtn: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: Sizes.borderRadiusSm,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  chatActionBtnText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '500',
  },
  chatActionBtnGold: {
    backgroundColor: Colors.primaryDim,
    borderRadius: Sizes.borderRadiusSm,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  chatActionBtnGoldText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '600',
  },

  /* ── Messages ── */
  messagesScroll: {
    flex: 1,
  },
  messagesContent: {
    padding: 16,
    gap: 12,
  },
  dateDivider: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 8,
  },
  dateLine: {
    flex: 1,
    height: 1,
    backgroundColor: Colors.border,
  },
  dateText: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '500',
  },
  messageBubbleWrap: {
    flexDirection: 'row',
    gap: 8,
    maxWidth: '80%',
  },
  bubbleLeft: {
    alignSelf: 'flex-start',
    alignItems: 'flex-end',
  },
  bubbleRight: {
    alignSelf: 'flex-end',
    flexDirection: 'row-reverse',
  },
  messageBubble: {
    borderRadius: 16,
    paddingHorizontal: 14,
    paddingVertical: 10,
    maxWidth: '100%',
  },
  bubbleOther: {
    backgroundColor: Colors.surfaceAlt,
    borderTopLeftRadius: 4,
  },
  bubbleMe: {
    backgroundColor: Colors.primaryDim,
    borderTopRightRadius: 4,
  },
  senderLabel: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '600',
    marginBottom: 4,
  },
  messageText: {
    fontSize: 14,
    lineHeight: 20,
  },
  messageTextOther: {
    color: Colors.textActive,
  },
  messageTextMe: {
    color: Colors.textActive,
  },
  messageTime: {
    color: Colors.textMuted,
    fontSize: 10,
    marginTop: 6,
    alignSelf: 'flex-end',
  },

  /* ── Input Bar ── */
  inputBar: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
    backgroundColor: Colors.surface,
    gap: 8,
  },
  inputIconBtn: {
    width: 36,
    height: 36,
    justifyContent: 'center',
    alignItems: 'center',
  },
  inputIconText: {
    fontSize: 20,
    color: Colors.textSecondary,
  },
  chatInput: {
    flex: 1,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 8,
    color: Colors.textActive,
    fontSize: 14,
    maxHeight: 100,
  },
  sendBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendBtnDisabled: {
    opacity: 0.4,
  },
  sendBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 16,
    fontWeight: '700',
  },

  /* ── Empty Chat State ── */
  emptyChat: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 12,
  },
  emptyChatIcon: {
    fontSize: 48,
    opacity: 0.5,
  },
  emptyChatTitle: {
    color: Colors.textSecondary,
    fontSize: 18,
    fontWeight: '600',
  },
  emptyChatSub: {
    color: Colors.textMuted,
    fontSize: 14,
  },
  loginBtn: {
    marginTop: 8,
    backgroundColor: Colors.primary,
    paddingHorizontal: 28,
    paddingVertical: 12,
    borderRadius: Sizes.borderRadiusSm,
  },
  loginBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '700',
  },

  /* ── Peer Sidebar ── */
  traderPanel: {
    width: 288,
    borderLeftWidth: 1,
    borderLeftColor: Colors.border,
    backgroundColor: Colors.surface,
  },
  traderHeader: {
    alignItems: 'center',
    paddingTop: 28,
    paddingBottom: 20,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  traderBadgeRow: {
    marginTop: 12,
  },
  traderBadge: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    overflow: 'hidden',
  },
  traderName: {
    color: Colors.textActive,
    fontSize: 17,
    fontWeight: '700',
    marginTop: 10,
  },
  traderHandle: {
    color: Colors.textMuted,
    fontSize: 13,
    marginTop: 2,
  },
  traderStatsGrid: {
    flexDirection: 'row',
    padding: 16,
    gap: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  traderStatCell: {
    flex: 1,
    alignItems: 'center',
    backgroundColor: Colors.surfaceAlt,
    borderRadius: Sizes.borderRadiusSm,
    paddingVertical: 12,
  },
  traderStatValue: {
    color: Colors.up,
    fontSize: 18,
    fontWeight: '700',
  },
  traderStatLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 4,
  },
  traderSection: {
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  traderSectionTitle: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    marginBottom: 10,
    textTransform: 'uppercase',
  },
  traderAbout: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 19,
  },
  traderDetailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  traderDetailLabel: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  traderDetailValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '600',
  },
  viewProfileBtn: {
    margin: 16,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    borderRadius: Sizes.borderRadiusSm,
    paddingVertical: 12,
    alignItems: 'center',
  },
  viewProfileText: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '700',
  },
});

/* ════════════════════════════════════════
   Modal Styles
   ════════════════════════════════════════ */

const modalStyles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  container: {
    width: '90%',
    maxWidth: 440,
    maxHeight: '80%',
    backgroundColor: Colors.surface,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.border,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  title: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
  },
  closeBtn: {
    color: Colors.textMuted,
    fontSize: 20,
    padding: 4,
  },
  searchBox: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  searchInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 14,
    padding: 0,
  },
  sectionLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 6,
  },
  list: {
    flex: 1,
    paddingBottom: 12,
  },
  userRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 10,
    gap: 12,
  },
  userName: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '600',
  },
  userSub: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 6,
    borderWidth: 2,
    borderColor: Colors.textMuted,
    justifyContent: 'center',
    alignItems: 'center',
  },
  checkboxSelected: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  checkmark: {
    color: Colors.background,
    fontSize: 14,
    fontWeight: '700',
  },
  fieldGroup: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 8,
  },
  fieldLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 6,
  },
  fieldInput: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    color: Colors.textActive,
    fontSize: 14,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  footer: {
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
  },
  createBtn: {
    backgroundColor: Colors.primary,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
  },
  createBtnDisabled: {
    opacity: 0.4,
  },
  createBtnText: {
    color: Colors.background,
    fontSize: 15,
    fontWeight: '700',
  },
});

