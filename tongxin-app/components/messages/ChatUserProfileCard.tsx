import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import AppIcon from '../ui/AppIcon';
import {
  acceptFriendRequest,
  fetchChatUserProfile,
  sendFriendRequest,
  type ChatRelationshipStatus,
  type ChatUserProfile,
  type PeerProfile,
} from '../../services/api/messagesApi';
import { useAuthStore } from '../../services/store/authStore';
import { useMessagesStore } from '../../services/store/messagesStore';
import { Colors, Sizes } from '../../theme/colors';

type SeedProfile = Partial<PeerProfile> | null | undefined;

type Props = {
  userId: string;
  initialProfile?: SeedProfile;
  embedded?: boolean;
  onViewPublicProfile?: (uid: string) => void;
};

function ProfileAvatar({
  name,
  imageUrl,
  size = 76,
}: {
  name: string;
  imageUrl?: string | null;
  size?: number;
}) {
  const letter = (name || '?').charAt(0).toUpperCase();
  const hue = name.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0) % 360;
  const backgroundColor = `hsl(${hue}, 34%, 24%)`;
  const color = `hsl(${hue}, 64%, 78%)`;

  if (imageUrl) {
    return (
      <Image
        source={{ uri: imageUrl }}
        style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: Colors.surfaceAlt }}
      />
    );
  }

  return (
    <View
      style={[
        styles.avatarFallback,
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          backgroundColor,
        },
      ]}
    >
      <Text style={[styles.avatarFallbackText, { color, fontSize: Math.max(24, size * 0.38) }]}>{letter}</Text>
    </View>
  );
}

function compactNumber(value?: number | null) {
  if (value == null || !Number.isFinite(value)) return '--';
  if (Math.abs(value) >= 1000000) return `${(value / 1000000).toFixed(1)}m`;
  if (Math.abs(value) >= 1000) return `${(value / 1000).toFixed(1)}k`;
  return String(Math.round(value * 10) / 10);
}

