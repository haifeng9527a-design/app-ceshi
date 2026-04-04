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
import { useRouter, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { SkeletonConversation } from '../../components/Skeleton';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import { useMessagesStore } from '../../services/store/messagesStore';
import {
  createGroupConversation,
  searchConversationMessages,
  type ApiConversation,
  type ApiMessage,
  type PeerProfile,
  type FriendProfile,
} from '../../services/api/messagesApi';
import { getTraderProfile, type TraderProfile } from '../../services/api/traderApi';

/* ════════════════════════════════════════
   UI-layer types (unchanged from design)
   ════════════════════════════════════════ */

/** 视为「当前在线」：最近 N 分钟内有心跳（与好友 last_online_at 对齐） */
const PRESENCE_ACTIVE_MS = 15 * 60 * 1000;

interface Conversation {
  id: string;
  name: string;
  lastMessage: string;
  time: string;
  unread: number;
  online?: boolean;
  /** 好友接口返回的对方 last_online_at；无则不在标题显示「离线」，避免无数据时误判 */
  peerLastOnlineAt?: string;
  pinned?: boolean;
  verified?: boolean;
  badge?: string;
  isGroup?: boolean;
  members?: number;
  isSupport?: boolean;
  peerUserId?: string;
  isTraderPeer?: boolean;
}

/** Rich message: strategy / share card (JSON in content or message_type teacher_share). */
interface StrategyCardPayload {
  symbol?: string;
  title?: string;
  pnl_pct?: number;
  side?: string;
  leverage?: number;
}

interface ChatMessage {
  id: string;
  senderId: string;
  senderName: string;
  text: string;
  time: string;
  date?: string;
  messageType?: string;
  card?: StrategyCardPayload;
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

function isRecentlyOnline(isoString?: string, withinMs = 5 * 60 * 1000): boolean {
  if (!isoString) return false;
  return Date.now() - new Date(isoString).getTime() < withinMs;
}

function parseStrategyCard(content: string, messageType: string): StrategyCardPayload | undefined {
  if (messageType !== 'teacher_share' && !content.trim().startsWith('{')) {
    return undefined;
  }
  try {
    const o = JSON.parse(content) as Record<string, unknown>;
    return strategyFieldsFromObject(o);
  } catch {
    return undefined;
  }
}

function strategyFieldsFromObject(o: Record<string, unknown>): StrategyCardPayload | undefined {
  if (typeof o !== 'object' || o == null) return undefined;
  const title = typeof o.title === 'string' ? o.title : undefined;
  const symbol = typeof o.symbol === 'string' ? o.symbol : undefined;
  const side = typeof o.side === 'string' ? o.side : undefined;
  const pnl = typeof o.pnl_pct === 'number' ? o.pnl_pct : undefined;
  const lev = typeof o.leverage === 'number' ? o.leverage : undefined;
  if (!title && !symbol && pnl == null && lev == null) return undefined;
  return { title, symbol, side, pnl_pct: pnl, leverage: lev };
}

function parseStrategyCardFromMetadata(meta: Record<string, unknown> | undefined): StrategyCardPayload | undefined {
  if (!meta || typeof meta !== 'object') return undefined;
  return strategyFieldsFromObject(meta);
}

function sameConvoId(a: string | null | undefined, b: string | null | undefined): boolean {
  return String(a ?? '').trim() === String(b ?? '').trim();
}

function mapConversation(
  c: ApiConversation,
  peerProfiles: Record<string, PeerProfile>,
  friendsByUserId: Record<string, FriendProfile>,
): Conversation {
  const isGroup = c.type === 'group';
  const peer = c.peer_id ? peerProfiles[c.peer_id] : undefined;
  const friend = c.peer_id ? friendsByUserId[c.peer_id] : undefined;
  const name = isGroup ? (c.title || 'Group') : (peer?.display_name || 'User');
  const role = friend?.role?.toLowerCase() ?? '';
  const fromFriendRole =
    role === 'trader' || role === 'teacher' || role === 'approved' || role === 'certified';
  const isTraderPeer = c.peer_is_trader === true || fromFriendRole;
  const peerLo = friend?.last_online_at;
  const online = peerLo ? isRecentlyOnline(peerLo, PRESENCE_ACTIVE_MS) : false;

  return {
    id: c.id,
    name,
    lastMessage: c.last_message || '',
    time: formatRelativeTime(c.last_time),
    unread: c.unread_count || 0,
    isGroup,
    peerUserId: c.peer_id,
    isTraderPeer,
    verified: isTraderPeer,
    badge: isTraderPeer ? 'trader' : undefined,
    online,
    peerLastOnlineAt: peerLo || undefined,
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

    const cardMeta = parseStrategyCardFromMetadata(msg.metadata);
    const card = cardMeta ?? parseStrategyCard(msg.content, msg.message_type);
    result.push({
      id: msg.id,
      senderId:
        String(msg.sender_id ?? '') === String(currentUserId ?? '') ? 'me' : msg.sender_id,
      senderName: msg.sender_name,
      text: card ? '' : msg.content,
      time: formatMessageTime(msg.created_at),
      messageType: msg.message_type,
      card,
    });
  }

  return result;
}

/* ════════════════════════════════════════
   Filter tabs
   ════════════════════════════════════════ */

type ConvoFilter = 'all' | 'traders' | 'groups';

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

function StrategyCardBubble({
  card,
  isMe,
}: {
  card: StrategyCardPayload;
  isMe: boolean;
}) {
  const { t } = useTranslation();
  const pct = card.pnl_pct;
  const pctColor =
    pct == null ? Colors.textSecondary : pct >= 0 ? Colors.up : Colors.down;
  const title =
    card.title ||
    (card.symbol
      ? `${card.symbol}${card.leverage ? ` · ${card.leverage}${t('messages.leverage')}` : ''}`
      : t('messages.strategyShare'));
  const barPct = Math.min(100, Math.max(8, 50 + (pct ?? 0) * 2));

  return (
    <View
      style={[
        styles.strategyCard,
        isMe ? styles.strategyCardMe : styles.strategyCardOther,
      ]}
    >
      <View style={styles.strategyCardHeader}>
        <Text style={styles.strategyCardTitle} numberOfLines={2}>
          {title}
        </Text>
        {pct != null && (
          <Text style={[styles.strategyCardPct, { color: pctColor }]}>
            {pct >= 0 ? '+' : ''}
            {pct.toFixed(1)}%
          </Text>
        )}
      </View>
      {(card.symbol || card.side) && (
        <Text style={styles.strategyCardMeta}>
          {[card.symbol, card.side?.toUpperCase()]
            .filter(Boolean)
            .join(' · ')}
        </Text>
      )}
      <View style={styles.strategyCardBar}>
        <View
          style={[
            styles.strategyCardBarFill,
            {
              width: `${barPct}%`,
              backgroundColor: pctColor,
            },
          ]}
        />
      </View>
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
  onOpenContacts,
  friendRequestBadgeCount = 0,
  chatWsConnected,
}: {
  conversations: Conversation[];
  activeId: string;
  onSelect: (c: Conversation) => void;
  filter: ConvoFilter;
  onFilterChange: (f: ConvoFilter) => void;
  loading?: boolean;
  onAddFriend: () => void;
  onCreateGroup: () => void;
  onOpenContacts: () => void;
  friendRequestBadgeCount?: number;
  chatWsConnected: boolean;
}) {
  const { t } = useTranslation();
  const [listQuery, setListQuery] = useState('');

  const filterTabs: { key: ConvoFilter; label: string }[] = [
    { key: 'all', label: t('messages.filterAll') },
    { key: 'traders', label: t('messages.filterTraders') },
    { key: 'groups', label: t('messages.filterGroups') },
  ];

  const q = listQuery.trim().toLowerCase();
  const filtered = conversations.filter((c) => {
    if (filter === 'traders') {
      if (!(!c.isGroup && !!c.isTraderPeer)) return false;
    } else if (filter === 'groups') {
      if (!c.isGroup) return false;
    }
    if (!q) return true;
    return (
      c.name.toLowerCase().includes(q) ||
      (c.lastMessage || '').toLowerCase().includes(q)
    );
  });

  return (
    <View style={styles.listPanel}>
      {/* Header */}
      <View style={styles.listHeader}>
        <View style={styles.listHeaderLeft}>
          <Text style={styles.listTitle}>{t('messages.title')}</Text>
          <View style={styles.listSocketRow}>
            <View
              style={[
                styles.socketDot,
                { backgroundColor: chatWsConnected ? Colors.online : Colors.offline },
              ]}
            />
            <Text style={styles.socketStatusText} numberOfLines={1}>
              {chatWsConnected
                ? t('messages.chatSocketConnected')
                : t('messages.chatSocketDisconnected')}
            </Text>
          </View>
        </View>
        <View style={styles.headerActions}>
          <TouchableOpacity style={styles.headerActionBtn} activeOpacity={0.7} onPress={onAddFriend}>
            <Text style={styles.headerActionIcon}>👤+</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.headerActionBtn} activeOpacity={0.7} onPress={onCreateGroup}>
            <Text style={styles.headerActionIcon}>👥+</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.headerActionBtn} activeOpacity={0.7} onPress={onOpenContacts}>
            <View style={styles.headerIconWrap}>
              <Text style={styles.headerActionIcon}>📇</Text>
              {friendRequestBadgeCount > 0 ? (
                <View style={styles.headerBadge}>
                  <Text style={styles.headerBadgeText}>
                    {friendRequestBadgeCount > 99 ? '99+' : friendRequestBadgeCount}
                  </Text>
                </View>
              ) : null}
            </View>
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
          value={listQuery}
          onChangeText={setListQuery}
          autoCapitalize="none"
        />
      </View>

      {/* Filter Tabs */}
      <View style={styles.filterRow}>
        {filterTabs.map((f) => (
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
      <ScrollView
        style={styles.convoScroll}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="always"
      >
        {loading && filtered.length === 0 && (
          <View>
            {[1, 2, 3, 4, 5].map(i => <SkeletonConversation key={i} />)}
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
            active={sameConvoId(c.id, activeId)}
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
  const { t } = useTranslation();
  const badgeLabel =
    convo.badge === 'trader' ? t('messages.badgeTrader') : convo.badge;

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
          {!!badgeLabel && (
            <View style={styles.convoTagBadge}>
              <Text style={styles.convoTagBadgeText}>{badgeLabel}</Text>
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
  conversationId,
  messages,
  onBack,
  showBack,
  onSend,
  loading,
  onLoadMore,
  hasMore,
  peerUserId,
  onOpenTrader,
  chatWsConnected,
}: {
  conversation: Conversation;
  conversationId: string;
  messages: ChatMessage[];
  onBack?: () => void;
  showBack?: boolean;
  onSend: (text: string) => void;
  loading?: boolean;
  onLoadMore?: () => void;
  hasMore?: boolean;
  peerUserId?: string | null;
  onOpenTrader?: (uid: string) => void;
  chatWsConnected: boolean;
}) {
  const { t } = useTranslation();
  const [inputText, setInputText] = useState('');
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQ, setSearchQ] = useState('');
  const [searchRemote, setSearchRemote] = useState<ApiMessage[]>([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const searchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
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

  useEffect(() => {
    if (!searchOpen || !conversationId) {
      return;
    }
    const q = searchQ.trim();
    if (q.length < 1) {
      setSearchRemote([]);
      return;
    }
    if (searchDebounceRef.current) {
      clearTimeout(searchDebounceRef.current);
    }
    searchDebounceRef.current = setTimeout(async () => {
      setSearchLoading(true);
      try {
        const rows = await searchConversationMessages(conversationId, q, 40);
        setSearchRemote(rows);
      } catch {
        setSearchRemote([]);
      } finally {
        setSearchLoading(false);
      }
    }, 320);
    return () => {
      if (searchDebounceRef.current) {
        clearTimeout(searchDebounceRef.current);
      }
    };
  }, [searchOpen, searchQ, conversationId]);

  const statusLabel = (() => {
    if (conversation.isGroup) {
      return null;
    }
    const lo = conversation.peerLastOnlineAt;
    if (!lo) {
      return null;
    }
    if (conversation.online) {
      return t('messages.activeNow');
    }
    return `${t('messages.lastSeen')} · ${formatRelativeTime(lo)}`;
  })();

  const showCopyStrategy =
    !!peerUserId && !!conversation.isTraderPeer && !conversation.isGroup;

  return (
    <KeyboardAvoidingView
      style={styles.chatPanel}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={90}
    >
      <Modal visible={searchOpen} transparent animationType="fade" onRequestClose={() => setSearchOpen(false)}>
        <View style={modalStyles.overlay}>
          <View style={[modalStyles.container, { maxHeight: '70%' }]}>
            <View style={modalStyles.header}>
              <Text style={modalStyles.title}>{t('messages.searchInConversation')}</Text>
              <TouchableOpacity onPress={() => setSearchOpen(false)} activeOpacity={0.7}>
                <Text style={modalStyles.closeBtn}>✕</Text>
              </TouchableOpacity>
            </View>
            <View style={[modalStyles.fieldGroup, { marginBottom: 8 }]}>
              <TextInput
                style={modalStyles.fieldInput}
                placeholder={t('common.search')}
                placeholderTextColor={Colors.textMuted}
                value={searchQ}
                onChangeText={setSearchQ}
                autoFocus
                autoCapitalize="none"
              />
            </View>
            <ScrollView style={{ flexGrow: 0 }} keyboardShouldPersistTaps="handled">
              {searchLoading && (
                <ActivityIndicator color={Colors.primary} style={{ marginVertical: 12 }} />
              )}
              {!searchLoading && searchQ.trim() && searchRemote.length === 0 ? (
                <Text style={{ color: Colors.textMuted, padding: 16 }}>{t('common.noResults')}</Text>
              ) : (
                searchRemote.map((m) => (
                  <View key={m.id} style={{ paddingHorizontal: 16, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: Colors.border }}>
                    <Text style={{ color: Colors.primary, fontSize: 12 }}>
                      {m.sender_name || '—'} · {formatMessageTime(m.created_at)}
                    </Text>
                    <Text style={{ color: Colors.textActive, marginTop: 4 }} numberOfLines={3}>
                      {m.content || (m.metadata && typeof m.metadata === 'object' ? t('messages.strategyShare') : '')}
                    </Text>
                  </View>
                ))
              )}
            </ScrollView>
          </View>
        </View>
      </Modal>

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
          {statusLabel ? (
            <Text style={[styles.chatHeaderStatus, conversation.online && { color: Colors.up }]}>
              {statusLabel}
            </Text>
          ) : null}
        </View>
        <View style={{ flex: 1 }} />
        <View style={styles.chatSocketBadge}>
          <View
            style={[
              styles.socketDotSm,
              { backgroundColor: chatWsConnected ? Colors.online : Colors.offline },
            ]}
          />
          <Text style={styles.chatSocketBadgeText} numberOfLines={1}>
            {chatWsConnected
              ? t('messages.chatSocketConnected')
              : t('messages.chatSocketDisconnected')}
          </Text>
        </View>
        {showCopyStrategy && (
          <TouchableOpacity
            style={styles.chatActionBtnGold}
            activeOpacity={0.7}
            onPress={() => peerUserId && onOpenTrader?.(peerUserId)}
          >
            <Text style={styles.chatActionBtnGoldText}>{t('messages.copyStrategy')}</Text>
          </TouchableOpacity>
        )}
        <TouchableOpacity style={styles.chatActionBtn} activeOpacity={0.7} onPress={() => setSearchOpen(true)}>
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
                  msg.card && { backgroundColor: 'transparent', paddingHorizontal: 0, paddingVertical: 0 },
                ]}
              >
                {!isMe && conversation.isGroup && (
                  <Text style={styles.senderLabel}>{msg.senderName}</Text>
                )}
                {msg.card ? (
                  <StrategyCardBubble card={msg.card} isMe={isMe} />
                ) : (
                  <Text
                    style={[
                      styles.messageText,
                      isMe ? styles.messageTextMe : styles.messageTextOther,
                    ]}
                  >
                    {msg.text}
                  </Text>
                )}
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
          placeholder={t('messages.encryptPlaceholder', { name: conversation.name })}
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

function PeerSidebar({
  profile,
  peerUserId,
  onViewPublicProfile,
}: {
  profile: PeerProfile;
  peerUserId: string;
  onViewPublicProfile: (uid: string) => void;
}) {
  const { t } = useTranslation();
  const [trader, setTrader] = useState<TraderProfile | null>(null);

  useEffect(() => {
    let cancel = false;
    (async () => {
      try {
        const tp = await getTraderProfile(peerUserId);
        if (!cancel) setTrader(tp);
      } catch {
        if (!cancel) setTrader(null);
      }
    })();
    return () => {
      cancel = true;
    };
  }, [peerUserId]);

  const stats = trader?.stats;
  const winRatePct =
    stats && stats.win_rate != null ? Number(stats.win_rate).toFixed(1) : null;
  const copiers =
    stats?.followers_count != null ? stats.followers_count : null;

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
          {trader?.is_trader && (
            <>
              {winRatePct != null && (
                <Text style={styles.traderStatLine}>
                  {t('messages.winRate')}: {winRatePct}%
                </Text>
              )}
              {copiers != null && (
                <Text style={styles.traderStatLine}>
                  {t('messages.copiers')}: {copiers >= 1000 ? `${(copiers / 1000).toFixed(1)}k` : copiers}
                </Text>
              )}
            </>
          )}
        </View>
        <TouchableOpacity
          style={styles.viewProfileBtn}
          activeOpacity={0.8}
          onPress={() => onViewPublicProfile(peerUserId)}
        >
          <Text style={styles.viewProfileText}>{t('messages.viewPublicProfile')}</Text>
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
  const params = useLocalSearchParams<{ conversationId?: string | string[] }>();
  const openedFromRouteRef = useRef<string | null>(null);
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
    loadConversations,
    setActiveConversation,
    sendMessage,
    loadMoreMessages,
    loadFriends,
    loadFriendRequests,
    incomingFriendRequests,
    refreshActiveMessages,
    wsConnected: chatWsConnected,
  } = useMessagesStore();

  const [filter, setFilter] = useState<ConvoFilter>('all');
  const [mobileShowChat, setMobileShowChat] = useState(false);
  const [showCreateGroup, setShowCreateGroup] = useState(false);

  // Initialize on mount
  useEffect(() => {
    if (!user) return;
    loadConversations();
    loadFriends();
    loadFriendRequests();
  }, [user?.uid]);

  // 当前会话定时拉取：接收方在 WS 未连上或未推送时仍能看见新消息
  useEffect(() => {
    if (!user?.uid || !activeConversationId) return;
    const t = setInterval(() => {
      refreshActiveMessages();
    }, 3500);
    return () => clearInterval(t);
  }, [user?.uid, activeConversationId, refreshActiveMessages]);

  // 停留在消息 Tab 时定期刷新会话列表（最后一条预览等；不依赖 WS）
  useFocusEffect(
    useCallback(() => {
      if (!user?.uid) return;
      const t = setInterval(() => {
        loadConversations();
      }, 10000);
      return () => clearInterval(t);
    }, [user?.uid, loadConversations]),
  );

  const friendsById = useMemo(
    () => Object.fromEntries(friends.map((f) => [f.user_id, f])),
    [friends],
  );

  // Map API conversations to UI conversations
  const uiConversations = useMemo(
    () => apiConversations.map((c) => mapConversation(c, peerProfiles, friendsById)),
    [apiConversations, peerProfiles, friendsById],
  );

  // 从通讯录/加好友等带 conversationId 进入时打开对应会话
  useEffect(() => {
    const raw = params.conversationId;
    const cid =
      typeof raw === 'string'
        ? raw
        : Array.isArray(raw) && raw.length > 0
          ? raw[0]
          : undefined;
    if (!user) return;
    if (!cid?.trim()) {
      openedFromRouteRef.current = null;
      return;
    }
    if (openedFromRouteRef.current === cid) return;
    openedFromRouteRef.current = cid;
    setActiveConversation(cid);
    if (!isDesktop) setMobileShowChat(true);
  }, [params.conversationId, user?.uid, isDesktop, setActiveConversation]);

  // Map API messages to UI messages
  const uiMessages = useMemo(
    () => (user ? mapMessages(apiMessages, user.uid) : []),
    [apiMessages, user?.uid],
  );

  // Active conversation UI object（优先 ui 列表；否则从原始 api 映射，避免 activeConvo 为空导致聊天页不渲染）
  const activeConvo = useMemo(() => {
    const aid = activeConversationId;
    if (!aid) return null;
    const fromUi = uiConversations.find((c) => sameConvoId(c.id, aid));
    if (fromUi) return fromUi;
    const raw = apiConversations.find((c) => sameConvoId(c.id, aid));
    if (!raw) return null;
    return mapConversation(raw, peerProfiles, friendsById);
  }, [activeConversationId, uiConversations, apiConversations, peerProfiles, friendsById]);

  // Active conversation's peer profile (for sidebar)
  const activePeerProfile = useMemo(() => {
    const apiConvo = apiConversations.find((c) => sameConvoId(c.id, activeConversationId));
    if (!apiConvo?.peer_id) return null;
    return peerProfiles[apiConvo.peer_id] ?? null;
  }, [apiConversations, activeConversationId, peerProfiles]);

  const activePeerId = useMemo(() => {
    const c = apiConversations.find((x) => sameConvoId(x.id, activeConversationId));
    return c?.peer_id ?? null;
  }, [apiConversations, activeConversationId]);

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
          onOpenContacts={() => router.push('/contacts' as any)}
          friendRequestBadgeCount={incomingFriendRequests.length}
          chatWsConnected={chatWsConnected}
        />
      )}

      {/* Create Group Modal */}
      <CreateGroupModal
        visible={showCreateGroup}
        onClose={() => setShowCreateGroup(false)}
        onGroupCreated={handleNewConversation}
        friends={friends}
      />

      {/* 手机端：已选会话但列表映射尚未就绪时避免白屏 */}
      {showChat &&
        !isDesktop &&
        mobileShowChat &&
        activeConversationId &&
        !activeConvo && (
          <View style={styles.chatBootstrapping}>
            <ActivityIndicator color={Colors.primary} size="large" />
            <Text style={styles.chatBootstrappingText}>{t('common.loading')}</Text>
          </View>
        )}

      {/* Chat Panel */}
      {showChat && activeConvo && activeConversationId && (
        <ChatPanel
          conversation={activeConvo}
          conversationId={activeConversationId}
          messages={uiMessages}
          onBack={handleBack}
          showBack={!isDesktop}
          onSend={handleSend}
          loading={messagesLoading}
          onLoadMore={loadMoreMessages}
          hasMore={hasMoreMessages}
          peerUserId={activeConvo.peerUserId ?? activePeerId}
          onOpenTrader={(uid) => router.push(`/trader/${uid}` as any)}
          chatWsConnected={chatWsConnected}
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
      {isXL && activePeerProfile && activePeerId && (
        <PeerSidebar
          profile={activePeerProfile}
          peerUserId={activePeerId}
          onViewPublicProfile={(uid) => router.push(`/trader/${uid}` as any)}
        />
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
  chatBootstrapping: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: Colors.background,
    padding: 24,
  },
  chatBootstrappingText: {
    marginTop: 12,
    color: Colors.textMuted,
    fontSize: 14,
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
  listHeaderLeft: {
    flex: 1,
    minWidth: 0,
    marginRight: 8,
  },
  listTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '700',
  },
  listSocketRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 6,
  },
  socketDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  socketDotSm: {
    width: 6,
    height: 6,
    borderRadius: 3,
    flexShrink: 0,
  },
  socketStatusText: {
    fontSize: 11,
    color: Colors.textMuted,
    flex: 1,
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
  headerIconWrap: {
    position: 'relative',
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerBadge: {
    position: 'absolute',
    top: -6,
    right: -10,
    minWidth: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: '#c62828',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  headerBadgeText: {
    color: '#fff',
    fontSize: 9,
    fontWeight: '800',
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
  chatSocketBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    maxWidth: 140,
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderRadius: Sizes.borderRadiusSm,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  chatSocketBadgeText: {
    fontSize: 10,
    color: Colors.textMuted,
    flex: 1,
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

  strategyCard: {
    borderRadius: 12,
    padding: 12,
    minWidth: 220,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.surfaceAlt,
  },
  strategyCardMe: {
    borderColor: Colors.primary,
    backgroundColor: Colors.primaryDim,
  },
  strategyCardOther: {
    borderColor: Colors.glassBorder,
  },
  strategyCardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 8,
  },
  strategyCardTitle: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  strategyCardPct: {
    fontSize: 14,
    fontWeight: '700',
  },
  strategyCardMeta: {
    marginTop: 6,
    color: Colors.textMuted,
    fontSize: 11,
  },
  strategyCardBar: {
    marginTop: 10,
    height: 4,
    borderRadius: 2,
    backgroundColor: Colors.border,
    overflow: 'hidden',
  },
  strategyCardBarFill: {
    height: '100%',
    borderRadius: 2,
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
  traderStatLine: {
    color: Colors.textSecondary,
    fontSize: 13,
    marginTop: 8,
    fontWeight: '600',
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

