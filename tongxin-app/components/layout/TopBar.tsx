import { View, Text, TextInput, TouchableOpacity, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import AppIcon from '../ui/AppIcon';

interface TopBarProps {
  searchQuery: string;
  onSearchChange: (text: string) => void;
  wsConnected: boolean;
}

export default function TopBar({ searchQuery, onSearchChange, wsConnected }: TopBarProps) {
  const { t } = useTranslation();
  const user = useAuthStore((s) => s.user);

  return (
    <View style={styles.container}>
      {/* Search */}
      <View style={styles.searchBox}>
        <AppIcon name="search" size={14} color={Colors.textMuted} />
        <TextInput
          style={styles.searchInput}
          placeholder={t('market.searchPairs')}
          placeholderTextColor={Colors.textMuted}
          value={searchQuery}
          onChangeText={onSearchChange}
        />
        {searchQuery.length > 0 && (
          <TouchableOpacity onPress={() => onSearchChange('')}>
            <Text style={styles.clearBtn}>✕</Text>
          </TouchableOpacity>
        )}
      </View>

      <View style={{ flex: 1 }} />

      {/* Right Actions */}
      <View style={styles.rightSection}>
        {/* WS Status */}
        <View style={styles.statusBadge}>
          <View style={[styles.statusDot, { backgroundColor: wsConnected ? Colors.online : Colors.offline }]} />
          <Text style={styles.statusText}>
            {wsConnected ? t('market.wsConnected') : t('market.wsDisconnected')}
          </Text>
        </View>

        {/* Notification */}
        <TouchableOpacity style={styles.iconBtn}>
          <AppIcon name="bell" size={16} color={Colors.textSecondary} />
        </TouchableOpacity>

        {/* User Avatar */}
        <TouchableOpacity style={styles.userArea}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>
              {(user?.displayName || user?.email || 'U').charAt(0).toUpperCase()}
            </Text>
          </View>
          {user && (
            <View style={[styles.vipBadge, (user.vipLevel ?? 0) >= 3 && { backgroundColor: '#FFB800' }]}>
              <Text style={styles.vipBadgeText}>V{user.vipLevel ?? 0}</Text>
            </View>
          )}
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    height: Sizes.topBarHeight,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.topBarBg,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 20,
    gap: 16,
  },
  // Search
  searchBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 12,
    height: 40,
    minWidth: 240,
    maxWidth: 360,
  },
  searchIcon: {
    fontSize: 13,
    marginRight: 8,
  },
  searchInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 14,
  },
  clearBtn: {
    color: Colors.textMuted,
    fontSize: 14,
    paddingLeft: 8,
  },
  // Right
  rightSection: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: 20,
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  statusDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    marginRight: 6,
  },
  statusText: {
    color: Colors.textSecondary,
    fontSize: 11,
    fontWeight: '500',
  },
  iconBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  iconEmoji: {
    fontSize: 16,
  },
  userArea: {
    marginLeft: 4,
    position: 'relative' as const,
  },
  vipBadge: {
    position: 'absolute' as const,
    bottom: -4,
    right: -6,
    backgroundColor: '#C9A84C',
    borderRadius: 6,
    paddingHorizontal: 4,
    paddingVertical: 1,
    borderWidth: 1.5,
    borderColor: Colors.topBarBg,
  },
  vipBadgeText: {
    color: '#000',
    fontSize: 8,
    fontWeight: '700' as const,
  },
  avatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '700',
  },
});
