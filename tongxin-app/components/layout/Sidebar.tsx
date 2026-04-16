import { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { useRouter, usePathname } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import { useMessagesStore } from '../../services/store/messagesStore';
import { marketWs } from '../../services/websocket/marketWs';
import AppIcon, { type AppIconName } from '../ui/AppIcon';

interface NavItem {
  key: string;
  label: string;
  icon: AppIconName;
  route: string;
}

const COLLAPSED_WIDTH = 64;
const EXPANDED_WIDTH = Sizes.sidePanelWidth; // 256

export default function Sidebar() {
  const { t } = useTranslation();
  const router = useRouter();
  const pathname = usePathname();
  const { user, signOut } = useAuthStore();
  const totalUnread = useMessagesStore((s) => s.totalUnread);
  const [collapsed, setCollapsed] = useState(false);

  // Network status
  const [netConnected, setNetConnected] = useState(true);
  const [netLatency, setNetLatency] = useState(-1);
  useEffect(() => {
    const handler = (msg: any) => {
      if (msg.type === 'ws_status') {
        setNetConnected(msg.connected);
        if (!msg.connected) setNetLatency(-1);
      }
      if (msg.type === 'ws_latency') {
        setNetLatency(msg.latency);
        setNetConnected(true);
      }
    };
    marketWs.onMessage(handler);
    return () => { marketWs.offMessage(handler); };
  }, []);

  const navItems: NavItem[] = [
    { key: 'market', label: t('nav.market'), icon: 'market', route: '/(tabs)/market' },
    { key: 'watchlist', label: t('nav.watchlist'), icon: 'watchlist', route: '/(tabs)/watchlist' },
    { key: 'following', label: t('nav.following'), icon: 'eye', route: '/(tabs)/following' },
    { key: 'trading', label: t('nav.trading'), icon: 'trading', route: '/(tabs)/trading' },
    { key: 'spot', label: t('nav.spot'), icon: 'bitcoin', route: '/(tabs)/spot' },
    { key: 'assets', label: t('nav.assets'), icon: 'wallet', route: '/(tabs)/portfolio' },
    { key: 'trader-center', label: t('nav.traderCenter'), icon: 'badge', route: '/(tabs)/trader-center' },
    { key: 'rankings', label: t('nav.rankings'), icon: 'trophy', route: '/(tabs)/rankings' },
    { key: 'messages', label: t('messages.title'), icon: 'message', route: '/(tabs)/messages' },
    { key: 'profile', label: t('nav.profile'), icon: 'user', route: '/(tabs)/profile' },
  ];

  const isActive = (route: string) => pathname.includes(route.replace('/(tabs)', ''));

  // 收起状态下图标没有文字，桌面端希望 hover 时显示功能名。
  // React Native Web 会吃掉 title prop（只保留 aria-label），而浏览器原生 tooltip 只认 title 属性。
  // 所以用 ref 回调拿到底层 DOM 节点后直接 setAttribute('title', ...) 才能真正显示 tooltip。
  const tooltip = (label: string) =>
    Platform.OS === 'web'
      ? ({
          ref: (el: any) => {
            if (el && typeof el.setAttribute === 'function') {
              el.setAttribute('title', label);
            }
          },
          accessibilityLabel: label,
        } as any)
      : {};

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
            <AppIcon name="building" size={22} color={Colors.primary} />
          </TouchableOpacity>
        ) : (
          <>
            <View style={styles.logoIcon}>
              <AppIcon name="building" size={22} color={Colors.primary} />
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
        {...tooltip(collapsed ? t('common.expand') : t('common.collapse'))}
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
              {...tooltip(item.label)}
            >
              <View style={{ position: 'relative' }}>
                <View style={[styles.navIcon, collapsed && styles.navIconCollapsed]}>
                  <AppIcon
                    name={item.icon}
                    size={18}
                    color={active ? Colors.primary : Colors.textSecondary}
                  />
                </View>
                {item.key === 'messages' && totalUnread > 0 && collapsed && (
                  <View style={styles.badgeDotSmall} />
                )}
              </View>
              {!collapsed && (
                <Text style={[styles.navLabel, active && styles.navLabelActive]}>
                  {item.label}
                </Text>
              )}
              {item.key === 'messages' && totalUnread > 0 && !collapsed && (
                <View style={styles.unreadBadge}>
                  <Text style={styles.unreadBadgeText}>
                    {totalUnread > 99 ? '99+' : totalUnread}
                  </Text>
                </View>
              )}
              {active && !collapsed && item.key !== 'messages' && <View style={styles.activeDot} />}
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
              {...tooltip(user.displayName || user.email || t('nav.profile'))}
            >
              <View style={styles.userAvatar}>
                <Text style={styles.userAvatarText}>
                  {(user.displayName || user.email || '?').charAt(0).toUpperCase()}
                </Text>
              </View>
              {!collapsed && (
                <View style={{ flex: 1 }}>
                  <Text style={styles.userName} numberOfLines={1}>
                    {user.displayName || t('auth.notLoggedIn')}
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
              {...tooltip(t('auth.logout'))}
            >
              <View style={[styles.navIcon, collapsed && styles.navIconCollapsed]}>
                <AppIcon name="logout" size={18} color={Colors.down} />
              </View>
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
            {...tooltip(t('auth.loginOrRegister'))}
          >
            <AppIcon name="lock" size={18} color={Colors.background} />
            {!collapsed && <Text style={styles.walletText}>{t('auth.loginOrRegister')}</Text>}
          </TouchableOpacity>
        )}

        {/* Settings */}
        <TouchableOpacity
          style={[styles.settingsItem, collapsed && styles.settingsItemCollapsed]}
          activeOpacity={0.7}
          {...tooltip(t('nav.settings'))}
        >
          <View style={[styles.navIcon, collapsed && styles.navIconCollapsed]}>
            <AppIcon name="settings" size={18} color={Colors.textSecondary} />
          </View>
          {!collapsed && <Text style={styles.navLabel}>{t('nav.settings')}</Text>}
        </TouchableOpacity>

        {/* Network Status */}
        <View style={[styles.netStatus, collapsed && styles.netStatusCollapsed]}>
          <View style={[styles.netDot, { backgroundColor: !netConnected ? '#F6465D' : netLatency < 100 ? '#0ECB81' : netLatency < 300 ? '#F0B90B' : '#F6465D' }]} />
          {!collapsed && (
            <Text style={[styles.netText, { color: !netConnected ? '#F6465D' : netLatency < 100 ? '#0ECB81' : netLatency < 300 ? '#F0B90B' : '#F6465D' }]}>
              {!netConnected ? t('market.networkOffline') : netLatency >= 0 ? `${netLatency}ms` : t('common.loading')}
            </Text>
          )}
        </View>
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
    width: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  navIconCollapsed: {
    width: 20,
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
  unreadBadge: {
    backgroundColor: '#F6465D',
    minWidth: 20,
    height: 20,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 5,
  },
  unreadBadgeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  badgeDotSmall: {
    position: 'absolute',
    top: -2,
    right: -4,
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#F6465D',
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

  /* ── Network Status ── */
  netStatus: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    paddingHorizontal: 12,
    gap: 8,
  },
  netStatusCollapsed: {
    justifyContent: 'center',
    paddingHorizontal: 0,
    gap: 0,
  },
  netDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  netText: {
    fontSize: 12,
    fontWeight: '500',
    fontFamily: 'monospace',
  },
});
