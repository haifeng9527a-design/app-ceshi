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
  Alert,
  Image,
} from 'react-native';
import { useRouter, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { SkeletonConversation } from '../../components/Skeleton';
import EquityCurve from '../../components/chart/EquityCurve';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import { useMessagesStore } from '../../services/store/messagesStore';
import { useCallStore } from '../../services/store/callStore';
import { Config } from '../../services/config';
import {
  addGroupMembers,
  createGroupConversation,
  dissolveGroup,
  fetchGroupInfo,
  fetchUserProfilesBatch,
  removeGroupMember,
  searchConversationMessages,
  updateGroupMemberRole,
  updateGroupInfo,
  type ApiConversation,
  type ApiMessage,
  type PeerProfile,
  type FriendProfile,
  type GroupInfo,
  uploadMessageAsset,
} from '../../services/api/messagesApi';
import {
  getTraderProfile,
  getMyFollowing,
  getTraderPositions,
  followTrader,
  unfollowTrader,
  type TraderProfile,
  type CopyTrading,
  type TraderPosition,
} from '../../services/api/traderApi';
import { getMyStrategies, type TraderStrategy } from '../../services/api/traderStrategyApi';
import { chatWs } from '../../services/websocket/chatWs';

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
  strategy_id?: string;
  symbol?: string;
  title?: string;
  summary?: string;
  cover_image?: string;
  category?: string;
  author_id?: string;
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
  mediaUrl?: string;
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
  const strategyId = typeof o.strategy_id === 'string' ? o.strategy_id : undefined;
  const title = typeof o.title === 'string' ? o.title : undefined;
  const symbol = typeof o.symbol === 'string' ? o.symbol : undefined;
  const side = typeof o.side === 'string' ? o.side : undefined;
  const summary = typeof o.summary === 'string' ? o.summary : undefined;
  const coverImage = typeof o.cover_image === 'string' ? o.cover_image : undefined;
  const category = typeof o.category === 'string' ? o.category : undefined;
  const authorId = typeof o.author_id === 'string' ? o.author_id : undefined;
  const pnl = typeof o.pnl_pct === 'number' ? o.pnl_pct : undefined;
  const lev = typeof o.leverage === 'number' ? o.leverage : undefined;
  if (!strategyId && !title && !symbol && pnl == null && lev == null) return undefined;
  return {
    strategy_id: strategyId,
    title,
    symbol,
    side,
    summary,
    cover_image: coverImage,
    category,
    author_id: authorId,
    pnl_pct: pnl,
    leverage: lev,
  };
}

function parseStrategyCardFromMetadata(meta: Record<string, unknown> | undefined): StrategyCardPayload | undefined {
  if (!meta || typeof meta !== 'object') return undefined;
  return strategyFieldsFromObject(meta);
}

function sameConvoId(a: string | null | undefined, b: string | null | undefined): boolean {
  return String(a ?? '').trim() === String(b ?? '').trim();
}

function normId(v: string | null | undefined): string {
  return String(v ?? '').trim();
}

function compactNumber(v?: number | null): string {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n)) return '0';
  if (Math.abs(n) >= 1000000) return `${(n / 1000000).toFixed(1)}m`;
  if (Math.abs(n) >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return `${Math.round(n)}`;
}

function formatPnl(v?: number | null): string {
  const n = Number(v ?? 0);
  if (!Number.isFinite(n)) return '$0';
  const sign = n > 0 ? '+' : '';
  return `${sign}$${compactNumber(n)}`;
}

type CopyRiskPreset = {
  key: 'steady' | 'balanced' | 'aggressive';
  label: string;
  ratio: string;
  maxPosition: string;
  note: string;
};

