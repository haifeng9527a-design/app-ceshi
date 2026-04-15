import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Platform,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
  useWindowDimensions,
} from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { Colors, Shadows } from '../../theme/colors';
import AppIcon from '../../components/ui/AppIcon';
import { useAuthStore } from '../../services/store/authStore';
import {
  ProfitShareRecord,
  ProfitShareSummary,
  getProfitShareRecords,
  getProfitShareSummary,
  updateDefaultShareRate,
} from '../../services/api/traderApi';

const PAGE_SIZE = 20;
const MAX_RATE_PCT = 20; // 0–20%
const STEP_PCT = 1;

function fmtUsdt(n: number, digits = 2): string {
  if (!Number.isFinite(n)) return '0.00';
  return n.toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

function fmtRatePct(rate: number): string {
  // rate is 0~0.2 (decimal)
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

function maskShortId(uid: string | undefined, name: string | undefined): string {
  if (name && name.trim()) {
    return name.length > 16 ? `${name.slice(0, 14)}…` : name;
  }
  if (!uid) return '••••';
  if (uid.length <= 6) return uid;
  return `${uid.slice(0, 4)}…${uid.slice(-2)}`;
}

export default function TraderDashboardScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [summary, setSummary] = useState<ProfitShareSummary | null>(null);
  const [records, setRecords] = useState<ProfitShareRecord[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loadingMore, setLoadingMore] = useState(false);

  // Default rate editor (held as percent, 0–20)
  const [draftPct, setDraftPct] = useState('0');
  const [draftDirty, setDraftDirty] = useState(false);
  const [savingRate, setSavingRate] = useState(false);

  const isTrader = !!user?.isTrader;

  const loadInitial = useCallback(async () => {
    if (!user || !isTrader) return;
    setLoading(true);
    try {
      const [sum, page] = await Promise.all([
        getProfitShareSummary(),
        getProfitShareRecords(PAGE_SIZE, 0),
      ]);
      setSummary(sum);
      setRecords(page.records);
      setTotal(page.total);
      setOffset(page.records.length);
      // Initialize rate editor from server (only if user hasn't started editing)
      if (!draftDirty) {
        const pct = (sum.default_share_rate ?? 0) * 100;
        setDraftPct(pct.toFixed(pct < 10 ? 1 : 0));
      }
    } catch (e: any) {
      Alert.alert(t('profitShare.loadFailedTitle'), e?.message || t('profitShare.loadFailedBody'));
    } finally {
      setLoading(false);
    }
  }, [user, isTrader, draftDirty, t]);

  useEffect(() => {
    loadInitial();
  }, [loadInitial]);

  useFocusEffect(
    useCallback(() => {
      // Refresh whenever the page regains focus; cheap on summary endpoint
      loadInitial();
    }, [loadInitial]),
  );

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    setOffset(0);
    setDraftDirty(false);
    await loadInitial();
    setRefreshing(false);
  }, [loadInitial]);

  const handleLoadMore = useCallback(async () => {
    if (loadingMore || records.length >= total) return;
    setLoadingMore(true);
    try {
      const page = await getProfitShareRecords(PAGE_SIZE, offset);
      setRecords((prev) => [...prev, ...page.records]);
      setOffset((prev) => prev + page.records.length);
      setTotal(page.total);
    } catch (e: any) {
      Alert.alert(t('profitShare.loadFailedTitle'), e?.message || t('profitShare.loadFailedBody'));
    } finally {
      setLoadingMore(false);
    }
  }, [loadingMore, records.length, total, offset, t]);

  const adjustDraft = useCallback((deltaPct: number) => {
    setDraftPct((prev) => {
      const cur = Math.max(0, Math.min(MAX_RATE_PCT, parseFloat(prev) || 0));
      const next = Math.max(0, Math.min(MAX_RATE_PCT, cur + deltaPct));
      return next.toFixed(next < 10 ? 1 : 0);
    });
    setDraftDirty(true);
  }, []);

  const handleDraftChange = useCallback((text: string) => {
    // Allow empty / partial input; clamp on save
    setDraftPct(text);
    setDraftDirty(true);
  }, []);

  const handleSaveRate = useCallback(async () => {
    const pct = parseFloat(draftPct);
    if (!Number.isFinite(pct) || pct < 0 || pct > MAX_RATE_PCT) {
      Alert.alert(t('profitShare.invalidRateTitle'), t('profitShare.invalidRateBody', { max: MAX_RATE_PCT }));
      return;
    }
    setSavingRate(true);
    try {
      const rate = pct / 100;
      const res = await updateDefaultShareRate(rate);
      setSummary((prev) => (prev ? { ...prev, default_share_rate: res.default_profit_share_rate } : prev));
      setDraftDirty(false);
      Alert.alert(t('profitShare.saveOkTitle'), t('profitShare.saveOkBody'));
    } catch (e: any) {
      Alert.alert(t('profitShare.saveFailTitle'), e?.message || t('profitShare.saveFailBody'));
    } finally {
      setSavingRate(false);
    }
  }, [draftPct, t]);

  const settledRecords = useMemo(() => records.filter((r) => r.status === 'settled' && r.share_amount > 0), [records]);

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

  if (!isTrader) {
    return (
      <View style={styles.center}>
        <AppIcon name="lock" size={36} color={Colors.textMuted} />
        <Text style={styles.emptyTitle}>{t('profitShare.notTraderTitle')}</Text>
        <Text style={styles.emptyDesc}>{t('profitShare.notTraderDesc')}</Text>
        <TouchableOpacity
          style={styles.primaryBtn}
          onPress={() => router.push('/(tabs)/trader-center' as any)}
        >
          <Text style={styles.primaryBtnText}>{t('profitShare.goApply')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (loading && !summary) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

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
          <Text style={styles.pageTitle}>{t('profitShare.pageTitle')}</Text>
          <Text style={styles.pageSub}>{t('profitShare.pageSubtitle')}</Text>
        </View>
      </View>

      {/* KPI cards */}
      <View style={[styles.kpiRow, isDesktop && styles.kpiRowDesktop]}>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('profitShare.kpiLifetime')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(summary?.lifetime ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('profitShare.kpiThisMonth')}</Text>
          <Text style={styles.kpiValue}>{fmtUsdt(summary?.this_month ?? 0)}</Text>
          <Text style={styles.kpiUnit}>USDT</Text>
        </View>
        <View style={styles.kpiCard}>
          <Text style={styles.kpiLabel}>{t('profitShare.kpiActiveFollowers')}</Text>
          <Text style={[styles.kpiValue, { color: Colors.textActive }]}>{summary?.active_followers ?? 0}</Text>
          <Text style={styles.kpiUnit}>{t('profitShare.kpiFollowersUnit')}</Text>
        </View>
      </View>

      {/* Default rate editor */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('profitShare.defaultRateTitle')}</Text>
        <Text style={styles.sectionDesc}>{t('profitShare.defaultRateDesc', { max: MAX_RATE_PCT })}</Text>

        <View style={styles.rateRow}>
          <TouchableOpacity
            style={styles.stepperBtn}
            activeOpacity={0.7}
            onPress={() => adjustDraft(-STEP_PCT)}
          >
            <Text style={styles.stepperText}>−</Text>
          </TouchableOpacity>
          <View style={styles.rateInputWrap}>
            <TextInput
              style={styles.rateInput}
              value={draftPct}
              onChangeText={handleDraftChange}
              keyboardType={Platform.OS === 'web' ? 'default' : 'decimal-pad'}
              placeholder="0"
              placeholderTextColor={Colors.textMuted}
            />
            <Text style={styles.ratePct}>%</Text>
          </View>
          <TouchableOpacity
            style={styles.stepperBtn}
            activeOpacity={0.7}
            onPress={() => adjustDraft(STEP_PCT)}
          >
            <Text style={styles.stepperText}>+</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.saveRateBtn, (!draftDirty || savingRate) && styles.saveRateBtnDisabled]}
            activeOpacity={0.85}
            onPress={() => void handleSaveRate()}
            disabled={!draftDirty || savingRate}
          >
            {savingRate ? (
              <ActivityIndicator size="small" color={Colors.textOnPrimary} />
            ) : (
              <Text style={styles.saveRateText}>{t('profitShare.saveRate')}</Text>
            )}
          </TouchableOpacity>
        </View>

        <View style={styles.noticeCard}>
          <AppIcon name="bulb" size={14} color={Colors.warning} />
          <Text style={styles.noticeText}>{t('profitShare.snapshotNotice')}</Text>
        </View>
      </View>

      {/* Records */}
      <View style={styles.section}>
        <View style={styles.recordsHead}>
          <Text style={styles.sectionTitle}>{t('profitShare.recordsTitle')}</Text>
          <Text style={styles.recordsCount}>
            {t('profitShare.recordsCount', { count: total })}
          </Text>
        </View>

        {settledRecords.length === 0 ? (
          <View style={styles.emptyBlock}>
            <AppIcon name="bot" size={28} color={Colors.textMuted} />
            <Text style={styles.emptyTitle}>{t('profitShare.recordsEmptyTitle')}</Text>
            <Text style={styles.emptyDesc}>{t('profitShare.recordsEmptyDesc')}</Text>
          </View>
        ) : (
          <>
            {settledRecords.map((r) => (
              <View key={r.id} style={styles.recordRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.recordTime}>{fmtDate(r.created_at)}</Text>
                  <Text style={styles.recordSub}>
                    {t('profitShare.recordFrom', { name: maskShortId(r.follower_user_id, r.follower_name) })}
                    {r.position_info ? `  ·  ${r.position_info}` : ''}
                  </Text>
                  <Text style={styles.recordRate}>
                    {t('profitShare.recordRateLine', {
                      rate: fmtRatePct(r.rate_applied),
                      net: fmtUsdt(r.net_pnl),
                    })}
                  </Text>
                </View>
                <Text style={styles.recordAmount}>+{fmtUsdt(r.share_amount)} USDT</Text>
              </View>
            ))}

            {records.length < total ? (
              <TouchableOpacity
                style={[styles.loadMoreBtn, loadingMore && styles.saveRateBtnDisabled]}
                activeOpacity={0.85}
                disabled={loadingMore}
                onPress={() => void handleLoadMore()}
              >
                {loadingMore ? (
                  <ActivityIndicator size="small" color={Colors.primary} />
                ) : (
                  <Text style={styles.loadMoreText}>{t('profitShare.loadMore')}</Text>
                )}
              </TouchableOpacity>
            ) : (
              <Text style={styles.endHint}>{t('profitShare.listEnd')}</Text>
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
  pageSub: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
    lineHeight: 18,
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
  sectionDesc: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },

  // Rate row
  rateRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    marginTop: 4,
    flexWrap: 'wrap',
  },
  stepperBtn: {
    width: 38,
    height: 38,
    borderRadius: 10,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepperText: {
    color: Colors.primary,
    fontSize: 18,
    fontWeight: '800',
  },
  rateInputWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.inputBg,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderRadius: 10,
    paddingHorizontal: 12,
    minWidth: 100,
    height: 38,
  },
  rateInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
    paddingVertical: 0,
  },
  ratePct: {
    color: Colors.textMuted,
    fontSize: 14,
    fontWeight: '700',
    marginLeft: 4,
  },
  saveRateBtn: {
    paddingHorizontal: 16,
    height: 38,
    borderRadius: 10,
    backgroundColor: Colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  saveRateBtnDisabled: {
    opacity: 0.5,
  },
  saveRateText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '800',
  },

  // Notice card
  noticeCard: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 8,
    backgroundColor: 'rgba(242, 202, 80, 0.08)',
    borderWidth: 1,
    borderColor: 'rgba(242, 202, 80, 0.25)',
    borderRadius: 10,
    padding: 10,
    marginTop: 6,
  },
  noticeText: {
    flex: 1,
    color: Colors.warning,
    fontSize: 12,
    lineHeight: 18,
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
  recordRate: {
    color: Colors.textMuted,
    fontSize: 11,
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
