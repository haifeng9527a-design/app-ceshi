import { View, Text, TouchableOpacity, StyleSheet, ScrollView, Alert, Platform, useWindowDimensions } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';

/* ════════════════════════════════════════
   Avatar Helper
   ════════════════════════════════════════ */

function AvatarCircle({ name, size = 80 }: { name: string; size?: number }) {
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
      }}
    >
      <Text style={{ color: Colors.primary, fontSize: size * 0.38, fontWeight: '800' }}>
        {letter}
      </Text>
    </View>
  );
}

/* ════════════════════════════════════════
   Main Page
   ════════════════════════════════════════ */

export default function ProfileScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user, signOut } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const handleSignOut = () => {
    Alert.alert(
      t('auth.logout'),
      '确定要退出登录吗？',
      [
        { text: t('common.cancel'), style: 'cancel' },
        {
          text: t('auth.logout'),
          style: 'destructive',
          onPress: async () => {
            await signOut();
            router.replace('/');
          },
        },
      ],
    );
  };

  // Not logged in state
  if (!user) {
    return (
      <View style={s.container}>
        <View style={s.loginPrompt}>
          <AvatarCircle name="?" size={80} />
          <Text style={s.loginTitle}>{t('auth.notLoggedIn')}</Text>
          <Text style={s.loginHint}>{t('auth.loginHint')}</Text>
          <TouchableOpacity
            style={s.loginBtn}
            onPress={() => router.push('/(auth)/login')}
            activeOpacity={0.8}
          >
            <Text style={s.loginBtnText}>{t('auth.loginOrRegister')}</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  return (
    <ScrollView
      style={s.container}
      contentContainerStyle={[
        s.scrollContent,
        isDesktop && { maxWidth: 720, alignSelf: 'center' as const, width: '100%' },
      ]}
      showsVerticalScrollIndicator={false}
    >
      {/* ── Profile Header Card ── */}
      <View style={s.headerCard}>
        <View style={s.headerRow}>
          {/* Avatar with level badge */}
          <View style={s.avatarWrap}>
            <AvatarCircle name={user.displayName || user.email || 'U'} size={80} />
            <View style={[s.levelBadge, (user.vipLevel ?? 0) >= 3 && { backgroundColor: '#FFB800' }]}>
              <Text style={s.levelText}>VIP{user.vipLevel ?? 0}</Text>
            </View>
          </View>

          {/* Info */}
          <View style={s.headerInfo}>
            <View style={s.nameRow}>
              <Text style={s.displayName}>{user.displayName || 'User'}</Text>
              {user.role && (
                <View style={s.roleBadge}>
                  <Text style={s.roleText}>{user.role}</Text>
                </View>
              )}
            </View>
            <View style={s.metaRow}>
              {user.shortId && (
                <Text style={s.metaItem}>
                  <Text style={s.metaLabel}>Account ID: </Text>
                  <Text style={s.metaValue}>{user.shortId}</Text>
                </Text>
              )}
              {user.email && (
                <Text style={s.metaItem}>
                  <Text style={s.metaLabel}>Email: </Text>
                  <Text style={s.metaValueNormal}>{user.email}</Text>
                </Text>
              )}
            </View>
          </View>
        </View>

        {/* Edit button */}
        <TouchableOpacity style={s.editBtn} activeOpacity={0.7}>
          <Text style={s.editBtnText}>编辑资料</Text>
        </TouchableOpacity>
      </View>

      {/* ── Action Tiles (Bento 2-col) ── */}
      <View style={s.tilesRow}>
        {/* 交易中心 */}
        <TouchableOpacity style={s.tile} activeOpacity={0.7}>
          <View style={s.tileIconWrap}>
            <Text style={s.tileIcon}>📊</Text>
          </View>
          <Text style={s.tileTitle}>交易中心</Text>
          <Text style={s.tileDesc}>实时查看市场动向，监控您的投资组合与资产波动。</Text>
          <View style={s.tileCta}>
            <Text style={s.tileCtaText}>立即进入</Text>
            <Text style={s.tileCtaArrow}>→</Text>
          </View>
        </TouchableOpacity>

        {/* 发布策略 */}
        <TouchableOpacity style={s.tile} activeOpacity={0.7}>
          <View style={s.tileIconWrap}>
            <Text style={s.tileIcon}>💡</Text>
          </View>
          <Text style={s.tileTitle}>发布策略</Text>
          <Text style={s.tileDesc}>构建并分享您的独家交易逻辑，吸引更多订阅者。</Text>
          <View style={s.tileCta}>
            <Text style={s.tileCtaText}>开始创作</Text>
            <Text style={s.tileCtaArrow}>→</Text>
          </View>
        </TouchableOpacity>
      </View>

      {/* ── Navigation List ── */}
      <View style={s.menuCard}>
        <MenuItem icon="👥" label="交易玩友 (Trader Friends)" onPress={() => {}} />
        <MenuItem icon="❓" label="帮助中心 (Help)" onPress={() => {}} />
        <MenuItem icon="🔒" label="隐私政策 (Privacy Policy)" onPress={() => {}} />
        <MenuItem icon="🏪" label="用户交易市场 (User Trading Center)" onPress={() => {}} />
        <MenuItem icon="📢" label="投诉建议 (Report)" onPress={() => {}} />
        <MenuItem
          icon="🌐"
          label="语言设置 (Language)"
          rightText="简体中文"
          onPress={() => {}}
          last
        />
      </View>

      {/* ── Destructive Actions ── */}
      <View style={s.destructRow}>
        <TouchableOpacity style={s.logoutBtn} onPress={handleSignOut} activeOpacity={0.7}>
          <Text style={s.logoutIcon}>↩</Text>
          <Text style={s.logoutText}>退出登录</Text>
        </TouchableOpacity>
        <TouchableOpacity style={s.deleteBtn} activeOpacity={0.7}>
          <Text style={s.deleteIcon}>🗑</Text>
          <Text style={s.deleteText}>注销账户</Text>
        </TouchableOpacity>
      </View>

      <View style={{ height: 40 }} />
    </ScrollView>
  );
}

/* ════════════════════════════════════════
   MenuItem
   ════════════════════════════════════════ */

function MenuItem({
  icon,
  label,
  rightText,
  onPress,
  last,
}: {
  icon: string;
  label: string;
  rightText?: string;
  onPress: () => void;
  last?: boolean;
}) {
  return (
    <TouchableOpacity
      style={[s.menuItem, !last && s.menuItemBorder]}
      onPress={onPress}
      activeOpacity={0.6}
    >
      <Text style={s.menuIcon}>{icon}</Text>
      <Text style={s.menuLabel}>{label}</Text>
      <View style={s.menuRight}>
        {rightText && <Text style={s.menuRightText}>{rightText}</Text>}
        <Text style={s.menuArrow}>›</Text>
      </View>
    </TouchableOpacity>
  );
}

/* ════════════════════════════════════════
   Styles
   ════════════════════════════════════════ */

const s = StyleSheet.create({
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

  /* ── Login prompt ── */
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

  /* ── Profile Header Card ── */
  headerCard: {
    backgroundColor: 'rgba(42, 42, 42, 0.4)',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.2)',
    padding: 24,
    gap: 20,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 20,
  },
  avatarWrap: {
    position: 'relative',
  },
  levelBadge: {
    position: 'absolute',
    bottom: -2,
    right: -2,
    backgroundColor: Colors.primary,
    borderRadius: 10,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderWidth: 2,
    borderColor: Colors.background,
  },
  levelText: {
    color: Colors.background,
    fontSize: 10,
    fontWeight: '700',
  },
  headerInfo: {
    flex: 1,
    gap: 6,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    flexWrap: 'wrap',
  },
  displayName: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
  roleBadge: {
    backgroundColor: Colors.primaryDim,
    borderRadius: 20,
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  roleText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '600',
  },
  metaRow: {
    gap: 4,
  },
  metaItem: {
    fontSize: 13,
  },
  metaLabel: {
    color: Colors.textMuted,
  },
  metaValue: {
    color: Colors.primaryLight,
    fontFamily: 'monospace',
  },
  metaValueNormal: {
    color: Colors.textSecondary,
  },
  editBtn: {
    backgroundColor: 'rgba(58, 57, 57, 0.6)',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.3)',
    paddingVertical: 10,
    alignItems: 'center',
  },
  editBtnText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '600',
  },

  /* ── Action Tiles ── */
  tilesRow: {
    flexDirection: 'row',
    gap: 14,
  },
  tile: {
    flex: 1,
    backgroundColor: 'rgba(42, 42, 42, 0.4)',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.1)',
    padding: 20,
    gap: 6,
  },
  tileIconWrap: {
    width: 44,
    height: 44,
    borderRadius: 10,
    backgroundColor: Colors.primaryDim,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  tileIcon: {
    fontSize: 24,
  },
  tileTitle: {
    color: Colors.textActive,
    fontSize: 17,
    fontWeight: '700',
  },
  tileDesc: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  tileCta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 12,
  },
  tileCtaText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  tileCtaArrow: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '700',
  },

  /* ── Navigation List ── */
  menuCard: {
    backgroundColor: 'rgba(28, 27, 27, 0.8)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.1)',
    overflow: 'hidden',
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 16,
    paddingHorizontal: 18,
  },
  menuItemBorder: {
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77, 70, 53, 0.1)',
  },
  menuIcon: {
    fontSize: 18,
    marginRight: 14,
    opacity: 0.8,
  },
  menuLabel: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '500',
  },
  menuRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  menuRightText: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  menuArrow: {
    color: Colors.textMuted,
    fontSize: 22,
    fontWeight: '300',
  },

  /* ── Destructive Actions ── */
  destructRow: {
    flexDirection: 'row',
    gap: 12,
  },
  logoutBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 14,
    borderRadius: 10,
    backgroundColor: 'rgba(28, 27, 27, 0.8)',
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.1)',
  },
  logoutIcon: {
    fontSize: 16,
    color: Colors.down,
  },
  logoutText: {
    color: Colors.down,
    fontSize: 14,
    fontWeight: '600',
  },
  deleteBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 14,
    borderRadius: 10,
    backgroundColor: 'rgba(28, 27, 27, 0.8)',
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.1)',
  },
  deleteIcon: {
    fontSize: 14,
    opacity: 0.5,
  },
  deleteText: {
    color: Colors.textMuted,
    fontSize: 14,
    fontWeight: '500',
  },
});