const COPY_RISK_PRESETS: CopyRiskPreset[] = [
  { key: 'steady', label: '稳健', ratio: '0.5', maxPosition: '250', note: '更轻仓，适合先观察交易员风格。' },
  { key: 'balanced', label: '均衡', ratio: '1.0', maxPosition: '500', note: '默认建议档，兼顾参与度和风险。' },
  { key: 'aggressive', label: '进取', ratio: '2.0', maxPosition: '1000', note: '高杠杆跟随，波动和回撤都会更大。' },
];

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
      mediaUrl: msg.media_url,
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
  onPress,
}: {
  card: StrategyCardPayload;
  isMe: boolean;
  onPress?: () => void;
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
    <TouchableOpacity
      style={[
        styles.strategyCard,
        isMe ? styles.strategyCardMe : styles.strategyCardOther,
      ]}
      activeOpacity={onPress ? 0.85 : 1}
      disabled={!onPress}
      onPress={onPress}
    >
      {!!card.cover_image && (
        <Image source={{ uri: card.cover_image }} style={styles.strategyCardCover} />
      )}
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
      {!!card.summary && (
        <Text style={styles.strategyCardSummary} numberOfLines={2}>
          {card.summary}
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
    </TouchableOpacity>
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

  const selectedFriends = useMemo(
    () => friends.filter((f) => selectedIds.has(f.user_id)),
    [friends, selectedIds],
  );

  const filteredFriends = useMemo(() => {
    if (!searchQuery.trim()) return friends;
    const q = searchQuery.toLowerCase();
    return friends.filter(
      (f) =>
        f.display_name.toLowerCase().includes(q) ||
        f.email?.toLowerCase().includes(q) ||
        f.short_id?.toLowerCase().includes(q),
    );
  }, [friends, searchQuery]);

  const suggestedName = useMemo(() => {
    if (groupName.trim()) return groupName.trim();
    if (selectedFriends.length === 0) return '新群聊';
    if (selectedFriends.length <= 3) {
      return selectedFriends.map((f) => f.display_name).join('、');
    }
    return `${selectedFriends[0].display_name} 等 ${selectedFriends.length} 人`;
  }, [groupName, selectedFriends]);

  const toggleSelect = (userId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  };

  const handleCreate = useCallback(async () => {
    const title = groupName.trim() || suggestedName;
    if (selectedIds.size < 2 || !title.trim()) return;
    setCreating(true);
    try {
      const result = await createGroupConversation(title, Array.from(selectedIds));
      onGroupCreated(result.id);
      onClose();
      setGroupName('');
      setSelectedIds(new Set());
      setSearchQuery('');
    } catch (e) {
      console.error('[CreateGroup] Failed:', e);
    } finally {
      setCreating(false);
    }
  }, [selectedIds, groupName, suggestedName, onGroupCreated, onClose]);

  const resetAndClose = useCallback(() => {
    setGroupName('');
    setSelectedIds(new Set());
    setSearchQuery('');
    onClose();
  }, [onClose]);

  if (!visible) return null;

  return (
    <Modal visible transparent animationType="fade" onRequestClose={resetAndClose}>
      <View style={modalStyles.overlay}>
        <View style={modalStyles.container}>
          {/* Header */}
          <View style={modalStyles.header}>
            <Text style={modalStyles.title}>创建群聊</Text>
            <TouchableOpacity onPress={resetAndClose} activeOpacity={0.7}>
              <Text style={modalStyles.closeBtn}>✕</Text>
            </TouchableOpacity>
          </View>

          <View style={modalStyles.groupHero}>
            <AvatarCircle name={suggestedName} size={62} badge={`${selectedIds.size + 1}`} />
            <View style={{ flex: 1 }}>
              <Text style={modalStyles.groupHeroTitle} numberOfLines={1}>
                {suggestedName}
              </Text>
              <Text style={modalStyles.groupHeroSub}>
                创建后共 {selectedIds.size + 1} 人，包含你自己
              </Text>
            </View>
          </View>

          {/* Group Name */}
          <View style={modalStyles.fieldGroup}>
            <View style={modalStyles.fieldLabelRow}>
              <Text style={modalStyles.fieldLabel}>群名称</Text>
              <Text style={modalStyles.fieldCounter}>{groupName.trim().length}/24</Text>
            </View>
            <TextInput
              style={modalStyles.fieldInput}
              placeholder="输入群聊名称"
              placeholderTextColor={Colors.textMuted}
              value={groupName}
              onChangeText={(text) => setGroupName(text.slice(0, 24))}
            />
            <Text style={modalStyles.helperText}>
              留空将自动使用默认群名。建议使用清晰、易识别的名称。
            </Text>
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

          {selectedFriends.length > 0 && (
            <View style={modalStyles.selectedSection}>
              <Text style={modalStyles.sectionLabel}>已选成员</Text>
              <ScrollView
                horizontal
                showsHorizontalScrollIndicator={false}
                contentContainerStyle={modalStyles.selectedChips}
              >
                {selectedFriends.map((f) => (
                  <TouchableOpacity
                    key={f.user_id}
                    style={modalStyles.selectedChip}
                    activeOpacity={0.75}
                    onPress={() => toggleSelect(f.user_id)}
                  >
                    <Text style={modalStyles.selectedChipText} numberOfLines={1}>
                      {f.display_name}
                    </Text>
                    <Text style={modalStyles.selectedChipRemove}>✕</Text>
                  </TouchableOpacity>
                ))}
              </ScrollView>
            </View>
          )}

          {/* Selected count */}
          <Text style={[modalStyles.sectionLabel, { marginTop: 4 }]}>
            选择成员 {selectedIds.size >= 2 ? `(${selectedIds.size} 已选)` : '(至少选择 2 位好友)'}
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
                (selectedIds.size < 2 || !suggestedName.trim()) && modalStyles.createBtnDisabled,
              ]}
              onPress={handleCreate}
              disabled={creating || selectedIds.size < 2 || !suggestedName.trim()}
              activeOpacity={0.8}
            >
              {creating ? (
                <ActivityIndicator size="small" color={Colors.background} />
              ) : (
                <Text style={modalStyles.createBtnText}>
                  创建 {selectedIds.size + 1} 人群聊
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
  canSendStrategy,
  chatWsConnected,
  onSendImage,
  onSendStrategy,
  onStartVoiceCall,
  callPending,
  activeCallStatus,
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
  canSendStrategy?: boolean;
  chatWsConnected: boolean;
  onSendImage?: (file: File) => Promise<void>;
  onSendStrategy?: (strategy: TraderStrategy) => Promise<void>;
  onStartVoiceCall?: () => Promise<void>;
  callPending?: boolean;
  activeCallStatus?: string | null;
}) {
  const { t } = useTranslation();
  const router = useRouter();
  const [inputText, setInputText] = useState('');
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQ, setSearchQ] = useState('');
  const [searchRemote, setSearchRemote] = useState<ApiMessage[]>([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const [showStrategyPicker, setShowStrategyPicker] = useState(false);
  const [strategyOptions, setStrategyOptions] = useState<TraderStrategy[]>([]);
  const [strategyLoading, setStrategyLoading] = useState(false);
  const [composerBusy, setComposerBusy] = useState(false);
  const [imagePreviewUrl, setImagePreviewUrl] = useState<string | null>(null);
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

  const handlePickImage = useCallback(async () => {
    if (!onSendImage) return;
    if (Platform.OS !== 'web') {
      Alert.alert('', '移动端图片发送将在下一轮补上，当前可先使用网页端。');
      return;
    }

    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.onchange = async (event: Event) => {
      const file = (event.target as HTMLInputElement)?.files?.[0];
      if (!file) return;
      setComposerBusy(true);
      try {
        await onSendImage(file);
      } catch (e: any) {
        Alert.alert('发送失败', e?.response?.data?.error || e?.message || '图片发送失败');
      } finally {
        setComposerBusy(false);
      }
    };
    input.click();
  }, [onSendImage]);

  const openStrategyPicker = useCallback(async () => {
    if (!onSendStrategy) return;
    setShowStrategyPicker(true);
    setStrategyLoading(true);
    try {
      const { strategies } = await getMyStrategies('published', 50, 0);
      setStrategyOptions(strategies || []);
    } catch {
      setStrategyOptions([]);
    } finally {
      setStrategyLoading(false);
    }
  }, [onSendStrategy]);

  const handleSendStrategy = useCallback(async (strategy: TraderStrategy) => {
    if (!onSendStrategy) return;
    setComposerBusy(true);
    try {
      await onSendStrategy(strategy);
      setShowStrategyPicker(false);
    } catch (e: any) {
      Alert.alert('发送失败', e?.response?.data?.error || e?.message || '策略发送失败');
    } finally {
      setComposerBusy(false);
    }
  }, [onSendStrategy]);

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

      <Modal visible={showStrategyPicker} transparent animationType="fade" onRequestClose={() => setShowStrategyPicker(false)}>
        <View style={modalStyles.overlay}>
          <View style={[modalStyles.container, { maxHeight: '72%' }]}>
            <View style={modalStyles.header}>
              <Text style={modalStyles.title}>发送交易策略</Text>
              <TouchableOpacity onPress={() => setShowStrategyPicker(false)} activeOpacity={0.7}>
                <Text style={modalStyles.closeBtn}>✕</Text>
              </TouchableOpacity>
            </View>
            <ScrollView style={{ flexGrow: 0 }} showsVerticalScrollIndicator={false}>
              {strategyLoading ? (
                <ActivityIndicator color={Colors.primary} style={{ marginVertical: 20 }} />
              ) : strategyOptions.length === 0 ? (
                <Text style={{ color: Colors.textMuted, padding: 20 }}>暂无已发布策略</Text>
              ) : (
                strategyOptions.map((strategy) => (
                  <TouchableOpacity
                    key={strategy.id}
                    style={styles.strategyPickerItem}
                    activeOpacity={0.85}
                    onPress={() => handleSendStrategy(strategy)}
                    disabled={composerBusy}
                  >
                    {!!strategy.cover_image && (
                      <Image source={{ uri: strategy.cover_image }} style={styles.strategyPickerThumb} />
                    )}
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Text style={styles.strategyPickerTitle} numberOfLines={1}>{strategy.title}</Text>
                      <Text style={styles.strategyPickerSummary} numberOfLines={2}>{strategy.summary}</Text>
                    </View>
                    <Text style={styles.strategyPickerAction}>发送</Text>
                  </TouchableOpacity>
                ))
              )}
            </ScrollView>
          </View>
        </View>
      </Modal>

      <Modal visible={!!imagePreviewUrl} transparent animationType="fade" onRequestClose={() => setImagePreviewUrl(null)}>
        <View style={styles.imagePreviewOverlay}>
          <TouchableOpacity style={styles.imagePreviewClose} activeOpacity={0.8} onPress={() => setImagePreviewUrl(null)}>
            <Text style={styles.imagePreviewCloseText}>✕</Text>
          </TouchableOpacity>
          {imagePreviewUrl ? <Image source={{ uri: imagePreviewUrl }} style={styles.imagePreviewImage} resizeMode="contain" /> : null}
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
        {!conversation.isGroup && (
          <TouchableOpacity
            style={[styles.chatActionBtn, callPending && styles.groupActionBtnDisabled]}
            activeOpacity={0.7}
            disabled={callPending}
            onPress={() => void onStartVoiceCall?.()}
          >
            <Text style={styles.chatActionBtnText}>
              {activeCallStatus === 'active' ? '通话中' : activeCallStatus === 'ringing' ? '响铃中' : '📞 语音电话'}
            </Text>
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
                  <StrategyCardBubble
                    card={msg.card}
                    isMe={isMe}
                    onPress={msg.card.strategy_id ? () => router.push(`/strategy/${msg.card?.strategy_id}` as any) : undefined}
                  />
                ) : msg.messageType === 'image' && msg.mediaUrl ? (
                  <TouchableOpacity activeOpacity={0.85} onPress={() => setImagePreviewUrl(msg.mediaUrl || null)}>
                    <Image source={{ uri: msg.mediaUrl }} style={styles.chatImageBubble} />
                  </TouchableOpacity>
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
        <TouchableOpacity style={styles.inputIconBtn} activeOpacity={0.7} onPress={handlePickImage} disabled={composerBusy}>
          <Text style={styles.inputIconText}>🖼</Text>
        </TouchableOpacity>
        {canSendStrategy ? (
          <TouchableOpacity style={styles.inputIconBtn} activeOpacity={0.7} onPress={openStrategyPicker} disabled={composerBusy}>
            <Text style={styles.inputIconText}>📈</Text>
          </TouchableOpacity>
        ) : null}
        <TextInput
          style={styles.chatInput}
          placeholder={t('messages.encryptPlaceholder', { name: conversation.name })}
          placeholderTextColor={Colors.textMuted}
          value={inputText}
          onChangeText={setInputText}
          multiline
          onSubmitEditing={handleSend}
        />
        <TouchableOpacity
          style={[styles.sendBtn, (!inputText.trim() || composerBusy) && styles.sendBtnDisabled]}
          activeOpacity={0.7}
          onPress={handleSend}
          disabled={!inputText.trim() || composerBusy}
        >
          {composerBusy ? <ActivityIndicator size="small" color={Colors.background} /> : <Text style={styles.sendBtnText}>➤</Text>}
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
  const { user } = useAuthStore();
  const [trader, setTrader] = useState<TraderProfile | null>(null);
  const [positions, setPositions] = useState<TraderPosition[]>([]);
  const [loading, setLoading] = useState(true);
  const [following, setFollowing] = useState(false);
  const [activeRelation, setActiveRelation] = useState<CopyTrading | null>(null);
  const [showFollowModal, setShowFollowModal] = useState(false);
  const [copyRatio, setCopyRatio] = useState('1.0');
  const [maxPosition, setMaxPosition] = useState('');
  const [actionLoading, setActionLoading] = useState(false);
  const isSelf = user?.uid === peerUserId;

  const loadSidebarData = useCallback(async () => {
    const [tp, followingList, pos] = await Promise.all([
      getTraderProfile(peerUserId),
      user && !isSelf ? getMyFollowing().catch(() => [] as CopyTrading[]) : Promise.resolve([] as CopyTrading[]),
      getTraderPositions(peerUserId).catch(() => [] as TraderPosition[]),
    ]);
    setTrader(tp);
    setPositions(pos);
    if (!isSelf) {
      const relation =
        followingList.find((item) => item.trader_id === peerUserId && item.status === 'active') ?? null;
      setActiveRelation(relation);
      setFollowing(!!relation);
      if (relation) {
        setCopyRatio(String(relation.copy_ratio || 1.0));
        setMaxPosition(relation.max_position != null ? String(relation.max_position) : '');
      } else {
        setCopyRatio('1.0');
        setMaxPosition('');
      }
    }
  }, [peerUserId, user, isSelf]);

  useEffect(() => {
    let cancel = false;
    (async () => {
      setLoading(true);
      try {
        await loadSidebarData();
        if (cancel) return;
      } catch {
        if (!cancel) {
          setTrader(null);
          setPositions([]);
          setActiveRelation(null);
          setFollowing(false);
        }
      } finally {
        if (!cancel) setLoading(false);
      }
    })();
    return () => {
      cancel = true;
    };
  }, [peerUserId, user?.uid, isSelf, loadSidebarData]);

  const handleFollow = useCallback(async () => {
    if (!user) {
      Alert.alert('', t('auth.notLoggedIn'));
      return;
    }
    setActionLoading(true);
    try {
      const ratio = parseFloat(copyRatio) || 1.0;
      const parsedMax = maxPosition.trim() ? parseFloat(maxPosition) : undefined;
      await followTrader(peerUserId, {
        copy_ratio: ratio,
        max_position: parsedMax && Number.isFinite(parsedMax) ? parsedMax : undefined,
      });
      await loadSidebarData();
      setShowFollowModal(false);
    } catch (e: any) {
      Alert.alert('Error', e?.response?.data?.error || e?.message || 'Follow failed');
    } finally {
      setActionLoading(false);
    }
  }, [copyRatio, maxPosition, peerUserId, t, user, loadSidebarData]);

  const handleUnfollow = useCallback(async () => {
    setActionLoading(true);
    try {
      await unfollowTrader(peerUserId);
      await loadSidebarData();
    } catch (e: any) {
      Alert.alert('Error', e?.response?.data?.error || e?.message || 'Unfollow failed');
    } finally {
      setActionLoading(false);
    }
  }, [peerUserId, loadSidebarData]);

  const openFollowModal = useCallback(() => {
    setCopyRatio(String(activeRelation?.copy_ratio || 1.0));
    setMaxPosition(activeRelation?.max_position != null ? String(activeRelation.max_position) : '');
    setShowFollowModal(true);
  }, [activeRelation]);

  const stats = trader?.stats;
  const winRatePct =
    stats && stats.win_rate != null ? Number(stats.win_rate).toFixed(1) : null;
  const copiers =
    stats?.followers_count != null ? stats.followers_count : null;
  const totalPnl = stats?.total_pnl ?? null;
  const maxDrawdown = stats?.max_drawdown ?? null;
  const totalTrades = stats?.total_trades ?? null;
  const avgPnl = stats?.avg_pnl ?? null;
  const copyEnabled = trader?.allow_copy_trading === true;
  const visiblePositions = positions.slice(0, 2);
  const ratioValue = parseFloat(copyRatio);
  const maxPositionValue = parseFloat(maxPosition);
  const normalizedRatio = Number.isFinite(ratioValue) && ratioValue > 0 ? ratioValue : 1;
  const normalizedMaxPosition =
    Number.isFinite(maxPositionValue) && maxPositionValue > 0 ? maxPositionValue : null;
  const estimatedExposure = normalizedMaxPosition != null ? normalizedRatio * normalizedMaxPosition : null;

  const applyRiskPreset = useCallback((preset: CopyRiskPreset) => {
    setCopyRatio(preset.ratio);
    setMaxPosition(preset.maxPosition);
  }, []);

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
          {loading ? (
            <ActivityIndicator size="small" color={Colors.primary} style={{ marginTop: 12 }} />
          ) : trader?.is_trader ? (
            <>
              <View style={styles.traderBadgeRow}>
                <Text style={styles.traderBadge}>认证交易员</Text>
              </View>
              <View style={styles.traderMetaPills}>
                <View style={styles.traderMetaPill}>
                  <Text style={styles.traderMetaPillText}>
                    {copyEnabled ? '可跟单' : '已关闭跟单'}
                  </Text>
                </View>
                {following && (
                  <View style={[styles.traderMetaPill, styles.traderMetaPillActive]}>
                    <Text style={[styles.traderMetaPillText, styles.traderMetaPillActiveText]}>
                      已跟单
                    </Text>
                  </View>
                )}
              </View>
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
          ) : null}
        </View>

        {trader?.is_trader && (
          <>
            <View style={styles.traderStatsGrid}>
              <View style={styles.traderStatCell}>
                <Text
                  style={[
                    styles.traderStatValue,
                    totalPnl != null && totalPnl < 0 ? { color: Colors.down } : null,
                  ]}
                >
                  {formatPnl(totalPnl)}
                </Text>
                <Text style={styles.traderStatLabel}>总收益</Text>
              </View>
              <View style={styles.traderStatCell}>
                <Text style={[styles.traderStatValue, { color: Colors.down }]}>
                  {maxDrawdown != null ? `${Number(maxDrawdown).toFixed(1)}%` : '--'}
                </Text>
                <Text style={styles.traderStatLabel}>最大回撤</Text>
              </View>
            </View>

            <View style={styles.traderSection}>
              <Text style={styles.traderSectionTitle}>交易员概览</Text>
              <View style={styles.traderDetailRow}>
                <Text style={styles.traderDetailLabel}>开放跟单</Text>
                <Text style={styles.traderDetailValue}>{copyEnabled ? '已开启' : '未开启'}</Text>
              </View>
              <View style={styles.traderDetailRow}>
                <Text style={styles.traderDetailLabel}>总交易数</Text>
                <Text style={styles.traderDetailValue}>{compactNumber(totalTrades)}</Text>
              </View>
              <View style={styles.traderDetailRow}>
                <Text style={styles.traderDetailLabel}>平均盈亏</Text>
                <Text
                  style={[
                    styles.traderDetailValue,
                    avgPnl != null && avgPnl < 0 ? { color: Colors.down } : { color: Colors.up },
                  ]}
                >
                  {formatPnl(avgPnl)}
                </Text>
              </View>
            </View>

            <View style={styles.traderCurveWrap}>
              <EquityCurve totalPnl={Number(totalPnl ?? 0)} totalTrades={Number(totalTrades ?? 0)} />
            </View>

            <View style={styles.traderSection}>
              <Text style={styles.traderSectionTitle}>当前持仓</Text>
              {visiblePositions.length === 0 ? (
                <Text style={styles.traderAbout}>暂无公开持仓摘要</Text>
              ) : (
                visiblePositions.map((pos) => {
                  const pnl = Number(pos.unrealized_pnl ?? 0);
                  return (
                    <View key={pos.id} style={styles.traderDetailRow}>
                      <View>
                        <Text style={styles.traderDetailValue}>{pos.symbol}</Text>
                        <Text style={styles.traderDetailLabel}>
                          {pos.side.toUpperCase()} · {pos.leverage}x
                        </Text>
                      </View>
                      <Text
                        style={[
                          styles.traderDetailValue,
                          pnl < 0 ? { color: Colors.down } : { color: Colors.up },
                        ]}
                      >
                        {formatPnl(pnl)}
                      </Text>
                    </View>
                  );
                })
              )}
            </View>
          </>
        )}

        {trader?.is_trader && !isSelf && (
          <>
            {copyEnabled ? (
              following ? (
                <TouchableOpacity
                  style={[styles.viewProfileBtn, styles.followSidebarBtn]}
                  activeOpacity={0.8}
                  onPress={openFollowModal}
                  disabled={actionLoading}
                >
                  {actionLoading ? (
                    <ActivityIndicator color={Colors.background} size="small" />
                  ) : (
                    <Text style={[styles.viewProfileText, styles.followSidebarBtnText]}>调整跟单设置</Text>
                  )}
                </TouchableOpacity>
              ) : (
                <TouchableOpacity
                  style={[styles.viewProfileBtn, styles.followSidebarBtn]}
                  activeOpacity={0.8}
                  onPress={openFollowModal}
                  disabled={actionLoading}
                >
                  <Text style={[styles.viewProfileText, styles.followSidebarBtnText]}>一键跟单</Text>
                </TouchableOpacity>
              )
            ) : (
              <View style={[styles.viewProfileBtn, styles.disabledSidebarBtn]}>
                <Text style={[styles.viewProfileText, styles.disabledSidebarBtnText]}>暂未开放跟单</Text>
              </View>
            )}
            {following && (
              <TouchableOpacity
                style={[styles.viewProfileBtn, styles.unfollowSidebarBtn]}
                activeOpacity={0.8}
                onPress={handleUnfollow}
                disabled={actionLoading}
              >
                {actionLoading ? (
                  <ActivityIndicator color={Colors.down} size="small" />
                ) : (
                  <Text style={[styles.viewProfileText, styles.unfollowSidebarBtnText]}>取消跟单</Text>
                )}
              </TouchableOpacity>
            )}
          </>
        )}

        <TouchableOpacity
          style={[styles.viewProfileBtn, styles.secondarySidebarBtn]}
          activeOpacity={0.8}
          onPress={() => onViewPublicProfile(peerUserId)}
        >
          <Text style={[styles.viewProfileText, styles.secondarySidebarBtnText]}>{t('messages.viewPublicProfile')}</Text>
        </TouchableOpacity>
      </ScrollView>

      <Modal visible={showFollowModal} transparent animationType="fade" onRequestClose={() => setShowFollowModal(false)}>
        <View style={modalStyles.overlay}>
          <View style={[modalStyles.container, { maxWidth: 360 }]}>
            <View style={modalStyles.header}>
              <Text style={modalStyles.title}>跟单设置</Text>
              <TouchableOpacity onPress={() => setShowFollowModal(false)}>
                <Text style={modalStyles.closeBtn}>✕</Text>
              </TouchableOpacity>
            </View>
            <View style={modalStyles.fieldGroup}>
              <Text style={modalStyles.fieldLabel}>风险档位 Risk Preset</Text>
              <View style={modalStyles.presetGrid}>
                {COPY_RISK_PRESETS.map((preset) => {
                  const active = copyRatio === preset.ratio && maxPosition === preset.maxPosition;
                  return (
                    <TouchableOpacity
                      key={preset.key}
                      style={[modalStyles.presetCard, active && modalStyles.presetCardActive]}
                      activeOpacity={0.8}
                      onPress={() => applyRiskPreset(preset)}
                    >
                      <Text style={[modalStyles.presetTitle, active && modalStyles.presetTitleActive]}>
                        {preset.label}
                      </Text>
                      <Text style={modalStyles.presetMeta}>{preset.ratio}x · ≤ ${preset.maxPosition}</Text>
                      <Text style={modalStyles.presetNote}>{preset.note}</Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            </View>
            <View style={modalStyles.fieldGroup}>
              <Text style={modalStyles.fieldLabel}>跟单比例 Copy Ratio</Text>
              <TextInput
                style={modalStyles.fieldInput}
                value={copyRatio}
                onChangeText={setCopyRatio}
                keyboardType="decimal-pad"
                placeholder="1.0"
                placeholderTextColor={Colors.textMuted}
              />
              <View style={modalStyles.chipRow}>
                {['0.5', '1.0', '1.5', '2.0', '3.0'].map((value) => {
                  const active = copyRatio === value;
                  return (
                    <TouchableOpacity
                      key={value}
                      style={[modalStyles.chip, active && modalStyles.chipActive]}
                      activeOpacity={0.75}
                      onPress={() => setCopyRatio(value)}
                    >
                      <Text style={[modalStyles.chipText, active && modalStyles.chipTextActive]}>{value}x</Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            </View>
            <View style={modalStyles.fieldGroup}>
              <Text style={modalStyles.fieldLabel}>最大仓位 Max Position</Text>
              <TextInput
                style={modalStyles.fieldInput}
                value={maxPosition}
                onChangeText={setMaxPosition}
                keyboardType="decimal-pad"
                placeholder="可选"
                placeholderTextColor={Colors.textMuted}
              />
              <View style={modalStyles.chipRow}>
                {['250', '500', '1000', '2000'].map((value) => {
                  const active = maxPosition === value;
                  return (
                    <TouchableOpacity
                      key={value}
                      style={[modalStyles.chip, active && modalStyles.chipActive]}
                      activeOpacity={0.75}
                      onPress={() => setMaxPosition(value)}
                    >
                      <Text style={[modalStyles.chipText, active && modalStyles.chipTextActive]}>${value}</Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            </View>
            <View style={modalStyles.fieldGroup}>
              <Text style={modalStyles.fieldLabel}>设置摘要</Text>
              <View style={modalStyles.summaryCard}>
                <View style={modalStyles.summaryRow}>
                  <Text style={modalStyles.summaryLabel}>跟单比例</Text>
                  <Text style={modalStyles.summaryValue}>{normalizedRatio.toFixed(2)}x</Text>
                </View>
                <View style={modalStyles.summaryRow}>
                  <Text style={modalStyles.summaryLabel}>单笔最大仓位</Text>
                  <Text style={modalStyles.summaryValue}>
                    {normalizedMaxPosition != null ? `$${compactNumber(normalizedMaxPosition)}` : '未限制'}
                  </Text>
                </View>
                <View style={modalStyles.summaryRow}>
                  <Text style={modalStyles.summaryLabel}>估算最大敞口</Text>
                  <Text style={modalStyles.summaryValue}>
                    {estimatedExposure != null ? `$${compactNumber(estimatedExposure)}` : '随交易员仓位变化'}
                  </Text>
                </View>
                <Text style={modalStyles.summaryHint}>
                  建议先从 0.5x 或 1.0x 开始，确认交易员风格与你的风险承受能力匹配后再放大仓位。
                </Text>
              </View>
            </View>
            <View style={modalStyles.footer}>
              <TouchableOpacity
                style={[modalStyles.createBtn, actionLoading && modalStyles.createBtnDisabled]}
                onPress={handleFollow}
                disabled={actionLoading}
              >
                {actionLoading ? (
                  <ActivityIndicator color={Colors.background} size="small" />
                ) : (
                  <Text style={modalStyles.createBtnText}>确认跟单</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function GroupSidebar({
  conversationId,
  fallbackTitle,
}: {
  conversationId: string;
  fallbackTitle: string;
}) {
  const router = useRouter();
  const { user } = useAuthStore();
  const friends = useMessagesStore((s) => s.friends);
  const loadConversations = useMessagesStore((s) => s.loadConversations);
  const setActiveConversation = useMessagesStore((s) => s.setActiveConversation);
  const [groupInfo, setGroupInfo] = useState<GroupInfo | null>(null);
  const [memberProfiles, setMemberProfiles] = useState<Record<string, PeerProfile>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showAddModal, setShowAddModal] = useState(false);
  const [memberActionTarget, setMemberActionTarget] = useState<GroupInfo['members'][number] | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [memberSearch, setMemberSearch] = useState('');
  const [addingIds, setAddingIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    let cancel = false;
    (async () => {
      setLoading(true);
      try {
        const info = await fetchGroupInfo(conversationId);
        if (cancel) return;
        setGroupInfo(info);
        const ids = (info?.members ?? [])
          .map((m) => String(m.user_id || '').trim())
          .filter(Boolean);
        if (ids.length > 0) {
          const profiles = await fetchUserProfilesBatch(ids);
          if (!cancel) setMemberProfiles(profiles);
        } else if (!cancel) {
          setMemberProfiles({});
        }
      } catch {
        if (!cancel) {
          setGroupInfo(null);
          setMemberProfiles({});
        }
      } finally {
        if (!cancel) setLoading(false);
      }
    })();
    return () => {
      cancel = true;
    };
  }, [conversationId]);

  const title = groupInfo?.title || fallbackTitle || '群聊';
  const members = groupInfo?.members ?? [];
  const myRole = members.find((m) => m.user_id === user?.uid)?.role ?? '';
  const canManage = myRole === 'admin';
  const isOwner = normId(groupInfo?.created_by) === normId(user?.uid);
  const candidateFriends = friends.filter((f) => {
    const id = normId(f.user_id);
    if (!id) return false;
    if (members.some((m) => normId(m.user_id) === id)) return false;
    if (!memberSearch.trim()) return true;
    const q = memberSearch.toLowerCase();
    return (
      f.display_name.toLowerCase().includes(q) ||
      f.email?.toLowerCase().includes(q) ||
      f.short_id?.toLowerCase().includes(q)
    );
  });

  const reloadGroup = useCallback(async () => {
    const info = await fetchGroupInfo(conversationId);
    setGroupInfo(info);
    const ids = (info?.members ?? []).map((m) => normId(m.user_id)).filter(Boolean);
    const profiles = ids.length > 0 ? await fetchUserProfilesBatch(ids) : {};
    setMemberProfiles(profiles);
    await loadConversations();
  }, [conversationId, loadConversations]);

  const handleSaveGroupInfo = useCallback(async () => {
    setSaving(true);
    try {
      await updateGroupInfo(conversationId, { title: editTitle.trim() });
      await reloadGroup();
      setShowEditModal(false);
    } catch (e) {
      console.error('[GroupSidebar] update group failed:', e);
    } finally {
      setSaving(false);
    }
  }, [conversationId, editTitle, reloadGroup]);

  const handleAddMembers = useCallback(async () => {
    if (addingIds.size === 0) return;
    setSaving(true);
    try {
      await addGroupMembers(conversationId, Array.from(addingIds));
      await reloadGroup();
      setAddingIds(new Set());
      setMemberSearch('');
      setShowAddModal(false);
    } catch (e) {
      console.error('[GroupSidebar] add members failed:', e);
    } finally {
      setSaving(false);
    }
  }, [addingIds, conversationId, reloadGroup]);

  const handleRemoveMember = useCallback(async (userId: string) => {
    setSaving(true);
    try {
      await removeGroupMember(conversationId, userId);
      await reloadGroup();
    } catch (e) {
      console.error('[GroupSidebar] remove member failed:', e);
    } finally {
      setSaving(false);
    }
  }, [conversationId, reloadGroup]);

  const handleToggleAdmin = useCallback(async (userId: string, nextRole: 'admin' | 'member') => {
    setSaving(true);
    try {
      await updateGroupMemberRole(conversationId, userId, nextRole);
      await reloadGroup();
    } catch (e) {
      console.error('[GroupSidebar] update member role failed:', e);
    } finally {
      setSaving(false);
    }
  }, [conversationId, reloadGroup]);

  const openMemberActions = useCallback((member: GroupInfo['members'][number]) => {
    if (!canManage || member.user_id === user?.uid) return;
    setMemberActionTarget(member);
  }, [canManage, user?.uid]);

  const handleDissolve = useCallback(async () => {
    setSaving(true);
    try {
      await dissolveGroup(conversationId);
      await loadConversations();
      setActiveConversation(null);
      router.replace('/(tabs)/messages' as any);
    } catch (e) {
      console.error('[GroupSidebar] dissolve group failed:', e);
    } finally {
      setSaving(false);
    }
  }, [conversationId, loadConversations, setActiveConversation, router]);

  return (
    <View style={styles.traderPanel}>
      <ScrollView showsVerticalScrollIndicator={false}>
        <View style={styles.traderHeader}>
          <AvatarCircle name={title} size={72} badge="GROUP" />
          <Text style={styles.traderName}>{title}</Text>
          {loading ? (
            <ActivityIndicator size="small" color={Colors.primary} style={{ marginTop: 12 }} />
          ) : (
            <>
              <Text style={styles.traderHandle}>成员数: {groupInfo?.member_count ?? members.length}</Text>
              {groupInfo?.announcement ? (
                <Text style={[styles.traderHandle, styles.groupAnnouncement]} numberOfLines={3}>
                  {groupInfo.announcement}
                </Text>
              ) : (
                <Text style={styles.traderHandle}>暂无群公告</Text>
              )}
              {canManage && (
                <View style={styles.groupAdminPills}>
                  <Text style={styles.traderBadge}>{isOwner ? '群主' : '群管理员'}</Text>
                </View>
              )}
            </>
          )}
        </View>

        {canManage && (
          <View style={styles.groupActionsRow}>
            <TouchableOpacity
              style={[styles.groupActionBtn, saving && styles.groupActionBtnDisabled]}
              activeOpacity={0.8}
              disabled={saving}
              onPress={() => {
                setEditTitle(title);
                setShowEditModal(true);
              }}
            >
              <Text style={styles.groupActionBtnText}>编辑群信息</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.groupActionBtn, saving && styles.groupActionBtnDisabled]}
              activeOpacity={0.8}
              disabled={saving}
              onPress={() => setShowAddModal(true)}
            >
              <Text style={styles.groupActionBtnText}>添加成员</Text>
            </TouchableOpacity>
          </View>
        )}

        <View style={styles.traderSection}>
          <Text style={styles.traderSectionTitle}>群成员</Text>
          {canManage && (
            <Text style={styles.groupManageHint}>
              {isOwner ? '右键、长按或点 ⋯ 管理成员与管理员权限' : '右键、长按或点 ⋯ 管理成员'}
            </Text>
          )}
          {members.length === 0 ? (
            <Text style={styles.traderAbout}>暂无成员信息</Text>
          ) : (
            members.map((member) => {
              const profile = memberProfiles[member.user_id];
              const name = member.display_name || profile?.display_name || member.user_id;
              const isMemberOwner = normId(member.user_id) === normId(groupInfo?.created_by);
              const roleLabel = isMemberOwner ? '群主' : member.role === 'admin' ? '管理员' : '成员';
              const sub = member.short_id || profile?.short_id || '';
              const canOpenActions = canManage && member.user_id !== user?.uid;
              return (
                <View
                  key={member.user_id}
                  style={styles.groupMemberRow}
                  {...(Platform.OS === 'web'
                    ? {
                        onContextMenu: (event: any) => {
                          event.preventDefault?.();
                          if (canOpenActions) openMemberActions(member);
                        },
                      }
                    : {})}
                >
                  <AvatarCircle name={name} size={36} />
                  <View style={styles.groupMemberBody}>
                    <Text style={styles.groupMemberName} numberOfLines={1}>{name}</Text>
                    <Text style={styles.groupMemberSub} numberOfLines={1}>
                      {sub ? `${sub} · ${roleLabel}` : roleLabel}
                    </Text>
                  </View>
                  <View style={styles.groupMemberActions}>
                    {canOpenActions && (
                      <TouchableOpacity
                        style={[styles.groupMenuBtn, saving && styles.groupActionBtnDisabled]}
                        activeOpacity={0.8}
                        disabled={saving}
                        onLongPress={() => openMemberActions(member)}
                        onPress={() => openMemberActions(member)}
                      >
                        <Text style={styles.groupMenuBtnText}>⋯</Text>
                      </TouchableOpacity>
                    )}
                  </View>
                </View>
              );
            })
          )}
        </View>

        {canManage && (
          <TouchableOpacity
            style={[styles.viewProfileBtn, styles.unfollowSidebarBtn, { marginTop: 0 }]}
            activeOpacity={0.8}
            disabled={saving}
            onPress={handleDissolve}
          >
            <Text style={[styles.viewProfileText, styles.unfollowSidebarBtnText]}>解散群</Text>
          </TouchableOpacity>
        )}
      </ScrollView>

      <Modal visible={showEditModal} transparent animationType="fade" onRequestClose={() => setShowEditModal(false)}>
        <View style={modalStyles.overlay}>
          <View style={[modalStyles.container, { maxWidth: 360 }]}>
            <View style={modalStyles.header}>
              <Text style={modalStyles.title}>编辑群信息</Text>
              <TouchableOpacity onPress={() => setShowEditModal(false)}>
                <Text style={modalStyles.closeBtn}>✕</Text>
              </TouchableOpacity>
            </View>
            <View style={modalStyles.fieldGroup}>
              <Text style={modalStyles.fieldLabel}>群名称</Text>
              <TextInput
                style={modalStyles.fieldInput}
                value={editTitle}
                onChangeText={setEditTitle}
                placeholder="输入群名称"
                placeholderTextColor={Colors.textMuted}
              />
            </View>
            <View style={modalStyles.footer}>
              <TouchableOpacity
                style={[modalStyles.createBtn, saving && modalStyles.createBtnDisabled]}
                activeOpacity={0.8}
                disabled={saving || !editTitle.trim()}
                onPress={handleSaveGroupInfo}
              >
                <Text style={modalStyles.createBtnText}>保存</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal visible={showAddModal} transparent animationType="fade" onRequestClose={() => setShowAddModal(false)}>
        <View style={modalStyles.overlay}>
          <View style={[modalStyles.container, { maxWidth: 420 }]}>
            <View style={modalStyles.header}>
              <Text style={modalStyles.title}>添加群成员</Text>
              <TouchableOpacity onPress={() => setShowAddModal(false)}>
                <Text style={modalStyles.closeBtn}>✕</Text>
              </TouchableOpacity>
            </View>
            <View style={[modalStyles.searchBox, { marginHorizontal: 20, marginTop: 12, marginBottom: 8 }]}>
              <Text style={{ fontSize: 14, marginRight: 8 }}>🔍</Text>
              <TextInput
                style={modalStyles.searchInput}
                placeholder="搜索好友..."
                placeholderTextColor={Colors.textMuted}
                value={memberSearch}
                onChangeText={setMemberSearch}
              />
            </View>
            <ScrollView style={modalStyles.list} showsVerticalScrollIndicator={false}>
              {candidateFriends.map((f) => {
                const selected = addingIds.has(f.user_id);
                return (
                  <TouchableOpacity
                    key={f.user_id}
                    style={modalStyles.userRow}
                    activeOpacity={0.8}
                    onPress={() =>
                      setAddingIds((prev) => {
                        const next = new Set(prev);
                        if (next.has(f.user_id)) next.delete(f.user_id);
                        else next.add(f.user_id);
                        return next;
                      })
                    }
                  >
                    <View style={[modalStyles.checkbox, selected && modalStyles.checkboxSelected]}>
                      {selected && <Text style={modalStyles.checkmark}>✓</Text>}
                    </View>
                    <AvatarCircle name={f.display_name} size={36} />
                    <View style={{ flex: 1 }}>
                      <Text style={modalStyles.userName}>{f.display_name}</Text>
                      <Text style={modalStyles.userSub}>{f.short_id ? `ID: ${f.short_id}` : f.email || ''}</Text>
                    </View>
                  </TouchableOpacity>
                );
              })}
            </ScrollView>
            <View style={modalStyles.footer}>
              <TouchableOpacity
                style={[modalStyles.createBtn, (saving || addingIds.size === 0) && modalStyles.createBtnDisabled]}
                activeOpacity={0.8}
                disabled={saving || addingIds.size === 0}
                onPress={handleAddMembers}
              >
                <Text style={modalStyles.createBtnText}>添加成员 ({addingIds.size})</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal
        visible={!!memberActionTarget}
        transparent
        animationType="fade"
        onRequestClose={() => setMemberActionTarget(null)}
      >
        <View style={modalStyles.overlay}>
          <View style={[modalStyles.container, { maxWidth: 360 }]}>
            <View style={modalStyles.header}>
              <Text style={modalStyles.title}>成员管理</Text>
              <TouchableOpacity onPress={() => setMemberActionTarget(null)}>
                <Text style={modalStyles.closeBtn}>✕</Text>
              </TouchableOpacity>
            </View>
            <View style={modalStyles.fieldGroup}>
              <Text style={modalStyles.fieldLabel}>成员</Text>
              <Text style={styles.memberManageName}>
                {memberActionTarget
                  ? (memberActionTarget.display_name || memberProfiles[memberActionTarget.user_id]?.display_name || memberActionTarget.user_id)
                  : ''}
              </Text>
              <Text style={styles.memberManageSub}>
                {memberActionTarget
                  ? ((memberActionTarget.short_id || memberProfiles[memberActionTarget.user_id]?.short_id || '') +
                    `${memberActionTarget.role ? ` · ${memberActionTarget.role === 'admin' ? '管理员' : '成员'}` : ''}`)
                  : ''}
              </Text>
            </View>
            <View style={styles.memberActionList}>
              {memberActionTarget && isOwner && normId(memberActionTarget.user_id) !== normId(groupInfo?.created_by) && (
                <TouchableOpacity
                  style={[styles.memberActionBtn, saving && styles.groupActionBtnDisabled]}
                  activeOpacity={0.85}
                  disabled={saving}
                  onPress={async () => {
                    await handleToggleAdmin(
                      memberActionTarget.user_id,
                      memberActionTarget.role === 'admin' ? 'member' : 'admin',
                    );
                    setMemberActionTarget(null);
                  }}
                >
                  <Text style={styles.memberActionBtnText}>
                    {memberActionTarget.role === 'admin' ? '取消管理员' : '设为管理员'}
                  </Text>
                </TouchableOpacity>
              )}
              {memberActionTarget && canManage && (
                <TouchableOpacity
                  style={[styles.memberActionBtn, styles.memberDangerBtn, saving && styles.groupActionBtnDisabled]}
                  activeOpacity={0.85}
                  disabled={saving}
                  onPress={async () => {
                    await handleRemoveMember(memberActionTarget.user_id);
                    setMemberActionTarget(null);
                  }}
                >
                  <Text style={[styles.memberActionBtnText, styles.memberDangerBtnText]}>移除成员</Text>
                </TouchableOpacity>
              )}
            </View>
          </View>
        </View>
      </Modal>
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
    currentCall,
    incomingCall,
    pending: callPending,
    startVoiceCall,
    acceptIncomingCall,
    rejectIncomingCall,
    endCurrentCall,
    handleCallEvent,
  } = useCallStore();

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

  useEffect(() => {
    const onCall = (payload: any) => {
      handleCallEvent(payload);
    };
    chatWs.onCallEvent(onCall);
    return () => {
      chatWs.offCallEvent(onCall);
    };
  }, [handleCallEvent]);

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
    sendMessage({ content: text, messageType: 'text' });
  };

  const handleSendImage = useCallback(async (file: File) => {
    const uploaded = await uploadMessageAsset(file);
    const absoluteUrl = uploaded.url.startsWith('http')
      ? uploaded.url
      : `${Config.MESSAGES_API_BASE_URL}${uploaded.url}`;
    await sendMessage({
      content: file.name || '图片',
      messageType: 'image',
      mediaUrl: absoluteUrl,
      metadata: {
        filename: file.name,
        size: file.size,
        mime_type: file.type,
      },
    });
  }, [sendMessage]);

  const handleSendStrategy = useCallback(async (strategy: TraderStrategy) => {
    await sendMessage({
      content: strategy.title,
      messageType: 'teacher_share',
      metadata: {
        strategy_id: strategy.id,
        title: strategy.title,
        summary: strategy.summary,
        cover_image: strategy.cover_image,
        category: strategy.category,
        author_id: strategy.author_id,
      },
    });
  }, [sendMessage]);

  const handleStartVoiceCall = useCallback(async () => {
    if (!activeConversationId || !activeConvo) return;
    try {
      await startVoiceCall(activeConversationId, activeConvo.name);
      const latestCallId = useCallStore.getState().currentCall?.id;
      if (latestCallId) {
        router.push(`/call/${latestCallId}` as any);
      }
    } catch (e: any) {
      Alert.alert('发起失败', e?.response?.data?.error || e?.message || '语音呼叫发起失败');
    }
  }, [activeConversationId, activeConvo, startVoiceCall, router]);

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
      <Modal visible={!!incomingCall} transparent animationType="fade" onRequestClose={() => void rejectIncomingCall()}>
        <View style={styles.callOverlay}>
          <View style={styles.callCard}>
            <Text style={styles.callCardEyebrow}>来电</Text>
            <Text style={styles.callCardTitle}>语音通话邀请</Text>
            <Text style={styles.callCardSub}>会话 ID: {incomingCall?.conversation_id || '--'}</Text>
            <View style={styles.callActionRow}>
              <TouchableOpacity
                style={[styles.callBtn, styles.callRejectBtn, callPending && styles.groupActionBtnDisabled]}
                activeOpacity={0.85}
                disabled={callPending}
                onPress={() => void rejectIncomingCall()}
              >
                <Text style={styles.callRejectText}>拒绝</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.callBtn, styles.callAcceptBtn, callPending && styles.groupActionBtnDisabled]}
                activeOpacity={0.85}
                disabled={callPending}
                onPress={async () => {
                  await acceptIncomingCall();
                  const latestCallId = useCallStore.getState().currentCall?.id;
                  if (latestCallId) {
                    router.push(`/call/${latestCallId}` as any);
                  }
                }}
              >
                <Text style={styles.callAcceptText}>接听</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      {currentCall && (
        <View style={styles.callBanner}>
          <View>
            <Text style={styles.callBannerTitle}>
              {currentCall.status === 'active' ? '语音通话中' : '语音呼叫中'}
            </Text>
            <Text style={styles.callBannerSub}>
              房间: {currentCall.room_name}
            </Text>
          </View>
          <View style={styles.callBannerActions}>
            <TouchableOpacity style={styles.callBannerOpenBtn} activeOpacity={0.85} onPress={() => router.push(`/call/${currentCall.id}` as any)}>
              <Text style={styles.callBannerOpenText}>进入通话</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.callBannerEndBtn} activeOpacity={0.85} onPress={() => void endCurrentCall()}>
              <Text style={styles.callBannerEndText}>挂断</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

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
          onSendImage={handleSendImage}
          onSendStrategy={handleSendStrategy}
          loading={messagesLoading}
          onLoadMore={loadMoreMessages}
          hasMore={hasMoreMessages}
          peerUserId={activeConvo.peerUserId ?? activePeerId}
          onOpenTrader={(uid) => router.push(`/trader/${uid}` as any)}
          canSendStrategy={!!user?.isTrader}
          chatWsConnected={chatWsConnected}
          onStartVoiceCall={handleStartVoiceCall}
          callPending={callPending}
          activeCallStatus={
            currentCall && currentCall.conversation_id === activeConversationId ? currentCall.status : null
          }
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

      {/* Group Sidebar (desktop, group conversations) */}
      {isDesktop && activeConvo?.isGroup && activeConversationId && (
        <GroupSidebar
          conversationId={activeConversationId}
          fallbackTitle={activeConvo.name}
        />
      )}

      {/* Peer Sidebar (XL desktop, direct conversations) */}
      {isXL && !activeConvo?.isGroup && activePeerProfile && activePeerId && (
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
  strategyCardCover: {
    width: '100%',
    height: 132,
    borderTopLeftRadius: 12,
    borderTopRightRadius: 12,
    marginBottom: 10,
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
  strategyCardSummary: {
    marginTop: 8,
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
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
  chatImageBubble: {
    width: 220,
    height: 220,
    borderRadius: 18,
    backgroundColor: Colors.surfaceAlt,
  },
  strategyPickerItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  strategyPickerThumb: {
    width: 64,
    height: 64,
    borderRadius: 12,
    backgroundColor: Colors.surfaceAlt,
  },
  strategyPickerTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  strategyPickerSummary: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 4,
  },
  strategyPickerAction: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  imagePreviewOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.92)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  imagePreviewImage: {
    width: '100%',
    height: '100%',
    maxWidth: 980,
    maxHeight: 760,
  },
  imagePreviewClose: {
    position: 'absolute',
    top: 24,
    right: 24,
    zIndex: 10,
    width: 40,
    height: 40,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  imagePreviewCloseText: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
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
  callOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  callCard: {
    width: '100%',
    maxWidth: 380,
    backgroundColor: Colors.surface,
    borderRadius: 24,
    padding: 24,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  callCardEyebrow: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  callCardTitle: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    marginTop: 10,
  },
  callCardSub: {
    color: Colors.textMuted,
    fontSize: 13,
    marginTop: 10,
  },
  callActionRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 22,
  },
  callBtn: {
    flex: 1,
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
  },
  callRejectBtn: {
    backgroundColor: 'rgba(198, 40, 40, 0.12)',
    borderColor: 'rgba(198, 40, 40, 0.24)',
  },
  callAcceptBtn: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  callRejectText: {
    color: Colors.down,
    fontSize: 14,
    fontWeight: '700',
  },
  callAcceptText: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '700',
  },
  callBanner: {
    position: 'absolute',
    top: 14,
    left: 14,
    right: 14,
    zIndex: 30,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: Colors.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  callBannerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  callBannerTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  callBannerSub: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 4,
  },
  callBannerEndBtn: {
    backgroundColor: 'rgba(198, 40, 40, 0.12)',
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(198, 40, 40, 0.24)',
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  callBannerOpenBtn: {
    backgroundColor: Colors.primaryDim,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  callBannerOpenText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  callBannerEndText: {
    color: Colors.down,
    fontSize: 12,
    fontWeight: '700',
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
  traderMetaPills: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 12,
    flexWrap: 'wrap',
    justifyContent: 'center',
  },
  traderMetaPill: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  traderMetaPillText: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
  },
  traderMetaPillActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  traderMetaPillActiveText: {
    color: Colors.primary,
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
  traderCurveWrap: {
    paddingHorizontal: 12,
    paddingTop: 12,
    paddingBottom: 4,
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
  groupManageHint: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
    marginBottom: 12,
  },
  groupAnnouncement: {
    textAlign: 'center',
    marginTop: 10,
    lineHeight: 18,
    paddingHorizontal: 16,
  },
  groupAdminPills: {
    marginTop: 12,
  },
  groupActionsRow: {
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  groupActionBtn: {
    flex: 1,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 10,
  },
  groupActionBtnDisabled: {
    opacity: 0.5,
  },
  groupActionBtnText: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '700',
  },
  groupMemberRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  groupMemberBody: {
    flex: 1,
    minWidth: 0,
  },
  groupMemberName: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  groupMemberSub: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 2,
  },
  groupMemberActions: {
    alignItems: 'flex-end',
    gap: 6,
  },
  groupMenuBtn: {
    width: 32,
    height: 32,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  groupMenuBtnText: {
    color: Colors.textSecondary,
    fontSize: 20,
    fontWeight: '700',
    lineHeight: 20,
    marginTop: -3,
  },
  groupRoleBtn: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: 'rgba(212, 178, 75, 0.12)',
    borderWidth: 1,
    borderColor: 'rgba(212, 178, 75, 0.28)',
  },
  groupRoleBtnText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '700',
  },
  groupRemoveBtn: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: 'rgba(198, 40, 40, 0.1)',
    borderWidth: 1,
    borderColor: 'rgba(198, 40, 40, 0.25)',
  },
  groupRemoveBtnText: {
    color: Colors.down,
    fontSize: 11,
    fontWeight: '700',
  },
  memberManageName: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
    marginTop: 2,
  },
  memberManageSub: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 6,
  },
  memberActionList: {
    paddingHorizontal: 20,
    paddingBottom: 20,
    gap: 10,
  },
  memberActionBtn: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingVertical: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  memberActionBtnText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  memberDangerBtn: {
    backgroundColor: 'rgba(198, 40, 40, 0.08)',
    borderColor: 'rgba(198, 40, 40, 0.22)',
  },
  memberDangerBtnText: {
    color: Colors.down,
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
  followSidebarBtn: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  followSidebarBtnText: {
    color: Colors.background,
  },
  unfollowSidebarBtn: {
    backgroundColor: 'rgba(198, 40, 40, 0.1)',
    borderColor: 'rgba(198, 40, 40, 0.3)',
  },
  unfollowSidebarBtnText: {
    color: Colors.down,
  },
  disabledSidebarBtn: {
    backgroundColor: Colors.surfaceAlt,
    borderColor: Colors.border,
  },
  disabledSidebarBtnText: {
    color: Colors.textMuted,
  },
  secondarySidebarBtn: {
    backgroundColor: Colors.surfaceAlt,
    borderColor: Colors.border,
  },
  secondarySidebarBtnText: {
    color: Colors.textSecondary,
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
  groupHero: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 8,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  groupHeroTitle: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
  },
  groupHeroSub: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
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
  fieldLabelRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  fieldLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
  },
  fieldCounter: {
    color: Colors.textMuted,
    fontSize: 11,
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
  helperText: {
    marginTop: 8,
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 17,
  },
  selectedSection: {
    paddingTop: 4,
  },
  selectedChips: {
    paddingHorizontal: 20,
    gap: 8,
    paddingBottom: 4,
  },
  selectedChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: Colors.primaryDim,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  selectedChipText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  selectedChipRemove: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '700',
  },
  presetGrid: {
    gap: 10,
  },
  presetCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 12,
    gap: 4,
  },
  presetCardActive: {
    borderColor: Colors.primary,
    backgroundColor: Colors.primaryDim,
  },
  presetTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  presetTitleActive: {
    color: Colors.primary,
  },
  presetMeta: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  presetNote: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 17,
  },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 10,
  },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 999,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  chipActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  chipText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  chipTextActive: {
    color: Colors.primary,
  },
  summaryCard: {
    marginTop: 4,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 12,
    gap: 8,
  },
  summaryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
  },
  summaryLabel: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  summaryValue: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '700',
  },
  summaryHint: {
    marginTop: 4,
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 17,
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
