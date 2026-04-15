import { useState, useMemo, useCallback, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  Platform,
  ActivityIndicator,
  Alert,
  Image,
} from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes } from '../theme/colors';
import { Config } from '../services/config';
import { useAuthStore } from '../services/store/authStore';
import { useMessagesStore } from '../services/store/messagesStore';
import {
  fetchUserProfilesBatch,
  acceptFriendRequest,
  rejectFriendRequest,
  createDirectConversation,
  type PeerProfile,
} from '../services/api/messagesApi';
import AppIcon from '../components/ui/AppIcon';

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

export default function ContactsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const user = useAuthStore((s) => s.user);
  const friends = useMessagesStore((s) => s.friends);
  const incomingFriendRequests = useMessagesStore((s) => s.incomingFriendRequests);
  const outgoingFriendRequests = useMessagesStore((s) => s.outgoingFriendRequests);
  const loadFriends = useMessagesStore((s) => s.loadFriends);
  const loadFriendRequests = useMessagesStore((s) => s.loadFriendRequests);
  const friendsError = useMessagesStore((s) => s.friendsError);

  const [profiles, setProfiles] = useState<Record<string, PeerProfile>>({});
  const [busyId, setBusyId] = useState<string | null>(null);
  const [openingChat, setOpeningChat] = useState<string | null>(null);

  const sortedFriends = useMemo(() => {
    return [...friends].sort((a, b) =>
      (a.display_name || '').localeCompare(b.display_name || '', 'zh-Hans'),
    );
  }, [friends]);

  const profileIds = useMemo(() => {
    const s = new Set<string>();
    incomingFriendRequests.forEach((r) => s.add(r.from_user_id));
    outgoingFriendRequests.forEach((r) => s.add(r.to_user_id));
    sortedFriends.forEach((f) => s.add(f.user_id));
    return [...s];
  }, [incomingFriendRequests, outgoingFriendRequests, sortedFriends]);

  const refresh = useCallback(() => {
    if (!user) return;
    console.log('[Contacts] refresh start:', { uid: user.uid });
    loadFriends();
    void loadFriendRequests();
  }, [user, loadFriends, loadFriendRequests]);

  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh]),
  );

  const profileIdsKey = profileIds.join(',');

  useEffect(() => {
    console.log('[Contacts] render state:', {
      userId: user?.uid ?? null,
      friendsCount: friends.length,
      sortedFriendsCount: sortedFriends.length,
      incomingCount: incomingFriendRequests.length,
      outgoingCount: outgoingFriendRequests.length,
      friendsError,
    });
  }, [user?.uid, friends.length, sortedFriends.length, incomingFriendRequests.length, outgoingFriendRequests.length, friendsError]);

  useEffect(() => {
    if (profileIds.length === 0) {
      setProfiles({});
      return;
    }
    let cancelled = false;
    fetchUserProfilesBatch(profileIds).then((m) => {
      if (!cancelled) setProfiles(m);
    });
    return () => {
      cancelled = true;
    };
  }, [profileIdsKey]);

  const displayName = (uid: string) =>
    profiles[uid]?.display_name?.trim() || sortedFriends.find((f) => f.user_id === uid)?.display_name || uid;

  const handleAccept = async (requestId: string) => {
    setBusyId(requestId);
    try {
      await acceptFriendRequest(requestId);
      refresh();
    } catch {
      Alert.alert(t('contacts.errorTitle'), t('contacts.actionFailed'));
    } finally {
      setBusyId(null);
    }
  };

  const handleReject = async (requestId: string) => {
    setBusyId(requestId);
    try {
      await rejectFriendRequest(requestId);
      refresh();
    } catch {
      Alert.alert(t('contacts.errorTitle'), t('contacts.actionFailed'));
    } finally {
      setBusyId(null);
    }
  };

  const handleOpenChat = async (uid: string) => {
    setOpeningChat(uid);
    try {
      const result = await createDirectConversation(uid);
      router.replace({ pathname: '/(tabs)/messages', params: { conversationId: result.id } } as any);
    } catch {
      Alert.alert(t('contacts.errorTitle'), t('contacts.chatOpenFailed'));
    } finally {
      setOpeningChat(null);
    }
  };

  if (!user) {
    return (
      <View style={styles.centered}>
        <Text style={styles.muted}>{t('messages.loginRequired')}</Text>
        <TouchableOpacity style={styles.primaryBtn} onPress={() => router.back()}>
          <Text style={styles.primaryBtnText}>{t('common.done')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const newFriendTotal = incomingFriendRequests.length + outgoingFriendRequests.length;

  return (
    <View style={styles.root}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn} activeOpacity={0.7}>
          <Text style={styles.backArrow}>←</Text>
        </TouchableOpacity>
        <Text style={styles.headerTitle}>{t('contacts.title')}</Text>
        <TouchableOpacity onPress={() => router.push('/add-friend' as any)} style={styles.addLink}>
          <Text style={styles.addLinkText}>{t('contacts.addFriend')}</Text>
        </TouchableOpacity>
      </View>

      <ScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled">
        {/* WeChat-style row */}
        <View style={styles.wechatRow}>
          <View style={styles.wechatRowIcon}>
            <AppIcon name="user" size={22} color={Colors.textSecondary} />
            {newFriendTotal > 0 ? (
              <View style={styles.rowBadge}>
                <Text style={styles.rowBadgeText}>{newFriendTotal > 99 ? '99+' : newFriendTotal}</Text>
              </View>
            ) : null}
          </View>
          <View style={styles.wechatRowBody}>
            <Text style={styles.wechatRowTitle}>{t('contacts.newFriends')}</Text>
            <Text style={styles.wechatRowSub} numberOfLines={1}>
              {newFriendTotal === 0
                ? t('contacts.noNewFriendLine')
                : t('contacts.newFriendsSummary', { count: newFriendTotal })}
            </Text>
          </View>
          <Text style={styles.chevron}>›</Text>
        </View>

        {/* 收到 */}
        {incomingFriendRequests.length > 0 ? (
          <View style={styles.section}>
            <Text style={styles.sectionLabel}>{t('contacts.incomingSection')}</Text>
            {incomingFriendRequests.map((req) => (
              <View key={req.id} style={styles.card}>
                <AvatarCircle name={displayName(req.from_user_id)} size={44} />
                <View style={styles.cardBody}>
                  <Text style={styles.cardName} numberOfLines={1}>
                    {displayName(req.from_user_id)}
                  </Text>
                  <Text style={styles.cardSub} numberOfLines={1}>
                    {req.message || t('contacts.wantsToAddYou')}
                  </Text>
                </View>
                {busyId === req.id ? (
                  <ActivityIndicator size="small" color={Colors.primary} />
                ) : (
                  <View style={styles.cardActions}>
                    <TouchableOpacity
                      style={[styles.miniBtn, styles.rejectBtn]}
                      onPress={() => handleReject(req.id)}
                      activeOpacity={0.8}
                    >
                      <Text style={styles.rejectBtnText}>{t('contacts.reject')}</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={[styles.miniBtn, styles.acceptBtn]}
                      onPress={() => handleAccept(req.id)}
                      activeOpacity={0.8}
                    >
                      <Text style={styles.acceptBtnText}>{t('contacts.accept')}</Text>
                    </TouchableOpacity>
                  </View>
                )}
              </View>
            ))}
          </View>
        ) : null}

        {/* 发出 */}
        {outgoingFriendRequests.length > 0 ? (
          <View style={styles.section}>
            <Text style={styles.sectionLabel}>{t('contacts.outgoingSection')}</Text>
            {outgoingFriendRequests.map((req) => (
              <View key={req.id} style={styles.card}>
                <AvatarCircle name={displayName(req.to_user_id)} size={44} />
                <View style={styles.cardBody}>
                  <Text style={styles.cardName} numberOfLines={1}>
                    {displayName(req.to_user_id)}
                  </Text>
                  <Text style={styles.cardSub}>{t('contacts.waitingVerify')}</Text>
                </View>
                <Text style={styles.waitingPill}>{t('contacts.waitingVerify')}</Text>
              </View>
            ))}
          </View>
        ) : null}

        {incomingFriendRequests.length === 0 && outgoingFriendRequests.length === 0 ? (
          <Text style={styles.emptyHint}>{t('contacts.noRequestsDetail')}</Text>
        ) : null}

        {/* 好友列表 */}
        <View style={styles.section}>
          <Text style={styles.sectionLabel}>{t('contacts.myFriends')}</Text>
          {friendsError ? (
            <Text style={[styles.emptyHint, { color: Colors.down }]}>
              {t('contacts.friendsLoadFailed')}: {friendsError}
            </Text>
          ) : null}
          {sortedFriends.length === 0 ? (
            <Text style={styles.emptyHint}>
              {t('contacts.noFriendsYet')}
              {user?.uid ? ` (uid: ${user.uid})` : ''}
            </Text>
          ) : (
            sortedFriends.map((f) => (
              <TouchableOpacity
                key={f.user_id}
                style={[styles.card, styles.friendRow]}
                onPress={() => handleOpenChat(f.user_id)}
                activeOpacity={0.75}
                disabled={openingChat === f.user_id}
              >
                <AvatarCircle name={f.display_name} size={44} imageUrl={f.avatar_url} />
                <View style={styles.cardBody}>
                  <Text style={styles.cardName} numberOfLines={1}>
                    {f.display_name}
                  </Text>
                  <Text style={styles.cardSub} numberOfLines={1}>
                    {`UID: ${f.user_id}`}
                  </Text>
                </View>
                {openingChat === f.user_id ? (
                  <ActivityIndicator size="small" color={Colors.primary} />
                ) : (
                  <AppIcon name="message" size={18} color={Colors.primary} />
                )}
              </TouchableOpacity>
            ))
          )}
        </View>

        <View style={{ height: 32 }} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: Colors.background },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
    backgroundColor: Colors.background,
    gap: 16,
  },
  muted: { color: Colors.textMuted, fontSize: 15 },
  primaryBtn: {
    backgroundColor: Colors.primary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: Sizes.borderRadiusSm,
  },
  primaryBtnText: { color: Colors.background, fontWeight: '700' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingTop: Platform.OS === 'ios' ? 56 : 16,
    paddingBottom: 12,
    backgroundColor: Colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  backBtn: { width: 40, height: 40, justifyContent: 'center', alignItems: 'center' },
  backArrow: { color: Colors.textActive, fontSize: 22 },
  headerTitle: { color: Colors.textActive, fontSize: 17, fontWeight: '600' },
  addLink: { paddingHorizontal: 8, paddingVertical: 4 },
  addLinkText: { color: Colors.primary, fontSize: 14, fontWeight: '600' },
  scroll: { flex: 1 },
  scrollContent: { padding: 16, gap: 8 },
  wechatRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    marginBottom: 8,
  },
  wechatRowIcon: {
    width: 48,
    height: 48,
    borderRadius: 8,
    backgroundColor: Colors.surfaceAlt,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
    position: 'relative',
  },
  rowBadge: {
    position: 'absolute',
    top: -4,
    right: -4,
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: '#c62828',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  rowBadgeText: { color: '#fff', fontSize: 10, fontWeight: '800' },
  wechatRowBody: { flex: 1, minWidth: 0 },
  wechatRowTitle: { color: Colors.textActive, fontSize: 16, fontWeight: '700' },
  wechatRowSub: { color: Colors.textMuted, fontSize: 13, marginTop: 2 },
  chevron: { color: Colors.textMuted, fontSize: 22, marginLeft: 8 },
  section: { marginTop: 12, gap: 8 },
  sectionLabel: {
    fontSize: 12,
    fontWeight: '700',
    color: Colors.textMuted,
    letterSpacing: 0.8,
    marginLeft: 4,
    marginBottom: 4,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    gap: 12,
  },
  friendRow: {},
  cardBody: { flex: 1, minWidth: 0 },
  cardName: { color: Colors.textActive, fontSize: 15, fontWeight: '700' },
  cardSub: { color: Colors.textMuted, fontSize: 12, marginTop: 2 },
  cardActions: { flexDirection: 'row', gap: 8, flexShrink: 0 },
  miniBtn: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    justifyContent: 'center',
  },
  rejectBtn: { backgroundColor: Colors.surfaceAlt, borderWidth: 1, borderColor: Colors.border },
  rejectBtnText: { color: Colors.textMuted, fontSize: 13, fontWeight: '600' },
  acceptBtn: { backgroundColor: Colors.primary },
  acceptBtnText: { color: Colors.background, fontSize: 13, fontWeight: '700' },
  waitingPill: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
    flexShrink: 0,
  },
  chatIcon: { fontSize: 20 },
  emptyHint: {
    color: Colors.textMuted,
    fontSize: 13,
    textAlign: 'center',
    paddingVertical: 16,
    paddingHorizontal: 12,
  },
});
