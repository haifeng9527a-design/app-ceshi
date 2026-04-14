import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Modal,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import * as ImagePicker from 'expo-image-picker';
import apiClient, { getStoredToken } from '../../services/api/client';
import { useAuthStore } from '../../services/store/authStore';
import { useFeedbackStore } from '../../services/store/feedbackStore';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import AppIcon, { type AppIconName } from '../../components/ui/AppIcon';

function AvatarCircle({ name, size = 84, imageUrl }: { name: string; size?: number; imageUrl?: string | null }) {
  const letter = (name || '?').charAt(0).toUpperCase();
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: Colors.primaryDim,
        borderWidth: 2,
        borderColor: Colors.primary,
        justifyContent: 'center',
        alignItems: 'center',
        overflow: 'hidden',
      }}
    >
      {imageUrl ? (
        <Image source={{ uri: imageUrl }} style={{ width: '100%', height: '100%' }} resizeMode="cover" />
      ) : (
        <Text style={{ color: Colors.primary, fontSize: size * 0.38, fontWeight: '800' }}>{letter}</Text>
      )}
    </View>
  );
}

type QuickAction = {
  key: string;
  title: string;
  description: string;
  icon: AppIconName;
  onPress: () => void;
};

const MAX_AVATAR_UPLOAD_BYTES = 10 * 1024 * 1024;
const ALLOWED_AVATAR_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

