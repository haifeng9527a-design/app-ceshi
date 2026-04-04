import { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useRouter, usePathname } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';

interface NavItem {
  key: string;
  label: string;
  icon: string;
  route: string;
}

const COLLAPSED_WIDTH = 64;
const EXPANDED_WIDTH = Sizes.sidePanelWidth; // 256

export default function Sidebar() {
  const { t } = useTranslation();
  const router = useRouter();
  const pathname = usePathname();
  const { user, signOut } = useAuthStore();
  const [collapsed, setCollapsed] = useState(false);

  const navItems: NavItem[] = [
    { key: 'market', label: t('nav.market'), icon: '📊', route: '/(tabs)/market' },
    { key: 'watchlist', label: t('nav.watchlist'), icon: '⭐', route: '/(tabs)/market' },
    { key: 'trading', label: t('nav.trading'), icon: '📈', route: '/(tabs)/trading' },
    { key: 'rankings', label: t('nav.rankings'), icon: '🏆', route: '/(tabs)/rankings' },
    { key: 'messages', label: t('messages.title'), icon: '💬', route: '/(tabs)/messages' },
    { key: 'profile', label: t('nav.profile'), icon: '👤', route: '/(tabs)/profile' },
  ];

  const isActive = (route: string) => pathname.includes(route.replace('/(tabs)', ''));

  return (
    <View style={[styles.container, { width: collapsed ? COLLAPSED_WIDTH : EXPANDED_WIDTH }]}>
      {/* Logo + Toggle */}
      <View style={[styles.logoArea, collapsed && styles.logoAreaCollapsed]}>
        {collapsed ? (
          <TouchableOpacity
            style={styles.logoIcon}
            onPress={() => setCollapsed(false)}
            activeOpacity={0.7}
          >
            <Text style={styles.logoEmoji}>🏛️</Text>
          </TouchableOpacity>
        ) : (
          <>
            <View style={styles.logoIcon}>
              <Text style={styles.logoEmoji}>🏛️</Text>
            </View>
            <View style={styles.logoTextWrap}>
              <Text style={styles.logoTitle}>Sovereign</Text>
              <Text style={styles.logoSub}>Digital Vault</Text>
            </View>
          </>
        )}
      </View>

      {/* Collapse toggle button */}
      <TouchableOpacity
        style={[styles.collapseBtn, collapsed && styles.collapseBtnCollapsed]}
        onPress={() => setCollapsed((c) => !c)}
        activeOpacity={0.7}
      >
        <Text style={styles.collapseIcon}>{collapsed ? '»' : '«'}</Text>
      </TouchableOpacity>

      {/* Nav Items */}
      <View style={[styles.navSection, collapsed && styles.navSectionCollapsed]}>
        {navItems.map((item) => {
          const active = isActive(item.route);
          return (
            <TouchableOpacity
              key={item.key}
              style={[
                styles.navItem,
                active && styles.navItemActive,
                collapsed && styles.navItemCollapsed,
              ]}
              activeOpacity={0.7}
              onPress={() => router.push(item.route as any)}
            >
              <Text style={[styles.navIcon, collapsed && styles.navIconCollapsed]}>
                {item.icon}
              </Text>
              {!collapsed && (
                <Text style={[styles.navLabel, active && styles.navLabelActive]}>
                  {item.label}
                </Text>
              )}
              {active && !collapsed && <View style={styles.activeDot} />}
            </TouchableOpacity>
          );
        })}
      </View>

      {/* Spacer */}
      <View style={{ flex: 1 }} />

      {/* User / Auth Section */}
      <View style={[styles.bottomSection, collapsed && styles.bottomSectionCollapsed]}>
        {user ? (
          <>
            {/* User info */}
            <TouchableOpacity
              style={[styles.userInfo, collapsed && styles.userInfoCollapsed]}
              onPress={() => router.push('/(tabs)/profile' as any)}
              activeOpacity={0.7}
            >
              <View style={styles.userAvatar}>
                <Text style={styles.userAvatarText}>
                  {(user.displayName || user.email || '?').charAt(0).toUpperCase()}
                </Text>
              </View>
              {!collapsed && (
                <View style={{ flex: 1 }}>
                  <Text style={styles.userName} numberOfLines={1}>
                    {user.displayName || 'User'}
                  </Text>
                  <Text style={styles.userEmail} numberOfLines={1}>{user.email}</Text>
                </View>
              )}
            </TouchableOpacity>

            {/* Logout */}
            <TouchableOpacity
              style={[styles.settingsItem, collapsed && styles.settingsItemCollapsed]}
              activeOpacity={0.7}
              onPress={async () => { await signOut(); router.replace('/'); }}
            >
              <Text style={[styles.navIcon, collapsed && styles.navIconCollapsed]}>🚪</Text>
              {!collapsed && (
                <Text style={[styles.navLabel, { color: Colors.down }]}>{t('auth.logout')}</Text>
              )}
            </TouchableOpacity>
          </>
        ) : (
          <TouchableOpacity
            style={[styles.walletBtn, collapsed && styles.walletBtnCollapsed]}
            activeOpacity={0.8}
            onPress={() => router.push('/(auth)/login' as any)}
          >
            <Text style={styles.walletIcon}>🔐</Text>
            {!collapsed && <Text style={styles.walletText}>{t('auth.loginOrRegister')}</Text>}
          </TouchableOpacity>
        )}

        {/* Settings */}
        <TouchableOpacity
          style={[styles.settingsItem, collapsed && styles.settingsItemCollapsed]}
          activeOpacity={0.7}
        >
          <Text style={[styles.navIcon, collapsed && styles.navIconCollapsed]}>⚙️</Text>
          {!collapsed && <Text style={styles.navLabel}>{t('nav.settings')}</Text>}
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: Colors.topBarBg,
    borderRightWidth: 1,
    borderRightColor: Colors.border,
    paddingVertical: 20,
  },

  /* ── Logo ── */
  logoArea: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    marginBottom: 20,
  },
  logoAreaCollapsed: {
    justifyContent: 'center',
    paddingHorizontal: 0,
  },
  logoIcon: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    justifyContent: 'center',
    alignItems: 'center',
  },
  logoEmoji: {
    fontSize: 20,
  },
  logoTextWrap: {
    marginLeft: 12,
  },
  logoTitle: {
    color: Colors.primary,
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  logoSub: {
    color: Colors.textMuted,
    fontSize: 11,
    letterSpacing: 1,
    marginTop: 1,
  },

  /* ── Collapse toggle ── */
  collapseBtn: {
    alignSelf: 'flex-end',
    marginRight: 12,
    marginBottom: 12,
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: 'rgba(42, 42, 42, 0.6)',
    borderWidth: 1,
    borderColor: 'rgba(77, 70, 53, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  collapseBtnCollapsed: {
    alignSelf: 'center',
    marginRight: 0,
  },
  collapseIcon: {
    color: Colors.textMuted,
    fontSize: 14,
    fontWeight: '700',
  },

  /* ── Nav ── */
  navSection: {
    paddingHorizontal: 12,
    gap: 4,
  },
  navSectionCollapsed: {
    paddingHorizontal: 8,
    alignItems: 'center',
  },
  navItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: Sizes.borderRadiusSm,
  },
  navItemActive: {
    backgroundColor: Colors.primaryDim,
  },
  navItemCollapsed: {
    paddingHorizontal: 0,
    justifyContent: 'center',
    width: 44,
    height: 44,
    borderRadius: 10,
  },
  navIcon: {
    fontSize: 16,
    width: 28,
    textAlign: 'left',
  },
  navIconCollapsed: {
    width: 'auto',
    textAlign: 'center',
    fontSize: 18,
  },
  navLabel: {
    color: Colors.textSecondary,
    fontSize: 14,
    fontWeight: '500',
    flex: 1,
  },
  navLabelActive: {
    color: Colors.primary,
    fontWeight: '600',
  },
  activeDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.primary,
  },

  /* ── Bottom ── */
  bottomSection: {
    paddingHorizontal: 12,
    gap: 8,
  },
  bottomSectionCollapsed: {
    paddingHorizontal: 8,
    alignItems: 'center',
  },
  walletBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primary,
    paddingVertical: 12,
    borderRadius: Sizes.borderRadiusSm,
    gap: 8,
    ...Shadows.glow,
  },
  walletBtnCollapsed: {
    width: 44,
    height: 44,
    borderRadius: 10,
    paddingVertical: 0,
    gap: 0,
  },
  walletIcon: {
    fontSize: 14,
  },
  walletText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '700',
  },
  settingsItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: Sizes.borderRadiusSm,
  },
  settingsItemCollapsed: {
    paddingHorizontal: 0,
    justifyContent: 'center',
    width: 44,
    height: 44,
    borderRadius: 10,
  },

  /* ── User info ── */
  userInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    gap: 10,
  },
  userInfoCollapsed: {
    paddingHorizontal: 0,
    justifyContent: 'center',
    gap: 0,
  },
  userAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  userAvatarText: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '700',
  },
  userName: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '600',
  },
  userEmail: {
    color: Colors.textMuted,
    fontSize: 11,
  },
});
