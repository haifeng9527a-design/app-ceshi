import { useEffect, useMemo, useState } from 'react';
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
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import * as ImagePicker from 'expo-image-picker';
import apiClient from '../../services/api/client';
import { useAuthStore } from '../../services/store/authStore';
import { Colors, Sizes, Shadows } from '../../theme/colors';

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
  icon: string;
  onPress: () => void;
};

export default function ProfileScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const { user, signOut, syncProfile } = useAuthStore();
  const isDesktop = width >= 768;
  const [showEditProfile, setShowEditProfile] = useState(false);
  const [savingProfile, setSavingProfile] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [displayName, setDisplayName] = useState('');
  const [avatarUrl, setAvatarUrl] = useState('');
  const [phone, setPhone] = useState('');
  const [bio, setBio] = useState('');

  useEffect(() => {
    if (!user) return;
    setDisplayName(user.displayName || '');
    setAvatarUrl(user.photoURL || '');
    setPhone(user.phone || '');
    setBio(user.signature || '');
  }, [user?.uid, user?.displayName, user?.photoURL, user?.phone, user?.signature]);

  const handleSignOut = () => {
    Alert.alert(t('auth.logout'), '确定要退出登录吗？', [
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
      Alert.alert('提示', '昵称不能为空。');
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
      setShowEditProfile(false);
      Alert.alert('已更新', '个人资料已保存。');
    } catch (e: any) {
      Alert.alert('保存失败', e?.response?.data?.error || e?.message || '资料保存失败，请稍后重试。');
    } finally {
      setSavingProfile(false);
    }
  };

  const uploadAvatar = async (uri: string, fileName?: string | null, mimeType?: string | null) => {
    const formData = new FormData();
    const fallbackName = fileName || uri.split('/').pop() || 'avatar.jpg';
    const ext = fallbackName.split('.').pop()?.toLowerCase() || 'jpg';
    const resolvedMimeType =
      mimeType || (ext === 'png' ? 'image/png' : ext === 'gif' ? 'image/gif' : 'image/jpeg');

    formData.append('file', {
      uri,
      name: fallbackName,
      type: resolvedMimeType,
    } as any);

    const { data } = await apiClient.post('/api/upload', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });

    const rawUrl = data?.url || '';
    if (!rawUrl) {
      throw new Error('上传成功但未返回图片地址');
    }
    return rawUrl.startsWith('http') ? rawUrl : `${apiClient.defaults.baseURL}${rawUrl}`;
  };

  const handlePickAvatar = async () => {
    try {
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsEditing: true,
        aspect: [1, 1],
        quality: 0.85,
      });

      if (result.canceled || !result.assets?.[0]) return;

      const asset = result.assets[0];
      setUploadingAvatar(true);
      const uploadedUrl = await uploadAvatar(asset.uri, asset.fileName, asset.mimeType);
      setAvatarUrl(uploadedUrl);
      Alert.alert('上传成功', '头像已上传，保存资料后会同步到账号。');
    } catch (e: any) {
      Alert.alert('头像上传失败', e?.message || '请检查网络后重试。');
    } finally {
      setUploadingAvatar(false);
    }
  };

  const quickActions = useMemo<QuickAction[]>(
    () => [
      {
        key: 'trading',
        title: '交易中心',
        description: '快速进入交易页，查看资产、持仓与下单面板。',
        icon: '📊',
        onPress: () => router.push('/(tabs)/trading' as any),
      },
      {
        key: 'strategy',
        title: user?.isTrader ? '发布策略' : '交易员中心',
        description: user?.isTrader
          ? '进入交易员中心管理策略、跟单设置和交易员资料。'
          : '先进入交易员中心，查看认证与策略发布能力。',
        icon: '💡',
        onPress: () => router.push('/(tabs)/trader-center' as any),
      },
      {
        key: 'friends',
        title: '交易玩友',
        description: '查看好友、好友申请和群聊相关入口。',
        icon: '👥',
        onPress: () => router.push('/contacts' as any),
      },
      {
        key: 'public-profile',
        title: '公开主页',
        description: user?.isTrader ? '查看外部用户看到的交易员主页。' : '成为交易员后，这里会显示你的公开主页。',
        icon: '🌐',
        onPress: () => {
          if (user?.isTrader) {
            router.push(`/trader/${user.uid}` as any);
            return;
          }
          Alert.alert('暂未开放', '当前账号还不是认证交易员，公开主页暂不可用。');
        },
      },
    ],
    [router, user?.isTrader, user?.uid],
  );
  const currentLanguageLabel = useMemo(() => (t('nav.profile') === '我的' ? '简体中文' : 'English'), [t]);

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
        <Text style={styles.pageTitle}>我的</Text>
        <Text style={styles.pageSub}>把账号资料、业务入口和设置放在一个真正可操作的面板里，而不是只展示静态菜单。</Text>

        <View style={styles.headerCard}>
          <View style={styles.headerRow}>
            <View style={styles.avatarWrap}>
              <AvatarCircle name={user.displayName || user.email || 'U'} imageUrl={user.photoURL} />
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
              <Text style={styles.metaLine}>Account ID: {user.shortId || '--'}</Text>
              <Text style={styles.metaLine}>Email: {user.email || '--'}</Text>
              {user.phone ? <Text style={styles.metaLine}>Phone: {user.phone}</Text> : null}
              {user.signature ? <Text style={styles.bioText}>{user.signature}</Text> : null}
            </View>
          </View>

          <TouchableOpacity style={styles.editBtn} activeOpacity={0.85} onPress={() => setShowEditProfile(true)}>
            <Text style={styles.editBtnText}>编辑资料</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.tilesRow}>
          {quickActions.map((action) => (
            <TouchableOpacity key={action.key} style={styles.tile} activeOpacity={0.85} onPress={action.onPress}>
              <View style={styles.tileIconWrap}>
                <Text style={styles.tileIcon}>{action.icon}</Text>
              </View>
              <Text style={styles.tileTitle}>{action.title}</Text>
              <Text style={styles.tileDesc}>{action.description}</Text>
              <View style={styles.tileCta}>
                <Text style={styles.tileCtaText}>进入</Text>
                <Text style={styles.tileCtaArrow}>→</Text>
              </View>
            </TouchableOpacity>
          ))}
        </View>

        <View style={styles.menuCard}>
          <MenuItem icon="👥" label="交易玩友" description="进入通讯录和好友管理" onPress={() => router.push('/contacts' as any)} />
          <MenuItem icon="❓" label="帮助中心" description="查看常见问题和使用说明" onPress={() => router.push('/help' as any)} />
          <MenuItem icon="🔒" label="隐私政策" description="查看平台数据与隐私说明" onPress={() => router.push('/privacy' as any)} />
          <MenuItem icon="🏪" label="交易员市场" description="查看排行榜和活跃交易员" onPress={() => router.push('/(tabs)/rankings' as any)} />
          <MenuItem icon="🤖" label="投诉建议" description="这一项交给 Claude 继续实现" disabled />
          <MenuItem
            icon="🌐"
            label="语言设置"
            description="切换中文或英文界面"
            rightText={currentLanguageLabel}
            onPress={() => router.push('/settings/language' as any)}
            last
          />
        </View>

        <View style={styles.destructRow}>
          <TouchableOpacity style={styles.logoutBtn} onPress={handleSignOut} activeOpacity={0.85}>
            <Text style={styles.logoutIcon}>↩</Text>
            <Text style={styles.logoutText}>退出登录</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.deleteBtn}
            activeOpacity={0.85}
            onPress={() => Alert.alert('暂不支持自助注销', '当前版本先不开放自助注销，请联系管理员或客服处理。')}
          >
            <Text style={styles.deleteIcon}>🗑</Text>
            <Text style={styles.deleteText}>注销账户</Text>
          </TouchableOpacity>
        </View>

        <View style={{ height: 36 }} />
      </ScrollView>

      <Modal visible={showEditProfile} transparent animationType="fade" onRequestClose={() => setShowEditProfile(false)}>
        <View style={styles.modalOverlay}>
          <View style={styles.modalCard}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>编辑资料</Text>
                <Text style={styles.modalSubtitle}>先把高频且已有接口支持的资料项做成闭环。</Text>
              </View>
              <TouchableOpacity style={styles.modalCloseBtn} activeOpacity={0.8} onPress={() => setShowEditProfile(false)}>
                <Text style={styles.modalCloseText}>×</Text>
              </TouchableOpacity>
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>昵称</Text>
              <TextInput
                style={styles.formInput}
                value={displayName}
                onChangeText={setDisplayName}
                placeholder="输入昵称"
                placeholderTextColor={Colors.textMuted}
              />
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>头像</Text>
              <View style={styles.avatarUploaderRow}>
                <AvatarCircle
                  name={displayName || user.email || 'U'}
                  size={68}
                  imageUrl={avatarUrl || user.photoURL}
                />
                <View style={styles.avatarUploaderMeta}>
                  <Text style={styles.avatarUploaderHint}>
                    直接从本地相册选择图片，系统会先上传头像文件，再在保存资料时更新到账号。
                  </Text>
                  <TouchableOpacity
                    style={[styles.avatarUploadBtn, uploadingAvatar && styles.saveBtnDisabled]}
                    activeOpacity={0.85}
                    disabled={uploadingAvatar}
                    onPress={() => void handlePickAvatar()}
                  >
                    {uploadingAvatar ? (
                      <ActivityIndicator size="small" color={Colors.background} />
                    ) : (
                      <Text style={styles.avatarUploadBtnText}>选择并上传头像</Text>
                    )}
                  </TouchableOpacity>
                </View>
              </View>
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>手机号</Text>
              <TextInput
                style={styles.formInput}
                value={phone}
                onChangeText={setPhone}
                placeholder="输入手机号"
                placeholderTextColor={Colors.textMuted}
                keyboardType="phone-pad"
              />
            </View>

            <View style={styles.formGroup}>
              <Text style={styles.formLabel}>个人简介</Text>
              <TextInput
                style={[styles.formInput, styles.formTextarea]}
                value={bio}
                onChangeText={setBio}
                placeholder="写一句介绍自己或交易风格的话"
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
                <Text style={styles.saveBtnText}>保存资料</Text>
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
}: {
  icon: string;
  label: string;
  description: string;
  rightText?: string;
  onPress?: () => void;
  last?: boolean;
  disabled?: boolean;
}) {
  return (
    <TouchableOpacity
      style={[styles.menuItem, !last && styles.menuItemBorder, disabled && styles.menuItemDisabled]}
      activeOpacity={disabled ? 1 : 0.75}
      onPress={disabled ? undefined : onPress}
    >
      <View style={styles.menuIconWrap}>
        <Text style={styles.menuIcon}>{icon}</Text>
      </View>
      <View style={styles.menuContent}>
        <Text style={styles.menuLabel}>{label}</Text>
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
  menuLabel: {
    color: Colors.textActive,
    fontSize: 14,
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