function formatFileSize(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

export default function ProfileScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const isWeb = typeof document !== 'undefined';
  const { user, signOut, syncProfile } = useAuthStore();
  const feedbackUnread = useFeedbackStore((s) => s.unreadCount);
  const fetchFeedbackUnread = useFeedbackStore((s) => s.fetchUnreadCount);
  const isDesktop = width >= 768;

  // 进入我的页面时刷新未读数（含 Tab 切换回来）
  useFocusEffect(
    useCallback(() => {
      if (user) fetchFeedbackUnread();
    }, [user, fetchFeedbackUnread])
  );
  const [showEditProfile, setShowEditProfile] = useState(false);
  const [savingProfile, setSavingProfile] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [displayName, setDisplayName] = useState('');
  const [avatarUrl, setAvatarUrl] = useState('');
  const [avatarPreviewUrl, setAvatarPreviewUrl] = useState('');
  const [avatarUploadProgress, setAvatarUploadProgress] = useState(0);
  const [avatarUploadMessage, setAvatarUploadMessage] = useState(t('profile.avatarFormatsHint'));
  const [avatarUploadMeta, setAvatarUploadMeta] = useState<{ name: string; size: number } | null>(null);
  const [phone, setPhone] = useState('');
  const [bio, setBio] = useState('');

  useEffect(() => {
    if (!user) return;
    setDisplayName(user.displayName || '');
    setAvatarUrl(user.photoURL || '');
    setAvatarPreviewUrl(user.photoURL || '');
    setAvatarUploadProgress(0);
    setAvatarUploadMeta(null);
    setAvatarUploadMessage(t('profile.avatarFormatsHint'));
    setPhone(user.phone || '');
    setBio(user.signature || '');
  }, [user?.uid, user?.displayName, user?.photoURL, user?.phone, user?.signature]);

  const handleSignOut = () => {
    Alert.alert(t('auth.logout'), t('profile.logoutConfirmBody'), [
      { text: t('common.cancel'), style: 'cancel' },
      {
        text: t('auth.logout'),
        style: 'destructive',
        onPress: async () => {
          await signOut();
          router.replace('/');
        },
      },
    ]);
  };

  const handleSaveProfile = async () => {
    if (!displayName.trim()) {
      Alert.alert(t('profile.hintTitle'), t('profile.nicknameRequired'));
      return;
    }
    setSavingProfile(true);
    try {
      await apiClient.put('/api/auth/profile', {
        display_name: displayName.trim(),
        avatar_url: avatarUrl.trim(),
        phone: phone.trim(),
        bio: bio.trim(),
      });
      await syncProfile();
      setAvatarPreviewUrl(avatarUrl.trim());
      setAvatarUploadMessage(t('profile.avatarSaved'));
      setShowEditProfile(false);
      Alert.alert(t('profile.updatedTitle'), t('profile.updatedBody'));
    } catch (e: any) {
      Alert.alert(t('profile.saveFailedTitle'), e?.response?.data?.error || e?.message || t('profile.saveFailedBody'));
    } finally {
      setSavingProfile(false);
    }
  };

  const uploadAvatar = async (
    uri: string,
    fileName?: string | null,
    mimeType?: string | null,
    webFile?: File | null,
    onProgress?: (percent: number) => void,
  ) => {
    const fallbackName = fileName || webFile?.name || uri.split('/').pop() || 'avatar.jpg';
    const ext = fallbackName.split('.').pop()?.toLowerCase() || 'jpg';
    const resolvedMimeType =
      mimeType || webFile?.type || (ext === 'png' ? 'image/png' : ext === 'gif' ? 'image/gif' : 'image/jpeg');

    if (Platform.OS === 'web' && webFile) {
      const formData = new window.FormData();
      formData.append('file', webFile, fallbackName);
      const token = await getStoredToken();
      const response = await fetch(`${apiClient.defaults.baseURL}/api/upload`, {
        method: 'POST',
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
        body: formData,
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(data?.error || t('profile.avatarUploadFailedBody'));
      }
      const rawUrl = data?.url || '';
      if (!rawUrl) {
        throw new Error(t('profile.avatarMissingUrl'));
      }
      onProgress?.(100);
      return rawUrl.startsWith('http') ? rawUrl : `${apiClient.defaults.baseURL}${rawUrl}`;
    } else {
      const formData = new FormData();
      formData.append('file', {
        uri,
        name: fallbackName,
        type: resolvedMimeType,
      } as any);
      const { data } = await apiClient.post('/api/upload', formData, {
        onUploadProgress: (event) => {
          const total = event.total || 0;
          if (!total) return;
          onProgress?.(Math.min(100, Math.round((event.loaded / total) * 100)));
        },
      });

      const rawUrl = data?.url || '';
      if (!rawUrl) {
        throw new Error(t('profile.avatarMissingUrl'));
      }
      return rawUrl.startsWith('http') ? rawUrl : `${apiClient.defaults.baseURL}${rawUrl}`;
    }
  };

  const handlePickAvatar = async () => {
    if (isWeb) {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/jpeg,image/png,image/gif,image/webp';
      input.onchange = (event) => {
        void handleWebAvatarSelected(event);
      };
      input.click();
      return;
    }

    try {
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsEditing: true,
        aspect: [1, 1],
        quality: 0.85,
      });

      if (result.canceled || !result.assets?.[0]) return;

      const asset = result.assets[0];
      const size = asset.fileSize ?? 0;
      const mimeType = asset.mimeType || 'image/jpeg';
      if (size > MAX_AVATAR_UPLOAD_BYTES) {
        setAvatarUploadMessage(t('profile.avatarTooLarge', { size: formatFileSize(size) }));
        return;
      }
      if (mimeType && !ALLOWED_AVATAR_TYPES.includes(mimeType)) {
        setAvatarUploadMessage(t('profile.avatarInvalidFormat'));
        return;
      }

      setAvatarUploadMeta({
        name: asset.fileName || 'avatar.jpg',
        size,
      });
      setAvatarPreviewUrl(asset.uri);
      setUploadingAvatar(true);
      setAvatarUploadProgress(0);
      setAvatarUploadMessage(t('profile.avatarUploading'));
      const uploadedUrl = await uploadAvatar(
        asset.uri,
        asset.fileName,
        mimeType,
        isWeb ? ((asset as any).file ?? null) : null,
        (percent) => setAvatarUploadProgress(percent),
      );
      setAvatarUrl(uploadedUrl);
      setAvatarPreviewUrl(uploadedUrl);
      setAvatarUploadProgress(100);
      setAvatarUploadMessage(t('profile.avatarUploadedPendingSave'));
      Alert.alert(t('profile.avatarUploadSuccessTitle'), t('profile.avatarUploadSuccessBody'));
    } catch (e: any) {
      setAvatarPreviewUrl(avatarUrl || user?.photoURL || '');
      setAvatarUploadProgress(0);
      setAvatarUploadMessage(e?.response?.data?.error || e?.message || t('profile.avatarUploadFailedBody'));
      Alert.alert(t('profile.avatarUploadFailedTitle'), e?.message || t('profile.avatarUploadFailedBody'));
    } finally {
      setUploadingAvatar(false);
    }
  };

  const handleWebAvatarSelected = async (event: any) => {
    const file = event?.target?.files?.[0] as File | undefined;
    if (!file) return;
    if (file.size > MAX_AVATAR_UPLOAD_BYTES) {
      setAvatarUploadMessage(t('profile.avatarTooLarge', { size: formatFileSize(file.size) }));
      return;
    }
    if (file.type && !ALLOWED_AVATAR_TYPES.includes(file.type)) {
      setAvatarUploadMessage(t('profile.avatarInvalidFormat'));
      return;
    }

    const localPreview = URL.createObjectURL(file);
    setAvatarUploadMeta({ name: file.name, size: file.size });
    setAvatarPreviewUrl(localPreview);
    setUploadingAvatar(true);
    setAvatarUploadProgress(0);
    setAvatarUploadMessage(t('profile.avatarUploading'));
    try {
      const uploadedUrl = await uploadAvatar(localPreview, file.name, file.type, file, (percent) =>
        setAvatarUploadProgress(percent),
      );
      setAvatarUrl(uploadedUrl);
      setAvatarPreviewUrl(uploadedUrl);
      setAvatarUploadProgress(100);
      setAvatarUploadMessage(t('profile.avatarUploadedPendingSave'));
      Alert.alert(t('profile.avatarUploadSuccessTitle'), t('profile.avatarUploadSuccessBody'));
    } catch (e: any) {
      setAvatarPreviewUrl(avatarUrl || user?.photoURL || '');
      setAvatarUploadProgress(0);
      setAvatarUploadMessage(e?.response?.data?.error || e?.message || t('profile.avatarUploadFailedBody'));
      Alert.alert(t('profile.avatarUploadFailedTitle'), e?.response?.data?.error || e?.message || t('profile.avatarUploadFailedBody'));
    } finally {
      setUploadingAvatar(false);
      URL.revokeObjectURL(localPreview);
    }
  };

  const quickActions = useMemo<QuickAction[]>(
    () => [
      {
        key: 'trading',
        title: t('profile.tradingCenter'),
        description: t('profile.tradingCenterDesc'),
        icon: 'chart',
        onPress: () => router.push('/(tabs)/trading' as any),
      },
      {
        key: 'strategy',
        title: user?.isTrader ? t('profile.publishStrategy') : t('profile.traderCenterEntry'),
        description: user?.isTrader
          ? t('profile.publishStrategyDesc')
          : t('profile.traderCenterEntryDesc'),
        icon: 'bulb',
        onPress: () => router.push('/(tabs)/trader-center' as any),
      },
      {
        key: 'friends',
        title: t('profile.friendsEntry'),
        description: t('profile.friendsEntryDesc'),
        icon: 'users',
        onPress: () => router.push('/contacts' as any),
      },
      {
        key: 'public-profile',
        title: t('profile.publicProfile'),
        description: user?.isTrader ? t('profile.publicProfileDesc') : t('profile.publicProfileLockedDesc'),
        icon: 'globe',
        onPress: () => {
          if (user?.isTrader) {
            router.push(`/trader/${user.uid}` as any);
            return;
          }
          Alert.alert(t('profile.publicProfileUnavailableTitle'), t('profile.publicProfileUnavailableBody'));
        },
      },
    ],
    [router, t, user?.isTrader, user?.uid],
  );
  const currentLanguageLabel = useMemo(
    () => (i18n.language.startsWith('zh') ? t('profile.languageZh') : t('profile.languageEn')),
    [i18n.language, t],
  );

  if (!user) {
    return (
      <View style={styles.container}>
        <View style={styles.loginPrompt}>
          <AvatarCircle name="?" size={80} />
          <Text style={styles.loginTitle}>{t('auth.notLoggedIn')}</Text>
          <Text style={styles.loginHint}>{t('auth.loginHint')}</Text>
          <TouchableOpacity style={styles.loginBtn} onPress={() => router.push('/(auth)/login' as any)} activeOpacity={0.85}>
            <Text style={styles.loginBtnText}>{t('auth.loginOrRegister')}</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  return (
    <>
      <ScrollView
        style={styles.container}
        contentContainerStyle={[
          styles.scrollContent,
          isDesktop && { maxWidth: 900, alignSelf: 'center' as const, width: '100%' },
        ]}
        showsVerticalScrollIndicator={false}
      >
        <Text style={styles.pageTitle}>{t('profile.title')}</Text>
        <Text style={styles.pageSub}>{t('profile.pageSubtitle')}</Text>

        <View style={styles.headerCard}>
          <View style={styles.headerRow}>
            <View style={styles.avatarWrap}>
              <AvatarCircle name={user.displayName || user.email || 'U'} imageUrl={avatarPreviewUrl || user.photoURL} />
              <View style={styles.levelBadge}>
                <Text style={styles.levelText}>VIP{user.vipLevel ?? 0}</Text>
              </View>
            </View>
            <View style={styles.headerInfo}>
              <View style={styles.nameRow}>
                <Text style={styles.displayName}>{user.displayName || 'User'}</Text>
                {user.role ? (
                  <View style={styles.roleBadge}>
                    <Text style={styles.roleText}>{user.role}</Text>
                  </View>
                ) : null}
              </View>
              <Text style={styles.metaLine}>{t('profile.uidLabel')}: {user.uid || '--'}</Text>
              <Text style={styles.metaLine}>{t('profile.emailLabel')}: {user.email || '--'}</Text>
              {user.phone ? <Text style={styles.metaLine}>{t('profile.phoneLabel')}: {user.phone}</Text> : null}
              {user.signature ? <Text style={styles.bioText}>{user.signature}</Text> : null}
            </View>
          </View>

          <TouchableOpacity style={styles.editBtn} activeOpacity={0.85} onPress={() => setShowEditProfile(true)}>
            <Text style={styles.editBtnText}>{t('profile.editProfile')}</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.tilesRow}>
          {quickActions.map((action) => (
            <TouchableOpacity key={action.key} style={styles.tile} activeOpacity={0.85} onPress={action.onPress}>
              <View style={styles.tileIconWrap}>
                <AppIcon name={action.icon} size={20} color={Colors.primary} />
              </View>
              <Text style={styles.tileTitle}>{action.title}</Text>
              <Text style={styles.tileDesc}>{action.description}</Text>
              <View style={styles.tileCta}>
                <Text style={styles.tileCtaText}>{t('profile.enter')}</Text>
                <Text style={styles.tileCtaArrow}>→</Text>
              </View>
            </TouchableOpacity>
          ))}
        </View>

        <View style={styles.menuCard}>
          <MenuItem icon="users" label={t('profile.friendsEntry')} description={t('profile.friendsMenuDesc')} onPress={() => router.push('/contacts' as any)} />
          <MenuItem icon="help" label={t('profile.help')} description={t('profile.helpMenuDesc')} onPress={() => router.push('/help' as any)} />
          <MenuItem icon="lock" label={t('profile.privacyPolicy')} description={t('profile.privacyMenuDesc')} onPress={() => router.push('/privacy' as any)} />
          <MenuItem icon="market" label={t('profile.traderMarket')} description={t('profile.traderMarketDesc')} onPress={() => router.push('/(tabs)/rankings' as any)} />
          <MenuItem
            icon="bot"
            label={t('profile.feedback')}
            description={t('profile.feedbackDesc')}
            badge={feedbackUnread}
            onPress={() => router.push('/settings/feedback-history' as any)}
          />
          <MenuItem
            icon="globe"
            label={t('profile.language')}
            description={t('profile.languageDesc')}
            rightText={currentLanguageLabel}
            onPress={() => router.push('/settings/language' as any)}
            last
          />
        </View>

        <View style={styles.destructRow}>
          <TouchableOpacity style={styles.logoutBtn} onPress={handleSignOut} activeOpacity={0.85}>
            <AppIcon name="logout" size={18} color={Colors.down} />
            <Text style={styles.logoutText}>{t('profile.logout')}</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.deleteBtn}
            activeOpacity={0.85}
            onPress={() => Alert.alert(t('profile.deleteUnsupportedTitle'), t('profile.deleteUnsupportedBody'))}
          >
            <AppIcon name="trash" size={18} color={Colors.textMuted} />
            <Text style={styles.deleteText}>{t('profile.deleteAccount')}</Text>
          </TouchableOpacity>
        </View>

        <View style={{ height: 36 }} />
      </ScrollView>

      <Modal visible={showEditProfile} transparent animationType="fade" onRequestClose={() => setShowEditProfile(false)}>
        <View style={styles.modalOverlay}>
          <View style={styles.modalCard}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>{t('profile.editProfile')}</Text>
                <Text style={styles.modalSubtitle}>{t('profile.modalSubtitle')}</Text>
              </View>
              <TouchableOpacity style={styles.modalCloseBtn} activeOpacity={0.8} onPress={() => setShowEditProfile(false)}>
                <Text style={styles.modalCloseText}>×</Text>
              </TouchableOpacity>
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>{t('profile.nickname')}</Text>
              <TextInput
                style={styles.formInput}
                value={displayName}
                onChangeText={setDisplayName}
                placeholder={t('profile.nicknamePlaceholder')}
                placeholderTextColor={Colors.textMuted}
              />
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>{t('profile.avatar')}</Text>
              <View style={styles.avatarUploaderRow}>
                <AvatarCircle
                  name={displayName || user.email || 'U'}
                  size={68}
                  imageUrl={avatarPreviewUrl || avatarUrl || user.photoURL}
                />
                <View style={styles.avatarUploaderMeta}>
                  <Text style={styles.avatarUploaderHint}>{t('profile.avatarHint')}</Text>
                  {avatarUploadMeta ? (
                    <Text style={styles.avatarUploadMetaText}>
                      {t('profile.selectedFile')}: {avatarUploadMeta.name} · {formatFileSize(avatarUploadMeta.size)}
                    </Text>
                  ) : null}
                  <View style={styles.avatarProgressTrack}>
                    <View
                      style={[
                        styles.avatarProgressFill,
                        { width: `${Math.max(0, Math.min(100, avatarUploadProgress))}%` },
                      ]}
                    />
                  </View>
                  <Text style={styles.avatarUploadStatusText}>{avatarUploadMessage}</Text>
                  <TouchableOpacity
                    style={[styles.avatarUploadBtn, uploadingAvatar && styles.saveBtnDisabled]}
                    activeOpacity={0.85}
                    disabled={uploadingAvatar}
                    onPress={() => void handlePickAvatar()}
                  >
                    {uploadingAvatar ? (
                      <ActivityIndicator size="small" color={Colors.background} />
                    ) : (
                      <Text style={styles.avatarUploadBtnText}>{t('profile.pickAndUploadAvatar')}</Text>
                    )}
                  </TouchableOpacity>
                </View>
              </View>
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>{t('profile.phone')}</Text>
              <TextInput
                style={styles.formInput}
                value={phone}
                onChangeText={setPhone}
                placeholder={t('profile.phonePlaceholder')}
                placeholderTextColor={Colors.textMuted}
                keyboardType="phone-pad"
              />
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>{t('profile.bio')}</Text>
              <TextInput
                style={[styles.formInput, styles.formTextarea]}
                value={bio}
                onChangeText={setBio}
                placeholder={t('profile.bioPlaceholder')}
                placeholderTextColor={Colors.textMuted}
                multiline
              />
            </View>

            <TouchableOpacity
              style={[styles.saveBtn, savingProfile && styles.saveBtnDisabled]}
              activeOpacity={0.85}
              disabled={savingProfile}
              onPress={() => void handleSaveProfile()}
            >
              {savingProfile ? (
                <ActivityIndicator size="small" color={Colors.background} />
              ) : (
                <Text style={styles.saveBtnText}>{t('profile.saveProfile')}</Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </>
  );
}

function MenuItem({
  icon,
  label,
  description,
  rightText,
  onPress,
  last,
  disabled,
  badge,
}: {
  icon: AppIconName;
  label: string;
  description: string;
  rightText?: string;
  onPress?: () => void;
  last?: boolean;
  disabled?: boolean;
  badge?: number;
}) {
  return (
    <TouchableOpacity
      style={[styles.menuItem, !last && styles.menuItemBorder, disabled && styles.menuItemDisabled]}
      activeOpacity={disabled ? 1 : 0.75}
      onPress={disabled ? undefined : onPress}
    >
      <View style={styles.menuIconWrap}>
        <AppIcon name={icon} size={18} color={Colors.primary} />
      </View>
      <View style={styles.menuContent}>
        <View style={styles.menuLabelRow}>
          <Text style={styles.menuLabel}>{label}</Text>
          {badge !== undefined && badge > 0 && (
            <View style={styles.menuBadge}>
              <Text style={styles.menuBadgeText}>{badge > 99 ? '99+' : String(badge)}</Text>
            </View>
          )}
        </View>
        <Text style={styles.menuDescription}>{description}</Text>
      </View>
      <View style={styles.menuRight}>
        {rightText ? <Text style={styles.menuRightText}>{rightText}</Text> : null}
        <Text style={styles.menuArrow}>{disabled ? '·' : '›'}</Text>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  scrollContent: {
    padding: 20,
    paddingTop: Platform.OS === 'ios' ? 60 : 24,
    paddingBottom: 40,
    gap: 20,
  },
  pageTitle: {
    color: Colors.textActive,
    fontSize: 28,
    fontWeight: '800',
  },
  pageSub: {
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: -8,
  },
  loginPrompt: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  loginTitle: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '700',
    marginTop: 16,
  },
  loginHint: {
    color: Colors.textMuted,
    fontSize: 14,
    marginTop: 8,
    marginBottom: 24,
  },
  loginBtn: {
    backgroundColor: Colors.primary,
    borderRadius: 8,
    paddingHorizontal: 32,
    paddingVertical: 14,
  },
  loginBtnText: {
    color: Colors.background,
    fontSize: 16,
    fontWeight: '700',
  },
  headerCard: {
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 18,
    gap: 18,
    ...Shadows.card,
  },
  headerRow: {
    flexDirection: 'row',
    gap: 16,
  },
  avatarWrap: {
    position: 'relative',
    alignSelf: 'flex-start',
  },
  levelBadge: {
    position: 'absolute',
    right: -2,
    bottom: -4,
    backgroundColor: Colors.primary,
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  levelText: {
    color: Colors.background,
    fontSize: 10,
    fontWeight: '800',
  },
  headerInfo: {
    flex: 1,
    gap: 6,
    minWidth: 0,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 8,
  },
  displayName: {
    color: Colors.textActive,
    fontSize: 28,
    fontWeight: '800',
  },
  roleBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  roleText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '700',
  },
  metaLine: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 18,
  },
  bioText: {
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 4,
  },
  editBtn: {
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  editBtnText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  tilesRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 16,
  },
  tile: {
    flexGrow: 1,
    flexBasis: 220,
    minHeight: 172,
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 18,
    gap: 10,
  },
  tileIconWrap: {
    width: 42,
    height: 42,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  tileIcon: {
    fontSize: 20,
  },
  tileTitle: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
  },
  tileDesc: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
    flex: 1,
  },
  tileCta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  tileCtaText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
  },
  tileCtaArrow: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
  },
  menuCard: {
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    overflow: 'hidden',
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingHorizontal: 18,
    paddingVertical: 16,
  },
  menuItemDisabled: {
    opacity: 0.55,
  },
  menuItemBorder: {
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  menuIconWrap: {
    width: 34,
    height: 34,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceAlt,
  },
  menuIcon: {
    fontSize: 16,
  },
  menuContent: {
    flex: 1,
    gap: 4,
  },
  menuLabelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  menuLabel: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  menuBadge: {
    minWidth: 16,
    height: 16,
    paddingHorizontal: 5,
    borderRadius: 8,
    backgroundColor: '#ff3b30',
    alignItems: 'center',
    justifyContent: 'center',
  },
  menuBadgeText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: '700',
  },
  menuDescription: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },
  menuRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  menuRightText: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  menuArrow: {
    color: Colors.textMuted,
    fontSize: 18,
  },
  destructRow: {
    flexDirection: 'row',
    gap: 12,
  },
  logoutBtn: {
    flex: 1,
    minHeight: 54,
    borderRadius: 14,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: 8,
  },
  deleteBtn: {
    flex: 1,
    minHeight: 54,
    borderRadius: 14,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: 8,
    opacity: 0.78,
  },
  logoutIcon: {
    color: Colors.down,
    fontSize: 15,
  },
  logoutText: {
    color: Colors.down,
    fontSize: 14,
    fontWeight: '700',
  },
  deleteIcon: {
    color: Colors.textMuted,
    fontSize: 15,
  },
  deleteText: {
    color: Colors.textMuted,
    fontSize: 14,
    fontWeight: '700',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  modalCard: {
    width: '100%',
    maxWidth: 560,
    borderRadius: 20,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    gap: 16,
  },
  modalHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  modalTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
  },
  modalSubtitle: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 4,
  },
  modalCloseBtn: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceAlt,
  },
  modalCloseText: {
    color: Colors.textMuted,
    fontSize: 22,
    lineHeight: 22,
  },
  formGroup: {
    gap: 8,
  },
  avatarUploaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    padding: 12,
  },
  avatarUploaderMeta: {
    flex: 1,
    gap: 10,
  },
  avatarUploaderHint: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },
  avatarUploadMetaText: {
    color: Colors.textSecondary,
    fontSize: 11,
    lineHeight: 16,
  },
  avatarProgressTrack: {
    width: '100%',
    height: 7,
    borderRadius: 999,
    backgroundColor: Colors.border,
    overflow: 'hidden',
  },
  avatarProgressFill: {
    height: '100%',
    borderRadius: 999,
    backgroundColor: Colors.primary,
  },
  avatarUploadStatusText: {
    color: Colors.textMuted,
    fontSize: 11,
    lineHeight: 16,
  },
  avatarUploadBtn: {
    alignSelf: 'flex-start',
    borderRadius: 10,
    backgroundColor: Colors.primary,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  avatarUploadBtnText: {
    color: Colors.background,
    fontSize: 12,
    fontWeight: '800',
  },
  formLabel: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  formInput: {
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    color: Colors.textActive,
    fontSize: 14,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  formTextarea: {
    minHeight: 96,
    textAlignVertical: 'top',
  },
  saveBtn: {
    marginTop: 4,
    borderRadius: 12,
    backgroundColor: Colors.primary,
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  saveBtnDisabled: {
    opacity: 0.6,
  },
  saveBtnText: {
    color: Colors.background,
    fontSize: 14,
    fontWeight: '800',
  },
});
