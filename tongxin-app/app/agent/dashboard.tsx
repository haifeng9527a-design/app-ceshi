import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Platform,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  useWindowDimensions,
} from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { Colors, Shadows } from '../../theme/colors';
import AppIcon from '../../components/ui/AppIcon';
import { useAuthStore } from '../../services/store/authStore';
import { AgentDashboard, agentApi } from '../../services/api/referralApi';

function fmtUsdt(n: number, digits = 2): string {
  if (!Number.isFinite(n)) return '0.00';
  return n.toLocaleString('en-US', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

export default function AgentDashboardScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width > 900;

  const isAgent = !!user?.isAgent;

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [dashboard, setDashboard] = useState<AgentDashboard | null>(null);

  const loadData = useCallback(async () => {
    if (!user || !isAgent) return;
    setLoading(true);
    try {
      const data = await agentApi.getDashboard();
      setDashboard(data);
    } catch {
      // silently fail, user can pull-to-refresh
    } finally {
      setLoading(false);
    }
  }, [user, isAgent]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  useFocusEffect(
    useCallback(() => {
      loadData();
    }, [loadData]),
  );

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadData();
    setRefreshing(false);
  }, [loadData]);

  // ── Not logged in ──
  if (!user) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyTitle}>{t('common.loginRequired') || 'Login required'}</Text>
        <TouchableOpacity style={styles.primaryBtn} onPress={() => router.push('/(auth)/login' as any)}>
          <Text style={styles.primaryBtnText}>{t('auth.loginOrRegister')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // ── Not an agent ──
  if (!isAgent) {
    return (
      <View style={styles.center}>
        <AppIcon name="lock" size={36} color={Colors.textMuted} />
        <Text style={styles.emptyTitle}>{t('agent.notAgentTitle')}</Text>
        <Text style={styles.emptyDesc}>{t('agent.notAgentDesc')}</Text>
        <TouchableOpacity
          style={styles.primaryBtn}
          onPress={() => router.push('/agent/apply' as any)}
        >
          <Text style={styles.primaryBtnText}>{t('agent.goApply')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // ── Loading ──
  if (loading && !dashboard) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  const rate = dashboard?.my_rebate_rate ?? 0;

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={[
        styles.scrollContent,
        isDesktop && { maxWidth: 900, alignSelf: 'center' as const, width: '100%' },
      ]}
      refreshControl={
        <RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor={Colors.primary} />
      }
    >
      {/* Header */}
      <View style={styles.headerRow}>
        <TouchableOpacity style={styles.backBtn} onPress={() => router.back()} activeOpacity={0.7}>
          <AppIcon name="back" size={20} color={Colors.textActive} />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={styles.pageTitle}>{t('agent.pageTitle')}</Text>
          <Text style={styles.pageSub}>{t('agent.pageSubtitle')}</Text>
        </View>
      </View>

      {/* My Rate */}
      <View style={styles.rateSection}>
        <Text style={styles.rateLabelText}>{t('agent.myRateLabel')}</Text>
        <Text style={styles.rateValue}>{(rate * 100).toFixed(1)}%</Text>
      </View>

      {/* KPI cards — 2x3 grid (本月自返 = migration 034) */}
      <View style={[styles.kpiGrid, isDesktop && styles.kpiGridDesktop]}>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('agent.kpiLifetime')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(dashboard?.lifetime_commission_earned ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('agent.kpiDirectThisMonth')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(dashboard?.this_month_direct ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('agent.kpiOverrideThisMonth')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(dashboard?.this_month_override ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('agent.kpiSelfThisMonth')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(dashboard?.this_month_self ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('agent.kpiSubAgents')}</Text>
          <Text style={[styles.kpiValue, { color: Colors.textActive }]}>
            {dashboard?.sub_agents_count ?? 0}
          </Text>
          <Text style={styles.kpiUnit}>{t('agent.kpiSubAgentsUnit')}</Text>
        </View>
      </View>

      {/* Navigation cards */}
      <View style={styles.navSection}>
        <TouchableOpacity
          style={styles.navCard}
          activeOpacity={0.7}
          onPress={() => router.push('/agent/invite-links' as any)}
        >
          <View style={styles.navIconWrap}>
            <AppIcon name="send" size={18} color={Colors.primary} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.navCardTitle}>{t('agent.navInviteLinks')}</Text>
            <Text style={styles.navCardDesc}>{t('agent.navInviteLinksDesc')}</Text>
          </View>
          <AppIcon name="back" size={16} color={Colors.textMuted} style={{ transform: [{ rotate: '180deg' }] }} />
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.navCard}
          activeOpacity={0.7}
          onPress={() => router.push('/agent/sub-agents' as any)}
        >
          <View style={styles.navIconWrap}>
            <AppIcon name="users" size={18} color={Colors.primary} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.navCardTitle}>{t('agent.navSubAgents')}</Text>
            <Text style={styles.navCardDesc}>{t('agent.navSubAgentsDesc')}</Text>
          </View>
          <AppIcon name="back" size={16} color={Colors.textMuted} style={{ transform: [{ rotate: '180deg' }] }} />
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.navCard}
          activeOpacity={0.7}
          onPress={() => router.push('/referral/my-invites' as any)}
        >
          <View style={styles.navIconWrap}>
            <AppIcon name="paper" size={18} color={Colors.primary} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={styles.navCardTitle}>{t('agent.navCommissionDetail')}</Text>
            <Text style={styles.navCardDesc}>{t('agent.navCommissionDetailDesc')}</Text>
          </View>
          <AppIcon name="back" size={16} color={Colors.textMuted} style={{ transform: [{ rotate: '180deg' }] }} />
        </TouchableOpacity>
      </View>

      <View style={{ height: 32 }} />
    </ScrollView>
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
  center: {
    flex: 1,
    backgroundColor: Colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    gap: 12,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 4,
  },
  backBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pageTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
  },
  pageSub: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
    lineHeight: 18,
  },

  // Rate
  rateSection: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    alignItems: 'center',
    gap: 8,
    ...Shadows.card,
  },
  rateLabelText: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  rateValue: {
    color: Colors.primary,
    fontSize: 36,
    fontWeight: '800',
  },

  // KPI grid（mobile 2 列；desktop 5 列单行）
  kpiGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  kpiGridDesktop: {
    flexWrap: 'nowrap',
  },
  kpiCard: {
    flexBasis: '30%',
    flexGrow: 1,
    minWidth: 140,
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 6,
    ...Shadows.card,
  },
  kpiLabel: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  kpiValue: {
    color: Colors.primary,
    fontSize: 22,
    fontWeight: '800',
  },
  kpiUnit: {
    color: Colors.textMuted,
    fontSize: 11,
  },

  // Nav section
  navSection: {
    gap: 12,
  },
  navCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    ...Shadows.card,
  },
  navIconWrap: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: Colors.primaryDim,
    alignItems: 'center',
    justifyContent: 'center',
  },
  navCardTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  navCardDesc: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 2,
  },

  // Shared
  emptyTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    marginTop: 4,
  },
  emptyDesc: {
    color: Colors.textMuted,
    fontSize: 12,
    textAlign: 'center',
    lineHeight: 18,
  },
  primaryBtn: {
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: Colors.primary,
    marginTop: 6,
  },
  primaryBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '800',
  },
});
