import { useState, useCallback, useMemo, useEffect, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  Pressable,
  ScrollView,
  StyleSheet,
  useWindowDimensions,
  ActivityIndicator,
  Platform,
  Alert,
  Image,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { CameraView, useCameraPermissions } from 'expo-camera';
import QRCode from 'react-native-qrcode-svg';
import { Colors, Sizes } from '../theme/colors';
import { Config } from '../services/config';
import { useAuthStore } from '../services/store/authStore';
import { useMessagesStore } from '../services/store/messagesStore';
import apiClient from '../services/api/client';
import {
  searchUsers,
  sendFriendRequest,
  fetchOutgoingFriendRequests,
  createDirectConversation,
  type FriendProfile,
} from '../services/api/messagesApi';

/* ════════════════════════════════════════
   Teacher type (lightweight)
   ════════════════════════════════════════ */

interface RecommendedTrader {
  user_id: string;
  display_name: string;
  avatar_url?: string;
  title?: string;
  signature?: string;
  total_pnl?: number;
  win_rate?: number;
}

const MOCK_TRADERS: RecommendedTrader[] = [
  { user_id: 'mock-1', display_name: 'Alex Chen', signature: '量化策略 · 美股日内', total_pnl: 34.2, win_rate: 0.72 },
  { user_id: 'mock-2', display_name: 'Sarah Wang', signature: '期权价差专家', total_pnl: 21.8, win_rate: 0.65 },
  { user_id: 'mock-3', display_name: 'Mike Liu', signature: '加密货币趋势交易', total_pnl: -5.3, win_rate: 0.48 },
  { user_id: 'mock-4', display_name: 'Jessica Li', signature: '外汇短线 · EA 策略', total_pnl: 15.6, win_rate: 0.61 },
  { user_id: 'mock-5', display_name: 'David Zhou', signature: 'A股价值投资', total_pnl: 42.1, win_rate: 0.78 },
  { user_id: 'mock-6', display_name: 'Emma Xu', signature: '期货套利 · 风控优先', total_pnl: 8.9, win_rate: 0.58 },
];

/* ════════════════════════════════════════
   Types
   ════════════════════════════════════════ */

type SearchTab = 'email' | 'id' | 'qrcode';

const TABS: { key: SearchTab; icon: string; label: string }[] = [
  { key: 'email', icon: '✉️', label: '邮箱' },
  { key: 'id', icon: '🔑', label: '账号ID' },
  { key: 'qrcode', icon: '⊞', label: '二维码' },
];

function normId(s: string | undefined | null): string {
  return String(s ?? '').trim();
}

/* ════════════════════════════════════════
   Avatar Helper
   ════════════════════════════════════════ */

function AvatarCircle({ name, size = 48, imageUrl }: { name: string; size?: number; imageUrl?: string | null }) {
  const letter = (name || '?').charAt(0).toUpperCase();
  const hue = name.split('').reduce((a, c) => a + c.charCodeAt(0), 0) % 360;
  const bg = `hsl(${hue}, 40%, 25%)`;
  const fg = `hsl(${hue}, 60%, 75%)`;
  const resolvedUrl = imageUrl && imageUrl.startsWith('/') ? `${Config.API_BASE_URL}${imageUrl}` : imageUrl;

  if (resolvedUrl) {
    return (
      <Image
        source={{ uri: resolvedUrl }}
        style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: bg }}
      />
    );
  }

  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: bg,
        justifyContent: 'center',
        alignItems: 'center',
      }}
    >
      <Text style={{ color: fg, fontSize: size * 0.4, fontWeight: '700' }}>{letter}</Text>
    </View>
  );
}

/* ════════════════════════════════════════
   Sub: QR Code Tab Content
   ════════════════════════════════════════ */

