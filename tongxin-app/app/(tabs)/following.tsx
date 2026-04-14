import { useState, useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  RefreshControl,
  Alert,
  useWindowDimensions,
} from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import AppIcon from '../../components/ui/AppIcon';
import {
  getMyWatchedTraders,
  unwatchTrader,
  FollowedTrader,
} from '../../services/api/traderApi';

export default function FollowingScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;
  const user = useAuthStore((s) => s.user);

  const [traders, setTraders] = useState<FollowedTrader[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadData = useCallback(async () => {
    if (!user) { setLoading(false); return; }
    try {
      const data = await getMyWatchedTraders();
      setTraders(data || []);
    } catch {
      // ignore
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [user]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      loadData();
    }, [loadData])
  );

  const handleRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  const handleUnwatch = async (traderUid: string, name: string) => {
    Alert.alert(
      '取消关注',
      `确定取消关注 ${name} 吗？`,
      [
        { text: '取消', style: 'cancel' },
        {
          text: '确定',
          style: 'destructive',
          onPress: async () => {
            try {
              await unwatchTrader(traderUid);
              setTraders((prev) => prev.filter((t) => t.uid !== traderUid));
            } catch (e: any) {
              Alert.alert('Error', e.response?.data?.error || e.message);
            }
          },
        },
      ]
    );
  };

  if (!user) {
    return (
      <View style={styles.centered}>
        <AppIcon name="lock" size={28} color={Colors.textMuted} />
        <Text style={styles.emptyTitle}>请先登录</Text>
        <Text style={styles.emptySubtitle}>登录后可查看关注列表</Text>
        <TouchableOpacity
          style={styles.loginBtn}
          onPress={() => router.push('/(auth)/login' as any)}
        >
          <Text style={styles.loginBtnText}>去登录</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  const renderTrader = ({ item }: { item: FollowedTrader }) => {
    const stats = item.stats;
    const pnl = stats?.total_pnl || 0;
    const winRate = stats?.win_rate || 0;
    const followers = stats?.followers_count || 0;

    let statusLabel = '仅关注';
    let statusColor = Colors.textMuted;
    let statusBg = Colors.surfaceAlt;
    if (item.is_copying && item.copy_status === 'active') {
      statusLabel = '跟单中';
      statusColor = Colors.up;
      statusBg = Colors.upDim;
    } else if (item.is_copying && item.copy_status === 'paused') {
      statusLabel = '已暂停';
      statusColor = '#F0B90B';
      statusBg = 'rgba(240, 185, 11, 0.12)';
    }

    return (
      <TouchableOpacity
        style={[styles.traderCard, isDesktop && styles.traderCardDesktop]}
        activeOpacity={0.7}
        onPress={() => router.push(`/(tabs)/rankings?trader=${item.uid}` as any)}
      >
        {/* Header: Avatar + Name + Status */}
        <View style={styles.cardHeader}>
          <View style={styles.cardLeft}>
            <View style={styles.avatar}>
              <Text style={styles.avatarText}>
                {(item.display_name || '?')[0].toUpperCase()}
              </Text>
            </View>
            <View style={styles.nameCol}>
              <View style={styles.nameRow}>
                <Text style={styles.traderName} numberOfLines={1}>{item.display_name}</Text>
                {item.is_trader && (
                  <View style={styles.eliteBadge}>
                    <Text style={styles.eliteBadgeText}>ELITE</Text>
                  </View>
                )}
              </View>
              <Text style={styles.followDate}>
                关注于 {new Date(item.followed_at).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' })}
              </Text>
            </View>
          </View>
          <View style={[styles.statusTag, { backgroundColor: statusBg }]}>
            <Text style={[styles.statusTagText, { color: statusColor }]}>{statusLabel}</Text>
          </View>
        </View>

        {/* Stats Row */}
        <View style={styles.statsRow}>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>总盈亏</Text>
            <Text style={[styles.statValue, { color: pnl >= 0 ? Colors.up : Colors.down }]}>
              {pnl >= 0 ? '+' : ''}${formatMoney(pnl)}
            </Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>胜率</Text>
            <Text style={[styles.statValue, { color: winRate >= 50 ? Colors.up : Colors.down }]}>
              {winRate.toFixed(1)}%
            </Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>跟随</Text>
            <Text style={styles.statValue}>{followers}</Text>
          </View>
        </View>

        {/* Action Row */}
        <View style={styles.actionRow}>
          <TouchableOpacity
            style={styles.unwatchBtn}
            onPress={() => handleUnwatch(item.uid, item.display_name)}
          >
            <Text style={styles.unwatchBtnText}>取消关注</Text>
          </TouchableOpacity>
          {!item.is_copying && item.allow_copy_trading && (
            <TouchableOpacity
              style={styles.copyBtn}
              onPress={() => router.push(`/(tabs)/rankings?trader=${item.uid}` as any)}
            >
              <Text style={styles.copyBtnText}>一键跟单</Text>
            </TouchableOpacity>
          )}
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <View style={styles.container}>
      {/* Page Header */}
      <View style={styles.pageHeader}>
        <Text style={styles.pageTitle}>关注列表</Text>
        <Text style={styles.pageSubtitle}>
          {traders.length > 0 ? `已关注 ${traders.length} 位交易员` : ''}
        </Text>
      </View>

      {traders.length === 0 ? (
        <View style={styles.centered}>
          <AppIcon name="eye" size={28} color={Colors.textMuted} />
          <Text style={styles.emptyTitle}>暂无关注</Text>
          <Text style={styles.emptySubtitle}>去排行榜发现优秀交易员</Text>
          <TouchableOpacity
            style={styles.loginBtn}
            onPress={() => router.push('/(tabs)/rankings' as any)}
          >
            <Text style={styles.loginBtnText}>去排行榜</Text>
          </TouchableOpacity>
        </View>
      ) : (
        <FlatList
          data={traders}
          keyExtractor={(item) => item.uid}
          renderItem={renderTrader}
          contentContainerStyle={[
            styles.listContent,
            isDesktop && { maxWidth: 800, alignSelf: 'center', width: '100%' },
          ]}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor={Colors.primary}
            />
          }
          showsVerticalScrollIndicator={false}
        />
      )}
    </View>
  );
}

function formatMoney(n: number): string {
  return Math.abs(n).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 40,
  },

  // Page Header
  pageHeader: {
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    backgroundColor: Colors.topBarBg,
  },
  pageTitle: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
  pageSubtitle: {
    color: Colors.textMuted,
    fontSize: 13,
    marginTop: 4,
  },

  // List
  listContent: {
    padding: 16,
    gap: 12,
  },

  // Trader Card
  traderCard: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    ...Shadows.card,
  },
  traderCardDesktop: {
    padding: 20,
  },

  // Card Header
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 14,
  },
  cardLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    flex: 1,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 12,
    backgroundColor: Colors.surfaceAlt,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  avatarText: {
    color: Colors.primary,
    fontSize: 20,
    fontWeight: '800',
  },
  nameCol: {
    flex: 1,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  traderName: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
  },
  eliteBadge: {
    backgroundColor: Colors.primary,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
  },
  eliteBadgeText: {
    color: Colors.textOnPrimary,
    fontSize: 8,
    fontWeight: '800',
    letterSpacing: 1,
  },
  followDate: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
  },

  // Status Tag
  statusTag: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 6,
  },
  statusTagText: {
    fontSize: 11,
    fontWeight: '700',
  },

  // Stats Row
  statsRow: {
    flexDirection: 'row',
    gap: 16,
    paddingVertical: 12,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    marginBottom: 12,
  },
  statItem: {
    flex: 1,
  },
  statLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: 4,
  },
  statValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },

  // Action Row
  actionRow: {
    flexDirection: 'row',
    gap: 10,
  },
  unwatchBtn: {
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
  },
  unwatchBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '600',
  },
  copyBtn: {
    backgroundColor: Colors.primary,
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 10,
    ...Shadows.glow,
  },
  copyBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 13,
    fontWeight: '700',
  },

  // Empty State
  emptyTitle: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 8,
  },
  emptySubtitle: {
    color: Colors.textMuted,
    fontSize: 14,
    marginBottom: 20,
  },
  loginBtn: {
    backgroundColor: Colors.primary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 10,
    ...Shadows.glow,
  },
  loginBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '700',
  },
});
