import { useState, useCallback, useMemo } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  RefreshControl,
  useWindowDimensions,
} from 'react-native';
import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Shadows } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import AppIcon from '../../components/ui/AppIcon';
import { showAlert, showConfirm } from '../../services/utils/dialog';
import {
  getMyWatchedTraders,
  unwatchTrader,
  FollowedTrader,
} from '../../services/api/traderApi';
import {
  getTraderStrategies,
  TraderStrategy,
} from '../../services/api/traderStrategyApi';

interface FollowingWorkbenchProps {
  embedded?: boolean;
}

const STRATEGY_CATEGORY_LABELS: Record<string, string> = {
  technical: 'strategy.categoryTechnical',
  fundamental: 'strategy.categoryFundamental',
  macro: 'strategy.categoryMacro',
  news: 'strategy.categoryNews',
  education: 'strategy.categoryEducation',
  other: 'strategy.categoryOther',
};

export function FollowingWorkbench({ embedded = false }: FollowingWorkbenchProps) {
  const { t } = useTranslation();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 1080;
  const user = useAuthStore((s) => s.user);

  const [traders, setTraders] = useState<FollowedTrader[]>([]);
  const [strategyMap, setStrategyMap] = useState<Record<string, TraderStrategy | null>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadLatestStrategies = useCallback(async (items: FollowedTrader[]) => {
    if (items.length === 0) {
      setStrategyMap({});
      return;
    }

    const results = await Promise.allSettled(
      items.map(async (trader) => {
        const res = await getTraderStrategies(trader.uid, 1, 0);
        return [trader.uid, res.strategies?.[0] ?? null] as const;
      }),
    );

    const next: Record<string, TraderStrategy | null> = {};
    results.forEach((result) => {
      if (result.status === 'fulfilled') {
        const [uid, strategy] = result.value;
        next[uid] = strategy;
      }
    });
    setStrategyMap(next);
  }, []);

  const loadData = useCallback(async () => {
    if (!user) {
      setLoading(false);
      return;
    }

    try {
      const data = await getMyWatchedTraders();
      const list = data || [];
      setTraders(list);
      setStrategyMap({});
      void loadLatestStrategies(list);
    } catch {
      setTraders([]);
      setStrategyMap({});
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [loadLatestStrategies, user]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void loadData();
    }, [loadData]),
  );

  const handleRefresh = () => {
    setRefreshing(true);
    void loadData();
  };

  const handleUnwatch = async (traderUid: string, name: string) => {
    const confirmed = await showConfirm(
      t('following.unwatchBody', { name }),
      t('following.unwatchTitle'),
    );
    if (!confirmed) return;

    try {
      await unwatchTrader(traderUid);
      setTraders((prev) => prev.filter((trader) => trader.uid !== traderUid));
      setStrategyMap((prev) => {
        const next = { ...prev };
        delete next[traderUid];
        return next;
      });
    } catch (e: any) {
      showAlert(
        e?.response?.data?.error || e?.message || t('following.unwatchFailed'),
        t('following.unwatchTitle'),
      );
    }
  };

  const summary = useMemo(() => {
    const copyingCount = traders.filter((item) => item.is_copying && item.copy_status === 'active').length;
    const withStrategyCount = traders.filter((item) => !!strategyMap[item.uid]).length;
    const positiveCount = traders.filter((item) => (item.stats?.total_pnl || 0) > 0).length;
    return { copyingCount, withStrategyCount, positiveCount };
  }, [strategyMap, traders]);

  if (!user) {
    return (
      <View style={styles.centered}>
        <AppIcon name="lock" size={28} color={Colors.textMuted} />
        <Text style={styles.emptyTitle}>{t('following.loginTitle')}</Text>
        <Text style={styles.emptySubtitle}>{t('following.loginSubtitle')}</Text>
        <TouchableOpacity
          style={styles.primaryBtn}
          onPress={() => router.push('/(auth)/login' as any)}
        >
          <Text style={styles.primaryBtnText}>{t('following.goLogin')}</Text>
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

  if (traders.length === 0) {
    return (
      <View style={styles.centered}>
        <AppIcon name="eye" size={28} color={Colors.textMuted} />
        <Text style={styles.emptyTitle}>{t('following.emptyTitle')}</Text>
        <Text style={styles.emptySubtitle}>{t('following.emptySubtitle')}</Text>
        <TouchableOpacity
          style={styles.primaryBtn}
          onPress={() => router.push('/(tabs)/rankings' as any)}
        >
          <Text style={styles.primaryBtnText}>{t('following.goRankings')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const renderTraderCard = (item: FollowedTrader) => {
    const stats = item.stats;
    const pnl = stats?.total_pnl || 0;
    const winRate = stats?.win_rate || 0;
    const followers = stats?.followers_count || 0;
    const latestStrategy = strategyMap[item.uid];
    const traderRoute = embedded
      ? `/(tabs)/rankings?tab=following&trader=${item.uid}`
      : `/(tabs)/rankings?trader=${item.uid}`;

    let statusLabel = t('following.statusWatchOnly');
    let statusColor: string = Colors.textMuted;
    let statusBg: string = Colors.surfaceAlt;
    if (item.is_copying && item.copy_status === 'active') {
      statusLabel = t('following.statusCopying');
      statusColor = Colors.up;
      statusBg = Colors.upDim;
    } else if (item.is_copying && item.copy_status === 'paused') {
      statusLabel = t('following.statusPaused');
      statusColor = Colors.primary;
      statusBg = 'rgba(242, 202, 80, 0.12)';
    }

    const strategyDate = latestStrategy
      ? new Date(latestStrategy.created_at).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' })
      : null;

    return (
      <View key={item.uid} style={styles.cardShell}>
        <View style={styles.traderCard}>
          <View style={[styles.cardTopRow, isDesktop && styles.cardTopRowDesktop]}>
            <TouchableOpacity
              style={styles.identityRow}
              activeOpacity={0.85}
              onPress={() => router.push(traderRoute as any)}
            >
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>
                  {(item.display_name || '?').charAt(0).toUpperCase()}
                </Text>
              </View>
              <View style={styles.identityText}>
                <View style={styles.nameRow}>
                  <Text style={styles.traderName} numberOfLines={1}>
                    {item.display_name}
                  </Text>
                  <View style={[styles.statusTag, { backgroundColor: statusBg }]}>
                    <Text style={[styles.statusTagText, { color: statusColor }]}>{statusLabel}</Text>
                  </View>
                </View>
                <Text style={styles.followDate}>
                  {t('following.followedOn', {
                    date: new Date(item.followed_at).toLocaleDateString('zh-CN', {
                      month: '2-digit',
                      day: '2-digit',
                    }),
                  })}
                </Text>
              </View>
            </TouchableOpacity>

            <View style={styles.headerActions}>
              <View style={[styles.statusTag, { backgroundColor: statusBg }]}>
                <Text style={[styles.statusTagText, { color: statusColor }]}>{statusLabel}</Text>
              </View>
              <TouchableOpacity
                style={[styles.primaryBtnInline, isDesktop && styles.primaryBtnInlineDesktop]}
                onPress={() => router.push(traderRoute as any)}
              >
                <Text style={styles.primaryBtnInlineText}>
                  {item.is_copying ? t('following.manageCopy') : t('following.copyNow')}
                </Text>
              </TouchableOpacity>
            </View>
          </View>

          <View style={[styles.metricStrip, isDesktop && styles.metricStripDesktop]}>
            <View style={styles.metricItem}>
              <Text style={styles.metricLabel}>{t('following.totalPnl')}</Text>
              <Text style={[styles.metricValue, { color: pnl >= 0 ? Colors.up : Colors.down }]}>
                {pnl >= 0 ? '+' : '-'}${formatMoney(pnl)}
              </Text>
            </View>
            <View style={styles.metricDivider} />
            <View style={styles.metricItem}>
              <Text style={styles.metricLabel}>{t('following.winRate')}</Text>
              <Text style={styles.metricValuePlain}>{winRate.toFixed(1)}%</Text>
            </View>
            <View style={styles.metricDivider} />
            <View style={styles.metricItem}>
              <Text style={styles.metricLabel}>{t('following.followers')}</Text>
              <Text style={styles.metricValuePlain}>{followers}</Text>
            </View>
          </View>

          <TouchableOpacity
            style={styles.strategyPanel}
            activeOpacity={latestStrategy ? 0.86 : 1}
            onPress={() => {
              if (latestStrategy) {
                router.push(`/strategy/${latestStrategy.id}` as any);
              }
            }}
          >
            <View style={styles.strategyHead}>
              <Text style={styles.strategyEyebrow}>{t('following.latestStrategy')}</Text>
              {latestStrategy && strategyDate ? (
                <Text style={styles.strategyDate}>{strategyDate}</Text>
              ) : null}
            </View>

            {latestStrategy ? (
              <View style={[styles.strategyBody, isDesktop && styles.strategyBodyDesktop]}>
                <View style={styles.strategyMain}>
                  <Text style={styles.strategyTitle} numberOfLines={1}>
                    {latestStrategy.title}
                  </Text>
                  <Text style={styles.strategySummary} numberOfLines={1}>
                    {latestStrategy.summary || t('following.strategyPlaceholder')}
                  </Text>
                </View>
                <View style={styles.strategyFoot}>
                  <View style={styles.strategyMetaTag}>
                    <Text style={styles.strategyMetaTagText}>
                      {t(STRATEGY_CATEGORY_LABELS[latestStrategy.category] || 'strategy.categoryOther')}
                    </Text>
                  </View>
                  <Text style={styles.strategyLink}>{t('strategy.viewStrategy')}</Text>
                </View>
              </View>
            ) : (
              <View style={styles.strategyEmpty}>
                <Text style={styles.strategyEmptyTitle}>{t('following.noStrategy')}</Text>
                <Text style={styles.strategyEmptySub} numberOfLines={1}>
                  {t('following.strategyPlaceholder')}
                </Text>
              </View>
            )}
          </TouchableOpacity>

          <View style={[styles.actionRow, isDesktop && styles.actionRowDesktop]}>
            <TouchableOpacity
              style={styles.ghostBtn}
              onPress={() => router.push(traderRoute as any)}
            >
              <Text style={styles.ghostBtnText}>{t('following.viewDetails')}</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.ghostBtn}
              onPress={() => {
                if (latestStrategy) {
                  router.push(`/strategy/${latestStrategy.id}` as any);
                } else {
                  router.push(traderRoute as any);
                }
              }}
            >
              <Text style={styles.ghostBtnText}>{t('strategy.viewStrategy')}</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.textBtn}
              onPress={() => void handleUnwatch(item.uid, item.display_name)}
            >
              <Text style={styles.textBtnText}>{t('following.unwatch')}</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    );
  };

  return (
    <ScrollView
      style={[styles.container, embedded && styles.containerEmbedded]}
      contentContainerStyle={styles.scrollContent}
      showsVerticalScrollIndicator={false}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={handleRefresh}
          tintColor={Colors.primary}
        />
      }
    >
      <View style={[styles.summaryRail, embedded && styles.summaryRailEmbedded]}>
        <View style={styles.summaryBar}>
          <View style={styles.summaryItem}>
            <Text style={styles.summaryValue}>{traders.length}</Text>
            <Text style={styles.summaryLabel}>{t('following.summaryFollowed')}</Text>
          </View>
          <View style={styles.summaryDivider} />
          <View style={styles.summaryItem}>
            <Text style={styles.summaryValue}>{summary.copyingCount}</Text>
            <Text style={styles.summaryLabel}>{t('following.summaryCopying')}</Text>
          </View>
          <View style={styles.summaryDivider} />
          <View style={styles.summaryItem}>
            <Text style={styles.summaryValue}>{summary.withStrategyCount}</Text>
            <Text style={styles.summaryLabel}>{t('following.summaryWithStrategy')}</Text>
          </View>
          <View style={styles.summaryDivider} />
          <View style={styles.summaryItem}>
            <Text style={styles.summaryValue}>{summary.positiveCount}</Text>
            <Text style={styles.summaryLabel}>{t('following.summaryPositive')}</Text>
          </View>
        </View>
      </View>

      <View style={styles.grid}>
        {traders.map(renderTraderCard)}
      </View>
    </ScrollView>
  );
}

export default function FollowingRoute() {
  return <Redirect href="/(tabs)/rankings?tab=following" />;
}

function formatMoney(n: number): string {
  return Math.abs(n).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  containerEmbedded: {
    marginTop: 8,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 40,
  },
  scrollContent: {
    paddingBottom: 40,
  },
  summaryRail: {
    marginBottom: 18,
  },
  summaryRailEmbedded: {
    marginBottom: 16,
  },
  summaryBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 18,
    paddingVertical: 14,
    borderRadius: 16,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
  },
  summaryItem: {
    flex: 1,
  },
  summaryDivider: {
    width: 1,
    height: 26,
    backgroundColor: Colors.glassBorder,
    marginHorizontal: 8,
  },
  summaryValue: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
    marginBottom: 2,
  },
  summaryLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
  },
  grid: {
    gap: 16,
  },
  cardShell: {
    width: '100%',
  },
  traderCard: {
    backgroundColor: Colors.surface,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: 18,
  },
  cardTopRow: {
    gap: 14,
    marginBottom: 14,
  },
  cardTopRowDesktop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  identityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    flex: 1,
  },
  avatar: {
    width: 50,
    height: 50,
    borderRadius: 16,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: Colors.primaryLight,
    fontSize: 20,
    fontWeight: '800',
  },
  identityText: {
    flex: 1,
    gap: 4,
  },
  nameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexWrap: 'wrap',
  },
  traderName: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
  },
  followDate: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  statusTag: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
  },
  statusTagText: {
    fontSize: 11,
    fontWeight: '700',
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  metricStrip: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 14,
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderRadius: 14,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
  },
  metricStripDesktop: {
    paddingHorizontal: 16,
  },
  metricItem: {
    flex: 1,
  },
  metricDivider: {
    width: 1,
    height: 30,
    backgroundColor: Colors.glassBorder,
    marginHorizontal: 10,
  },
  metricLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    marginBottom: 6,
  },
  metricValue: {
    fontSize: 18,
    fontWeight: '800',
  },
  metricValuePlain: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
  },
  strategyPanel: {
    borderRadius: 14,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    paddingHorizontal: 16,
    paddingVertical: 14,
    marginBottom: 14,
  },
  strategyHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 10,
  },
  strategyEyebrow: {
    color: Colors.primaryLight,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  strategyDate: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  strategyTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
    marginBottom: 6,
  },
  strategyBody: {
    gap: 10,
  },
  strategyBodyDesktop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 16,
  },
  strategyMain: {
    flex: 1,
  },
  strategySummary: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 18,
  },
  strategyFoot: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  strategyMetaTag: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: Colors.primaryDim,
  },
  strategyMetaTagText: {
    color: Colors.primaryLight,
    fontSize: 11,
    fontWeight: '700',
  },
  strategyLink: {
    color: Colors.primaryLight,
    fontSize: 12,
    fontWeight: '700',
  },
  strategyEmpty: {
    minHeight: 44,
    justifyContent: 'center',
  },
  strategyEmptyTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    marginBottom: 4,
  },
  strategyEmptySub: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  actionRow: {
    flexDirection: 'row',
    gap: 10,
  },
  actionRowDesktop: {
    justifyContent: 'flex-end',
  },
  ghostBtn: {
    flex: 1,
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: Colors.glassBorder,
  },
  ghostBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '700',
  },
  primaryBtnInline: {
    minWidth: 160,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 20,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryLight,
  },
  primaryBtnInlineDesktop: {
    alignSelf: 'flex-start',
  },
  primaryBtnInlineText: {
    color: Colors.background,
    fontSize: 13,
    fontWeight: '800',
  },
  textBtn: {
    flex: 1,
    paddingVertical: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  textBtnText: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  emptyTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
    marginTop: 16,
  },
  emptySubtitle: {
    color: Colors.textMuted,
    fontSize: 14,
    lineHeight: 22,
    textAlign: 'center',
    marginTop: 8,
    marginBottom: 16,
    maxWidth: 360,
  },
  primaryBtn: {
    backgroundColor: Colors.primaryLight,
    borderRadius: 12,
    paddingHorizontal: 20,
    paddingVertical: 12,
    ...Shadows.glow,
  },
  primaryBtnText: {
    color: Colors.background,
    fontSize: 14,
    fontWeight: '800',
  },
});