function QRCodeTab({
  user,
  onScanned,
}: {
  user: { uid: string; displayName: string | null; email: string | null; shortId?: string };
  onScanned: (uid: string) => void;
}) {
  const [qrMode, setQRMode] = useState<'my' | 'scan'>('my');
  const [permission, requestPermission] = useCameraPermissions();
  const [scanned, setScanned] = useState(false);

  const qrValue = JSON.stringify({
    type: 'tongxin_user',
    uid: user.uid,
    name: user.displayName || '',
    short_id: user.shortId || '',
  });

  const handleBarCodeScanned = useCallback(
    ({ data }: { data: string }) => {
      if (scanned) return;
      setScanned(true);
      try {
        const parsed = JSON.parse(data);
        if (parsed.type === 'tongxin_user' && parsed.uid) {
          onScanned(parsed.uid);
          return;
        }
      } catch {
        // not valid
      }
      Alert.alert('无法识别', '不是有效的通心用户二维码');
      setTimeout(() => setScanned(false), 2000);
    },
    [scanned, onScanned],
  );

  return (
    <View style={{ flex: 1 }}>
      {/* My QR / Scan toggle */}
      <View style={s.qrToggleRow}>
        <TouchableOpacity
          style={[s.qrToggleBtn, qrMode === 'my' && s.qrToggleBtnActive]}
          onPress={() => { setQRMode('my'); setScanned(false); }}
          activeOpacity={0.7}
        >
          <Text style={[s.qrToggleText, qrMode === 'my' && s.qrToggleTextActive]}>
            我的二维码
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[s.qrToggleBtn, qrMode === 'scan' && s.qrToggleBtnActive]}
          onPress={() => { setQRMode('scan'); setScanned(false); }}
          activeOpacity={0.7}
        >
          <Text style={[s.qrToggleText, qrMode === 'scan' && s.qrToggleTextActive]}>
            扫一扫
          </Text>
        </TouchableOpacity>
      </View>

      {qrMode === 'my' ? (
        /* ── My QR Code ── */
        <View style={s.qrMyWrap}>
          <AvatarCircle name={user.displayName || 'U'} size={64} imageUrl={user.photoURL} />
          <Text style={s.qrMyName}>{user.displayName || 'User'}</Text>
          <Text style={s.qrMyId}>UID: {user.uid}</Text>
          <View style={s.qrCodeContainer}>
            <QRCode value={qrValue} size={180} backgroundColor="white" color="#1a1a1a" />
          </View>
          <Text style={s.qrMyHint}>扫一扫上面的二维码，加我为好友</Text>
        </View>
      ) : (
        /* ── Scanner ── */
        <View style={{ flex: 1, minHeight: 300 }}>
          {Platform.OS === 'web' ? (
            <View style={s.qrWebFallback}>
              <Text style={{ fontSize: 48 }}>📷</Text>
              <Text style={s.qrWebText}>扫码功能需在移动设备上使用</Text>
              <Text style={s.qrWebSubText}>请使用手机 App 扫描二维码添加好友</Text>
            </View>
          ) : !permission?.granted ? (
            <View style={s.qrWebFallback}>
              <Text style={{ color: '#fff', fontSize: 15 }}>需要相机权限才能扫描</Text>
              <TouchableOpacity style={s.permBtn} onPress={requestPermission} activeOpacity={0.8}>
                <Text style={{ color: Colors.background, fontWeight: '700' }}>授权相机</Text>
              </TouchableOpacity>
            </View>
          ) : (
            <CameraView
              style={{ flex: 1, borderRadius: 12, overflow: 'hidden' }}
              barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
              onBarcodeScanned={scanned ? undefined : handleBarCodeScanned}
            >
              <View style={s.scanOverlay}>
                <View style={s.scanFrame}>
                  <View style={[s.corner, s.cornerTL]} />
                  <View style={[s.corner, s.cornerTR]} />
                  <View style={[s.corner, s.cornerBL]} />
                  <View style={[s.corner, s.cornerBR]} />
                </View>
                <Text style={s.scanHint}>将二维码放入框内即可自动扫描</Text>
              </View>
            </CameraView>
          )}
        </View>
      )}
    </View>
  );
}

/* ════════════════════════════════════════
   Main Page
   ════════════════════════════════════════ */