export default function ChatUserProfileCard({
  userId,
  initialProfile,
  embedded,
  onViewPublicProfile,
}: Props) {
  const { t } = useTranslation();
  const currentUser = useAuthStore((s) => s.user);
  const friends = useMessagesStore((s) => s.friends);
  const incomingFriendRequests = useMessagesStore((s) => s.incomingFriendRequests);
  const outgoingFriendRequests = useMessagesStore((s) => s.outgoingFriendRequests);
  const supportAssignment = useMessagesStore((s) => s.supportAssignment);
  const loadFriends = useMessagesStore((s) => s.loadFriends);
  const loadFriendRequests = useMessagesStore((s) => s.loadFriendRequests);
  const [profile, setProfile] = useState<ChatUserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);

  useEffect(() => {
    if (friends.length === 0) {
      void loadFriends();
    }
    if (incomingFriendRequests.length === 0 && outgoingFriendRequests.length === 0) {
      void loadFriendRequests();
    }
  }, [
    friends.length,
    incomingFriendRequests.length,
    outgoingFriendRequests.length,
    loadFriends,
    loadFriendRequests,
  ]);

  const fallbackProfile = useMemo<ChatUserProfile>(() => {
    const normalizedUserId = String(userId ?? '').trim();
    const currentUserId = String(currentUser?.uid ?? '').trim();
    const isSelf = !!normalizedUserId && normalizedUserId === currentUserId;
    const isSupportAgent =
      !!normalizedUserId &&
      normalizedUserId === String(supportAssignment?.agent?.uid ?? '').trim();

    let relationshipStatus: ChatRelationshipStatus = 'not_friend';
    let relationshipRequestID: string | undefined;

    if (isSelf) {
      relationshipStatus = 'self';
    } else if (isSupportAgent) {
      relationshipStatus = 'support';
    } else if (friends.some((friend) => String(friend.user_id ?? '').trim() === normalizedUserId)) {
      relationshipStatus = 'friend';
    } else {
      const outgoing = outgoingFriendRequests.find(
        (request) =>
          String(request.to_user_id ?? '').trim() === normalizedUserId &&
          String(request.status ?? '').trim() === 'pending',
      );
      const incoming = incomingFriendRequests.find(
        (request) =>
          String(request.from_user_id ?? '').trim() === normalizedUserId &&
          String(request.status ?? '').trim() === 'pending',
      );
      if (outgoing) {
        relationshipStatus = 'pending_outgoing';
      } else if (incoming) {
        relationshipStatus = 'pending_incoming';
        relationshipRequestID = incoming.id;
      }
    }

    return {
      uid: normalizedUserId,
      display_name:
        initialProfile?.display_name?.trim() || normalizedUserId || t('messages.currentConversation'),
      avatar_url: initialProfile?.avatar_url || undefined,
      email: initialProfile?.email || undefined,
      short_id: initialProfile?.short_id || undefined,
      bio: '',
      role: undefined,
      status: 'active',
      online: false,
      is_self: isSelf,
      is_support_agent: isSupportAgent,
      relationship_status: relationshipStatus,
      relationship_request_id: relationshipRequestID,
      can_add_friend: relationshipStatus === 'not_friend',
      can_accept_friend: relationshipStatus === 'pending_incoming' && !!relationshipRequestID,
      trader_summary: null,
    };
  }, [
    userId,
    currentUser?.uid,
    supportAssignment?.agent?.uid,
    friends,
    incomingFriendRequests,
    outgoingFriendRequests,
    initialProfile?.display_name,
    initialProfile?.avatar_url,
    initialProfile?.email,
    initialProfile?.short_id,
    t,
  ]);

  const loadProfile = useCallback(async () => {
    if (!userId) return;
    setLoading(true);
    setProfileError(null);
    try {
      const data = await fetchChatUserProfile(userId);
      setProfile(data);
    } catch (error: any) {
      console.error('[ChatUserProfileCard] load failed:', error);
      setProfile(null);
      setProfileError(error?.response?.data?.error || error?.message || t('messages.profileLoadFailed'));
    } finally {
      setLoading(false);
    }
  }, [userId, t]);

  useEffect(() => {
    void loadProfile();
  }, [loadProfile]);

  const effectiveProfile = profile ?? fallbackProfile;
  const displayName = effectiveProfile.display_name || initialProfile?.display_name || userId;
  const avatarUrl = effectiveProfile.avatar_url || initialProfile?.avatar_url || null;
  const bio = effectiveProfile.bio?.trim();
  const isTrader = !!effectiveProfile.trader_summary?.is_trader;
  const canOpenPublicProfile = isTrader && !!onViewPublicProfile;

  const relationshipLabel = useMemo(() => {
    switch (effectiveProfile.relationship_status) {
      case 'self':
        return t('contacts.selfTag');
      case 'friend':
        return t('contacts.addedTag');
      case 'pending_outgoing':
        return t('messages.addFriendWaiting');
      case 'pending_incoming':
        return t('messages.acceptFriendRequest');
      case 'support':
        return t('messages.supportBadge');
      default:
        return null;
    }
  }, [effectiveProfile.relationship_status, t]);

  const handleAddFriend = useCallback(async () => {
    if (!effectiveProfile.can_add_friend) return;
    setActionLoading(true);
    try {
      await sendFriendRequest(userId);
      await loadFriendRequests();
      await loadProfile();
    } catch (error: any) {
      const message = error?.response?.data?.error || error?.message || t('messages.profileActionFailed');
      if (Platform.OS === 'web' && typeof window !== 'undefined' && window.alert) {
        window.alert(message);
      } else {
        Alert.alert('', message);
      }
    } finally {
      setActionLoading(false);
    }
  }, [effectiveProfile.can_add_friend, userId, loadFriendRequests, loadProfile, t]);

  const handleAcceptFriend = useCallback(async () => {
    if (!effectiveProfile.can_accept_friend || !effectiveProfile.relationship_request_id) return;
    setActionLoading(true);
    try {
      await acceptFriendRequest(effectiveProfile.relationship_request_id);
      await Promise.all([loadFriends(), loadFriendRequests()]);
      await loadProfile();
    } catch (error: any) {
      const message = error?.response?.data?.error || error?.message || t('messages.profileActionFailed');
      if (Platform.OS === 'web' && typeof window !== 'undefined' && window.alert) {
        window.alert(message);
      } else {
        Alert.alert('', message);
      }
    } finally {
      setActionLoading(false);
    }
  }, [effectiveProfile, loadFriends, loadFriendRequests, loadProfile, t]);

  const renderPrimaryAction = () => {
    if (effectiveProfile.relationship_status === 'self' || effectiveProfile.relationship_status === 'support') {
      return null;
    }
    if (effectiveProfile.relationship_status === 'friend') {
      return (
        <View style={[styles.actionBtn, styles.actionBtnMuted]}>
          <Text style={[styles.actionBtnText, styles.actionBtnTextMuted]}>{t('contacts.addedTag')}</Text>
        </View>
      );
    }
    if (effectiveProfile.relationship_status === 'pending_outgoing') {
      return (
        <View style={[styles.actionBtn, styles.actionBtnMuted]}>
          <Text style={[styles.actionBtnText, styles.actionBtnTextMuted]}>{t('messages.addFriendWaiting')}</Text>
        </View>
      );
    }
    if (effectiveProfile.can_accept_friend) {
      return (
        <TouchableOpacity
          style={[styles.actionBtn, actionLoading && styles.actionBtnDisabled]}
          activeOpacity={0.85}
          disabled={actionLoading}
          onPress={() => void handleAcceptFriend()}
        >
          {actionLoading ? (
            <ActivityIndicator size="small" color={Colors.textOnPrimary} />
          ) : (
            <Text style={styles.actionBtnText}>{t('messages.acceptFriendRequest')}</Text>
          )}
        </TouchableOpacity>
      );
    }
    if (effectiveProfile.can_add_friend) {
      return (
        <TouchableOpacity
          style={[styles.actionBtn, actionLoading && styles.actionBtnDisabled]}
          activeOpacity={0.85}
          disabled={actionLoading}
          onPress={() => void handleAddFriend()}
        >
          {actionLoading ? (
            <ActivityIndicator size="small" color={Colors.textOnPrimary} />
          ) : (
            <Text style={styles.actionBtnText}>{t('contacts.addAction')}</Text>
          )}
        </TouchableOpacity>
      );
    }
    return null;
  };

  if (loading && !profile) {
    return (
      <View style={[styles.panel, embedded && styles.panelEmbedded, styles.loadingWrap]}>
        <ActivityIndicator color={Colors.primary} />
      </View>
    );
  }

  return (
    <View style={[styles.panel, embedded && styles.panelEmbedded]}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        <View style={styles.heroCard}>
          <ProfileAvatar name={displayName} imageUrl={avatarUrl} />
          <Text style={styles.name}>{displayName}</Text>
          <View style={styles.badgeRow}>
            {effectiveProfile.is_support_agent ? (
              <View style={[styles.badgePill, styles.badgePillSupport]}>
                <Text style={[styles.badgePillText, styles.badgePillSupportText]}>{t('messages.supportBadge')}</Text>
              </View>
            ) : null}
            {isTrader ? (
              <View style={styles.badgePill}>
                <Text style={styles.badgePillText}>{t('messages.badgeTrader')}</Text>
              </View>
            ) : null}
            {relationshipLabel ? (
              <View style={[styles.badgePill, styles.badgePillMuted]}>
                <Text style={[styles.badgePillText, styles.badgePillMutedText]}>{relationshipLabel}</Text>
              </View>
            ) : null}
          </View>
          <View style={styles.metaBlock}>
            <Text style={styles.metaText}>{`UID: ${effectiveProfile.uid}`}</Text>
            {effectiveProfile.email ? <Text style={styles.metaText}>{effectiveProfile.email}</Text> : null}
            <Text style={[styles.statusText, effectiveProfile.online && styles.statusTextOnline]}>
              {effectiveProfile.online ? t('messages.online') : t('messages.profileOffline')}
            </Text>
          </View>
        </View>

        {profileError ? (
          <View style={styles.warningCard}>
            <Text style={styles.warningText}>{t('messages.profilePartialFallback')}</Text>
          </View>
        ) : null}

        <View style={styles.sectionCard}>
          <Text style={styles.sectionTitle}>{t('messages.profileAboutTitle')}</Text>
          <Text style={styles.aboutText}>
            {effectiveProfile.is_support_agent
              ? t('messages.profileSupportHint')
              : bio || t('messages.profileBioFallback')}
          </Text>
        </View>

        {isTrader ? (
          <View style={styles.sectionCard}>
            <Text style={styles.sectionTitle}>{t('messages.profileTraderSummaryTitle')}</Text>
            <View style={styles.statsGrid}>
              <View style={styles.statCard}>
                <Text style={styles.statValue}>
                  {Number.isFinite(effectiveProfile.trader_summary?.win_rate)
                    ? `${Number(effectiveProfile.trader_summary?.win_rate).toFixed(1)}%`
                    : '--'}
                </Text>
                <Text style={styles.statLabel}>{t('messages.winRate')}</Text>
              </View>
              <View style={styles.statCard}>
                <Text style={styles.statValue}>{compactNumber(effectiveProfile.trader_summary?.copiers_count)}</Text>
                <Text style={styles.statLabel}>{t('messages.copiers')}</Text>
              </View>
              <View style={styles.statCard}>
                <Text style={styles.statValue}>{compactNumber(effectiveProfile.trader_summary?.total_trades)}</Text>
                <Text style={styles.statLabel}>{t('messages.totalTradesLabel')}</Text>
              </View>
              <View style={styles.statCard}>
                <Text
                  style={[
                    styles.statValue,
                    (effectiveProfile.trader_summary?.total_pnl || 0) < 0
                      ? { color: Colors.down }
                      : { color: Colors.up },
                  ]}
                >
                  {effectiveProfile.trader_summary?.total_pnl != null
                    ? `${effectiveProfile.trader_summary.total_pnl > 0 ? '+' : ''}${compactNumber(effectiveProfile.trader_summary.total_pnl)}`
                    : '--'}
                </Text>
                <Text style={styles.statLabel}>{t('messages.totalReturn')}</Text>
              </View>
            </View>
            <View style={styles.copyStatusRow}>
              <AppIcon
                name="shield"
                size={14}
                color={effectiveProfile.trader_summary?.allow_copy_trading ? Colors.up : Colors.textMuted}
              />
              <Text style={styles.copyStatusText}>
                {effectiveProfile.trader_summary?.allow_copy_trading
                  ? t('messages.enabledCopy')
                  : t('messages.disabledCopy')}
              </Text>
            </View>
          </View>
        ) : null}
      </ScrollView>

      <View style={styles.footer}>
        {renderPrimaryAction()}
        {canOpenPublicProfile ? (
          <TouchableOpacity
            style={[styles.actionBtn, styles.secondaryBtn]}
            activeOpacity={0.85}
            onPress={() => onViewPublicProfile?.(userId)}
          >
            <Text style={[styles.actionBtnText, styles.secondaryBtnText]}>{t('messages.viewPublicProfile')}</Text>
          </TouchableOpacity>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  panel: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderLeftWidth: 1,
    borderLeftColor: Colors.border,
  },
  panelEmbedded: {
    borderLeftWidth: 0,
    backgroundColor: 'transparent',
  },
  loadingWrap: {
    minHeight: 240,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarFallback: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarFallbackText: {
    fontWeight: '800',
  },
  warningCard: {
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(222, 167, 53, 0.18)',
    backgroundColor: 'rgba(222, 167, 53, 0.08)',
  },
  warningText: {
    color: Colors.primary,
    fontSize: 12,
    lineHeight: 18,
  },
  scrollContent: {
    padding: 18,
    gap: 14,
  },
  heroCard: {
    alignItems: 'center',
    gap: 10,
    padding: 18,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
  },
  name: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
  },
  badgeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexWrap: 'wrap',
    justifyContent: 'center',
  },
  badgePill: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  badgePillMuted: {
    backgroundColor: Colors.surface,
    borderColor: Colors.borderLight,
  },
  badgePillSupport: {
    backgroundColor: 'rgba(102, 228, 185, 0.12)',
    borderColor: 'rgba(102, 228, 185, 0.22)',
  },
  badgePillText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '800',
  },
  badgePillMutedText: {
    color: Colors.textSecondary,
  },
  badgePillSupportText: {
    color: Colors.up,
  },
  metaBlock: {
    alignItems: 'center',
    gap: 4,
  },
  metaText: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  statusText: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  statusTextOnline: {
    color: Colors.up,
  },
  sectionCard: {
    padding: 16,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    gap: 12,
  },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  aboutText: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
  },
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  statCard: {
    minWidth: 120,
    flex: 1,
    padding: 12,
    borderRadius: 14,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
    gap: 6,
  },
  statValue: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
  },
  statLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
  },
  copyStatusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  copyStatusText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
  },
  footer: {
    padding: 18,
    paddingTop: 0,
    gap: 10,
  },
  actionBtn: {
    minHeight: 46,
    borderRadius: Sizes.borderRadius,
    backgroundColor: Colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  actionBtnDisabled: {
    opacity: 0.55,
  },
  actionBtnMuted: {
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  actionBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '800',
  },
  actionBtnTextMuted: {
    color: Colors.textSecondary,
  },
  secondaryBtn: {
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  secondaryBtnText: {
    color: Colors.primary,
  },
});
