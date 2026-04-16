import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Platform,
  RefreshControl,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  useWindowDimensions,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import * as Clipboard from 'expo-clipboard';

import { Colors, Shadows } from '../../theme/colors';
import AppIcon from '../../components/ui/AppIcon';
import { useAuthStore } from '../../services/store/authStore';
import {
  referralApi,
  type ReferralOverview,
  type CommissionRecord,
} from '../../services/api/referralApi';

const PAGE_SIZE = 20;

function fmtUsdt(n: number, digits = 2): string {
  if (!Number.isFinite(n)) return '0.00';
  return n.toLocaleString('en-US', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

function fmtRatePct(rate: number): string {
  return `${(rate * 100).toFixed(rate * 100 < 10 ? 1 : 0)}%`;
}

function fmtDate(iso: string): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(
    d.getMinutes(),
  )}`;
}

export default function MyInvitesScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [overview, setOverview] = useState<ReferralOverview | null>(null);
  const [records, setRecords] = useState<CommissionRecord[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    setError(null);
    try {
      const [ov, page] = await Promise.all([
        referralApi.getOverview(),
        referralApi.listCommissionRecords(undefined, PAGE_SIZE, 0),
      ]);
      setOverview(ov);
      setRecords(page.records);
      setTotal(page.total);
      setOffset(page.records.length);
    } catch (e: any) {
      setError(e?.response?.data?.error || e?.message || 'Failed to load');
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadData();
    setRefreshing(false);
  }, [loadData]);

  const handleLoadMore = useCallback(async () => {
    if (loadingMore || records.length >= total) return;
    setLoadingMore(true);
    try {
      const page = await referralApi.listCommissionRecords(undefined, PAGE_SIZE, offset);
      setRecords((prev) => [...prev, ...page.records]);
      setOffset((prev) => prev + page.records.length);
      setTotal(page.total);
    } catch (e: any) {
      Alert.alert('Error', e?.message || 'Failed to load more');
    } finally {
      setLoadingMore(false);
    }
  }, [loadingMore, records.length, total, offset]);

  const handleCopyCode = useCallback(async () => {
    if (!overview?.invite_code) return;
    await Clipboard.setStringAsync(overview.invite_code);
    Alert.alert(t('referral.copied'), overview.invite_code);
  }, [overview?.invite_code, t]);

  const handleShare = useCallback(async () => {
    if (!overview?.invite_code) return;
    try {
      await Share.share({
        message: `Join via my invite link: https://app.example.com/register?ref=${overview.invite_code}`,
      });
    } catch (_) {
      // user cancelled
    }
  }, [overview?.invite_code]);

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

  if (loading && !overview) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  if (error && !overview) {
    return (
      <View style={styles.center}>
        <AppIcon name="help" size={36} color={Colors.textMuted} />
        <Text style={styles.emptyTitle}>{error}</Text>
        <TouchableOpacity style={styles.primaryBtn} onPress={() => void loadData()}>
          <Text style={styles.primaryBtnText}>{t('common.retry')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const isAgent = overview?.is_agent ?? false;

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={[
        styles.scrollContent,
        isDesktop && { maxWidth: 900, alignSelf: 'center' as const, width: '100%' },
      ]}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor={Colors.primary} />}
    >
      {/* Header */}
      <View style={styles.headerRow}>
        <TouchableOpacity style={styles.backBtn} onPress={() => router.back()} activeOpacity={0.7}>
          <AppIcon name="back" size={20} color={Colors.textActive} />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={styles.pageTitle}>{t('referral.title')}</Text>
        </View>
      </View>

      {/* KPI cards */}
      <View style={[styles.kpiRow, isDesktop && styles.kpiRowDesktop]}>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('referral.lifetimeEarnings')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(overview?.lifetime_commission_earned ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('referral.thisMonth')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(overview?.this_month_commission ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('referral.inviteCount')}</Text>
          <Text style={[styles.kpiValue, { color: Colors.textActive }]}>{overview?.invite_count ?? 0}</Text>
          <Text style={styles.kpiUnit}>{t('profitShare.kpiFollowersUnit')}</Text>
        </View>
      </View>

      {/* My invite code */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('referral.myInviteCode')}</Text>
        <View style={styles.codeRow}>
          <View style={styles.codeBox}>
            <Text style={styles.codeText}>{overview?.invite_code || '--'}</Text>
          </View>
          <TouchableOpacity style={styles.actionBtn} activeOpacity={0.7} onPress={() => void handleCopyCode()}>
            <AppIcon name="badge" size={14} color={Colors.primary} />
            <Text style={styles.actionBtnText}>{t('referral.copyCode')}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionBtn} activeOpacity={0.7} onPress={() => void handleShare()}>
            <AppIcon name="chart" size={14} color={Colors.primary} />
            <Text style={styles.actionBtnText}>{t('referral.shareLink')}</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* My rebate rate */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('referral.myRate')}</Text>
        <Text style={styles.rateDisplay}>{fmtRatePct(overview?.my_rebate_rate ?? 0)}</Text>
      </View>

      {/* Apply agent CTA */}
      {!isAgent && (
        <TouchableOpacity
          style={styles.ctaBtn}
          activeOpacity={0.85}
          onPress={() => router.push('/agent/apply' as any)}
        >
          <AppIcon name="building" size={18} color={Colors.textOnPrimary} />
          <View style={{ flex: 1 }}>
            <Text style={styles.ctaBtnTitle}>{t('referral.applyAgent')}</Text>
            <Text style={styles.ctaBtnDesc}>{t('referral.applyAgentDesc')}</Text>
          </View>
          <Text style={styles.ctaArrow}>{'>'}</Text>
        </TouchableOpacity>
      )}

      {/* Commission records */}
      <View style={styles.section}>
        <View style={styles.recordsHead}>
          <Text style={styles.sectionTitle}>{t('referral.commissionRecords')}</Text>
          <Text style={styles.recordsCount}>{total}</Text>
        </View>

        {records.length === 0 ? (
          <View style={styles.emptyBlock}>
            <AppIcon name="wallet" size={28} color={Colors.textMuted} />
            <Text style={styles.emptyTitle}>{t('referral.noRecords')}</Text>
          </View>
        ) : (
          <>
            {records.map((r) => (
              <View key={r.id} style={styles.recordRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.recordTime}>{fmtDate(r.created_at)}</Text>
                  <Text style={styles.recordSub}>
                    {r.kind === 'direct'
                      ? t('referral.direct')
                      : r.kind === 'self'
                        ? t('referral.self')
                        : t('referral.override')}
                    {'  '}
                    {r.status === 'settled'
                      ? t('referral.settled')
                      : r.status === 'capped'
                        ? t('referral.capped')
                        : t('referral.pending')}
                  </Text>
                </View>
                <Text style={styles.recordAmount}>+{fmtUsdt(r.settled_amount)} USDT</Text>
              </View>
            ))}

            {records.length < total ? (
              <TouchableOpacity
                style={[styles.loadMoreBtn, loadingMore && styles.loadMoreBtnDisabled]}
                activeOpacity={0.85}
                disabled={loadingMore}
                onPress={() => void handleLoadMore()}
              >
                {loadingMore ? (
                  <ActivityIndicator size="small" color={Colors.primary} />
                ) : (
                  <Text style={styles.loadMoreText}>{t('referral.loadMore')}</Text>
                )}
              </TouchableOpacity>
            ) : (
              <Text style={styles.endHint}>{t('referral.endOfList')}</Text>
            )}
          </>
        )}
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

  // KPI
  kpiRow: {
    flexDirection: 'row',
    gap: 12,
    flexWrap: 'wrap',
  },
  kpiRowDesktop: {
    flexWrap: 'nowrap',
  },
  kpiCard: {
    flex: 1,
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

  // Section
  section: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 10,
    ...Shadows.card,
  },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },

  // Invite code
  codeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    flexWrap: 'wrap',
  },
  codeBox: {
    flex: 1,
    minWidth: 120,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  codeText: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
    letterSpacing: 2,
  },
  actionBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  actionBtnText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
  },

  // Rate display
  rateDisplay: {
    color: Colors.primary,
    fontSize: 28,
    fontWeight: '800',
  },

  // CTA
  ctaBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: Colors.primary,
    borderRadius: 14,
    padding: 16,
    ...Shadows.card,
  },
  ctaBtnTitle: {
    color: Colors.textOnPrimary,
    fontSize: 15,
    fontWeight: '800',
  },
  ctaBtnDesc: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 12,
    marginTop: 2,
  },
  ctaArrow: {
    color: Colors.textOnPrimary,
    fontSize: 18,
    fontWeight: '800',
  },

  // Records
  recordsHead: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
  },
  recordsCount: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  recordRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
    paddingVertical: 12,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
  },
  recordTime: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '600',
  },
  recordSub: {
    color: Colors.textSecondary,
    fontSize: 12,
    marginTop: 2,
  },
  recordAmount: {
    color: Colors.up,
    fontSize: 14,
    fontWeight: '800',
  },

  loadMoreBtn: {
    marginTop: 12,
    paddingVertical: 10,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    alignItems: 'center',
  },
  loadMoreBtnDisabled: {
    opacity: 0.5,
  },
  loadMoreText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
  },
  endHint: {
    marginTop: 12,
    color: Colors.textMuted,
    fontSize: 12,
    textAlign: 'center',
  },

  emptyBlock: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    gap: 6,
  },
  emptyTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    marginTop: 4,
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