export default function AddFriendPage() {
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;
  const router = useRouter();
  const { t } = useTranslation();
  const { user } = useAuthStore();
  const { friends, loadFriends, loadFriendRequests } = useMessagesStore();
  const sendLockRef = useRef(false);

  const [activeTab, setActiveTab] = useState<SearchTab>('email');
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<FriendProfile[]>([]);
  const [searching, setSearching] = useState(false);
  /** 已发起过申请的目标用户 id（Object 比 Set 更易触发 React 重绘） */
  const [requestSentMap, setRequestSentMap] = useState<Record<string, boolean>>({});
  const [sendingId, setSendingId] = useState<string | null>(null);
  const [creating, setCreating] = useState<string | null>(null);
  const [recommendedTraders, setRecommendedTraders] = useState<RecommendedTrader[]>([]);

  useEffect(() => {
    if (!user) return;
    loadFriends();
    fetchOutgoingFriendRequests()
      .then((out) => {
        setRequestSentMap((prev) => {
          const next = { ...prev };
          out.forEach((r) => {
            const k = normId(r.to_user_id);
            if (k) next[k] = true;
          });
          return next;
        });
      })
      .catch(() => {});
    // Fetch recommended traders (fallback to mock if API unavailable)
    apiClient
      .get('/api/teachers', { params: { limit: 6 } })
      .then(({ data }) => {
        const list = Array.isArray(data) && data.length > 0 ? data : MOCK_TRADERS;
        setRecommendedTraders(list);
      })
      .catch(() => setRecommendedTraders(MOCK_TRADERS));
  }, [user?.uid]);

  const placeholder = useMemo(() => {
    if (activeTab === 'email') return '输入好友的电子邮箱地址...';
    if (activeTab === 'id') return '输入好友的账号 ID...';
    return '';
  }, [activeTab]);

  const handleSearch = useCallback(async () => {
    const q = searchQuery.trim();
    if (q.length < 2) return;
    setSearching(true);
    try {
      const results = await searchUsers(q);
      setSearchResults(results.filter((r) => !!normId(r.user_id)));
    } catch (e) {
      console.error('[AddFriend] search failed:', e);
      setSearchResults([]);
      Alert.alert(t('contacts.errorTitle'), t('contacts.actionFailed'));
    } finally {
      setSearching(false);
    }
  }, [searchQuery, friends, user?.uid, t]);

  const handleSendRequest = useCallback(
    (userId: string) => {
      const id = normId(userId);
      if (!id) {
        Alert.alert(t('contacts.errorTitle'), t('messages.addFriendInvalidUser'));
        return;
      }
      if (sendLockRef.current) return;
      sendLockRef.current = true;
      setSendingId(id);
      sendFriendRequest(id)
        .then(() => {
          setRequestSentMap((prev) => ({ ...prev, [id]: true }));
          void loadFriendRequests();
        })
        .catch((e) => {
          console.error('[AddFriend] send request failed:', e);
          Alert.alert(t('contacts.errorTitle'), t('messages.addFriendSendFailed'));
        })
        .finally(() => {
          sendLockRef.current = false;
          setSendingId(null);
        });
    },
    [t, loadFriendRequests],
  );

  const handleStartChat = useCallback(
    async (friendId: string) => {
      setCreating(friendId);
      try {
        const result = await createDirectConversation(friendId);
        router.replace({ pathname: '/(tabs)/messages', params: { conversationId: result.id } } as any);
      } catch (e) {
        console.error('[AddFriend] create conversation failed:', e);
      } finally {
        setCreating(null);
      }
    },
    [router],
  );

  const handleQRScanned = useCallback(
    async (uid: string) => {
      try {
        const result = await createDirectConversation(uid);
        router.replace({ pathname: '/(tabs)/messages', params: { conversationId: result.id } } as any);
      } catch (e) {
        console.error('[AddFriend] QR scan create conversation failed:', e);
      }
    },
    [router],
  );

  // Not logged in — show page with recommended traders but disable search
  const isLoggedIn = !!user;

  // Filter friends by search locally
  const filteredFriends = friends.filter((f) => {
    if (!searchQuery.trim()) return false;
    const searchResultIds = new Set(searchResults.map((u) => normId(u.user_id)).filter(Boolean));
    if (searchResultIds.has(normId(f.user_id))) return false;
    const q = searchQuery.toLowerCase();
    return (
      f.display_name.toLowerCase().includes(q) ||
      f.email?.toLowerCase().includes(q) ||
      f.user_id?.toLowerCase().includes(q)
    );
  });

  return (
    <View style={s.root}>
      {/* Header with back button */}
      <View style={s.header}>
        <TouchableOpacity onPress={() => router.back()} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backArrow}>←</Text>
        </TouchableOpacity>
        <Text style={s.headerTitle}>添加好友</Text>
        <TouchableOpacity onPress={() => router.push('/contacts' as any)} style={s.headerRightLink} activeOpacity={0.7}>
          <Text style={s.headerRightLinkText}>{t('contacts.title')}</Text>
        </TouchableOpacity>
      </View>

      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={[s.scrollContent, isDesktop && { maxWidth: 640, alignSelf: 'center' as const, width: '100%' }]}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="always"
      >
        {/* Page Title */}
        <View style={s.titleSection}>
          <Text style={s.pageTitle}>添加好友</Text>
          <Text style={s.pageSubtitle}>搜索并添加 Sovereign 网络中的精英成员</Text>
        </View>

        {/* Tab Card */}
        <View style={s.card}>
          {/* Segmented Tabs */}
          <View style={s.tabRow}>
            {TABS.map((tab) => (
              <TouchableOpacity
                key={tab.key}
                style={[s.tab, activeTab === tab.key && s.tabActive]}
                onPress={() => { setActiveTab(tab.key); setSearchQuery(''); setSearchResults([]); }}
                activeOpacity={0.7}
              >
                <Text style={s.tabIcon}>{tab.icon}</Text>
                <Text style={[s.tabLabel, activeTab === tab.key && s.tabLabelActive]}>
                  {tab.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          {/* Content Area */}
          <View style={s.cardContent}>
            {activeTab === 'qrcode' ? (
              user ? (
                <QRCodeTab user={user} onScanned={handleQRScanned} />
              ) : (
                <View style={{ alignItems: 'center', padding: 40 }}>
                  <Text style={{ color: Colors.textMuted, fontSize: 14 }}>请先登录后使用二维码功能</Text>
                </View>
              )
            ) : !isLoggedIn ? (
              <View style={{ alignItems: 'center', padding: 40 }}>
                <Text style={{ color: Colors.textMuted, fontSize: 14 }}>请先登录后搜索好友</Text>
              </View>
            ) : (
              <>
                {/* Search Input */}
                <View style={s.fieldGroup}>
                  <Text style={s.fieldLabel}>SEARCH CREDENTIALS</Text>
                  <View style={s.inputWrap}>
                    <Text style={s.inputIcon}>🔍</Text>
                    <TextInput
                      style={s.input}
                      placeholder={placeholder}
                      placeholderTextColor={Colors.textMuted}
                      value={searchQuery}
                      onChangeText={setSearchQuery}
                      autoCapitalize="none"
                      autoCorrect={false}
                      onSubmitEditing={handleSearch}
                      keyboardType={activeTab === 'email' ? 'email-address' : 'default'}
                    />
                  </View>
                </View>

                {/* Search Button */}
                <TouchableOpacity
                  style={s.searchBtn}
                  onPress={handleSearch}
                  activeOpacity={0.85}
                  disabled={searching || searchQuery.trim().length < 2}
                >
                  {searching ? (
                    <ActivityIndicator color={Colors.background} size="small" />
                  ) : (
                    <>
                      <Text style={s.searchBtnIcon}>🔎</Text>
                      <Text style={s.searchBtnText}>搜索</Text>
                    </>
                  )}
                </TouchableOpacity>
              </>
            )}
          </View>
        </View>

        {/* Search Results */}
        {activeTab !== 'qrcode' && searchResults.length > 0 && (
          <View style={s.resultsSection}>
            <Text style={s.sectionLabel}>搜索结果</Text>
            {searchResults.map((u) => {
              const rowUid = normId(u.user_id);
              const isSelf = rowUid === normId(user?.uid);
              const isFriend = friends.some((f) => normId(f.user_id) === rowUid);
              return (
              <View key={rowUid || u.email || u.short_id} style={s.userCard}>
                <AvatarCircle name={u.display_name} size={48} imageUrl={u.avatar_url} />
                <View style={s.userCardBody} pointerEvents="box-none">
                  <Text style={s.userName} numberOfLines={1}>{u.display_name}</Text>
                  <Text style={s.userSub} numberOfLines={1}>{`UID: ${rowUid}`}</Text>
                </View>
                {sendingId === rowUid ? (
                  <ActivityIndicator size="small" color={Colors.primary} style={{ flexShrink: 0 }} />
                ) : isSelf ? (
                  <View style={s.selfBtn}>
                    <Text style={s.selfBtnText} numberOfLines={1}>你自己</Text>
                  </View>
                ) : isFriend ? (
                  <View style={s.addedBtn}>
                    <Text style={s.addedBtnText} numberOfLines={1}>已添加</Text>
                  </View>
                ) : requestSentMap[rowUid] ? (
                  <View style={s.waitingBtn}>
                    <Text style={s.waitingBtnText} numberOfLines={1}>
                      {t('messages.addFriendWaiting')}
                    </Text>
                  </View>
                ) : (
                  <Pressable
                    style={({ pressed }) => [
                      s.addBtn,
                      { zIndex: 10, elevation: 6 },
                      pressed && { opacity: 0.88 },
                    ]}
                    onPress={() => handleSendRequest(rowUid)}
                    hitSlop={{ top: 14, bottom: 14, left: 10, right: 10 }}
                  >
                    <Text style={s.addBtnText} numberOfLines={1}>+ 添加</Text>
                  </Pressable>
                )}
              </View>
            );})}
          </View>
        )}

        {/* Matched friends (existing) */}
        {activeTab !== 'qrcode' && filteredFriends.length > 0 && (
          <View style={s.resultsSection}>
            <Text style={s.sectionLabel}>已有好友</Text>
            {filteredFriends.map((f) => (
              <TouchableOpacity
                key={f.user_id}
                style={s.userCard}
                onPress={() => handleStartChat(f.user_id)}
                activeOpacity={0.7}
                disabled={creating === f.user_id}
              >
                <AvatarCircle name={f.display_name} size={48} imageUrl={f.avatar_url} />
                <View style={s.userCardBody}>
                  <Text style={s.userName} numberOfLines={1}>{f.display_name}</Text>
                  <Text style={s.userSub} numberOfLines={1}>
                    {`UID: ${f.user_id}`}
                  </Text>
                </View>
                {creating === f.user_id ? (
                  <ActivityIndicator size="small" color={Colors.primary} />
                ) : (
                  <Text style={{ fontSize: 20 }}>💬</Text>
                )}
              </TouchableOpacity>
            ))}
          </View>
        )}

        {/* No results */}
        {activeTab !== 'qrcode' && searching === false && searchQuery.trim().length >= 2 && searchResults.length === 0 && filteredFriends.length === 0 && (
          <View style={s.emptyState}>
            <Text style={s.emptyText}>未找到匹配的用户</Text>
          </View>
        )}

        {/* Recommended Traders — 2-column grid */}
        {recommendedTraders.length > 0 && (
          <View style={s.resultsSection}>
            <Text style={s.recSectionTitle}>推荐交易员</Text>
            <View style={s.recGrid}>
              {recommendedTraders.map((trader) => {
                const tid = normId(trader.user_id);
                return (
                <TouchableOpacity
                  key={tid || trader.display_name}
                  style={s.recCard}
                  activeOpacity={0.7}
                  onPress={() => handleSendRequest(tid)}
                  disabled={!tid || !!requestSentMap[tid] || sendingId !== null}
                >
                  <AvatarCircle name={trader.display_name} size={44} imageUrl={trader.avatar_url} />
                  <View style={{ flex: 1, gap: 2 }}>
                    <Text style={s.recName} numberOfLines={1}>{trader.display_name}</Text>
                    <Text style={s.recRole} numberOfLines={1}>
                      {trader.signature || trader.title || '交易员'}
                    </Text>
                  </View>
                  {sendingId === tid ? (
                    <ActivityIndicator size="small" color={Colors.primary} />
                  ) : requestSentMap[tid] ? (
                    <Text style={s.sentText}>{t('messages.addFriendWaiting')}</Text>
                  ) : (
                    <View style={s.addIconBtn}>
                      <Text style={s.addIconText}>+</Text>
                    </View>
                  )}
                </TouchableOpacity>
              );})}
            </View>
          </View>
        )}

        <View style={{ height: 40 }} />
      </ScrollView>
    </View>
  );
}

/* ════════════════════════════════════════
   Styles
   ════════════════════════════════════════ */

const s = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: Colors.background,
  },

  /* ── Header ── */
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingTop: Platform.OS === 'ios' ? 56 : 16,
    paddingBottom: 12,
    backgroundColor: Colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  backBtn: {
    width: 36,
    height: 36,
    justifyContent: 'center',
    alignItems: 'center',
  },
  backArrow: {
    color: Colors.textActive,
    fontSize: 22,
  },
  headerTitle: {
    color: Colors.textActive,
    fontSize: 17,
    fontWeight: '600',
  },
  headerRightLink: {
    minWidth: 48,
    paddingVertical: 4,
    paddingHorizontal: 4,
    alignItems: 'flex-end',
  },
  headerRightLinkText: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '600',
  },

  /* ── Title Section ── */
  scrollContent: {
    padding: 24,
    gap: 24,
  },
  titleSection: {
    alignItems: 'center',
    gap: 6,
    paddingVertical: 8,
  },
  pageTitle: {
    fontSize: 32,
    fontWeight: '800',
    color: Colors.textActive,
    letterSpacing: -0.5,
  },
  pageSubtitle: {
    color: Colors.textMuted,
    fontSize: 14,
  },

  /* ── Card ── */
  card: {
    backgroundColor: 'rgba(28, 27, 27, 0.6)',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.2)',
    overflow: 'hidden',
  },

  /* ── Tabs ── */
  tabRow: {
    flexDirection: 'row',
    padding: 4,
    gap: 4,
  },
  tab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 12,
    borderRadius: 10,
  },
  tabActive: {
    backgroundColor: '#2a2a2a',
  },
  tabIcon: {
    fontSize: 14,
  },
  tabLabel: {
    fontSize: 13,
    fontWeight: '500',
    color: Colors.textMuted,
  },
  tabLabelActive: {
    color: Colors.primaryLight,
    fontWeight: '600',
  },

  /* ── Card Content ── */
  cardContent: {
    padding: 24,
    gap: 20,
  },
  fieldGroup: {
    gap: 8,
  },
  fieldLabel: {
    fontSize: 10,
    fontWeight: '700',
    color: 'rgba(242, 202, 80, 0.5)',
    letterSpacing: 2,
    marginLeft: 2,
  },
  inputWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#0e0e0e',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.25)',
    paddingHorizontal: 14,
  },
  inputIcon: {
    fontSize: 16,
    marginRight: 10,
    opacity: 0.5,
  },
  input: {
    flex: 1,
    paddingVertical: 14,
    color: Colors.textActive,
    fontSize: 15,
  },

  /* ── Search Button ── */
  searchBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    paddingVertical: 16,
    borderRadius: 10,
    backgroundColor: Colors.primary,
  },
  searchBtnIcon: {
    fontSize: 18,
  },
  searchBtnText: {
    color: Colors.background,
    fontSize: 17,
    fontWeight: '700',
    letterSpacing: 0.5,
  },

  /* ── Results ── */
  resultsSection: {
    gap: 12,
  },
  sectionLabel: {
    fontSize: 11,
    fontWeight: '700',
    color: Colors.textMuted,
    letterSpacing: 1,
    marginLeft: 4,
  },
  userCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: 'rgba(32, 31, 31, 0.6)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.15)',
    padding: 16,
  },
  userCardBody: {
    flex: 1,
    gap: 2,
    minWidth: 0,
    marginRight: 4,
  },
  userName: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  userSub: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  addBtn: {
    flexShrink: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: 'rgba(212, 175, 55, 0.1)',
    borderWidth: 1,
    borderColor: 'rgba(212, 175, 55, 0.2)',
  },
  addBtnText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  sentText: {
    color: Colors.textMuted,
    fontSize: 12,
    flexShrink: 0,
  },
  waitingBtn: {
    flexShrink: 0,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: 'rgba(90, 90, 90, 0.35)',
    borderWidth: 1,
    borderColor: 'rgba(120, 120, 120, 0.4)',
  },
  waitingBtnText: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
  },
  addedBtn: {
    flexShrink: 0,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: 'rgba(100, 196, 132, 0.12)',
    borderWidth: 1,
    borderColor: 'rgba(100, 196, 132, 0.35)',
  },
  addedBtnText: {
    color: '#8dd3a4',
    fontSize: 12,
    fontWeight: '600',
  },
  selfBtn: {
    flexShrink: 0,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: 'rgba(116, 116, 140, 0.16)',
    borderWidth: 1,
    borderColor: 'rgba(136, 136, 166, 0.28)',
  },
  selfBtnText: {
    color: '#b4b7cb',
    fontSize: 12,
    fontWeight: '600',
  },
  emptyState: {
    padding: 40,
    alignItems: 'center',
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 14,
  },

  /* ── QR ── */
  qrToggleRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 20,
  },
  qrToggleBtn: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 8,
    alignItems: 'center',
    backgroundColor: 'rgba(14,14,14,0.4)',
  },
  qrToggleBtnActive: {
    backgroundColor: '#2a2a2a',
  },
  qrToggleText: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '500',
  },
  qrToggleTextActive: {
    color: Colors.primaryLight,
    fontWeight: '600',
  },
  qrMyWrap: {
    alignItems: 'center',
    gap: 8,
    paddingVertical: 8,
  },
  qrMyName: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
    marginTop: 4,
  },
  qrMyId: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  qrCodeContainer: {
    backgroundColor: '#fff',
    borderRadius: 16,
    padding: 16,
    marginTop: 16,
    marginBottom: 8,
  },
  qrMyHint: {
    color: Colors.textMuted,
    fontSize: 13,
    textAlign: 'center',
  },
  qrWebFallback: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 12,
    minHeight: 240,
  },
  qrWebText: {
    color: Colors.textSecondary,
    fontSize: 15,
    textAlign: 'center',
  },
  qrWebSubText: {
    color: Colors.textMuted,
    fontSize: 13,
    textAlign: 'center',
  },
  permBtn: {
    backgroundColor: Colors.primary,
    borderRadius: 10,
    paddingHorizontal: 24,
    paddingVertical: 12,
  },
  scanOverlay: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  scanFrame: {
    width: 220,
    height: 220,
    position: 'relative',
  },
  corner: {
    position: 'absolute',
    width: 28,
    height: 28,
    borderColor: Colors.primary,
  },
  cornerTL: {
    top: 0,
    left: 0,
    borderTopWidth: 3,
    borderLeftWidth: 3,
  },
  cornerTR: {
    top: 0,
    right: 0,
    borderTopWidth: 3,
    borderRightWidth: 3,
  },
  cornerBL: {
    bottom: 0,
    left: 0,
    borderBottomWidth: 3,
    borderLeftWidth: 3,
  },
  cornerBR: {
    bottom: 0,
    right: 0,
    borderBottomWidth: 3,
    borderRightWidth: 3,
  },
  scanHint: {
    color: '#fff',
    fontSize: 14,
    marginTop: 20,
    textAlign: 'center',
  },

  /* ── Recommended Traders (2-col grid) ── */
  recSectionTitle: {
    fontSize: 15,
    fontWeight: '700',
    color: Colors.textActive,
    letterSpacing: 0.3,
    marginLeft: 4,
  },
  recGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  recCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: 'rgba(32, 31, 31, 0.7)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.18)',
    padding: 12,
    width: '48.5%' as any,
  },
  recName: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  recRole: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  addIconBtn: {
    backgroundColor: 'rgba(212, 175, 55, 0.15)',
    borderRadius: 16,
    width: 32,
    height: 32,
    justifyContent: 'center',
    alignItems: 'center',
  },
  addIconText: {
    color: Colors.primary,
    fontSize: 20,
    fontWeight: '700',
    marginTop: -1,
  },
});
