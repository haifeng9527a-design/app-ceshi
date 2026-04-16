import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import AppIcon from '../../components/ui/AppIcon';
import { Colors, Shadows } from '../../theme/colors';
import { getAssetTransactions, type AssetTransaction } from '../../services/api/assetsApi';
import { useAuthStore } from '../../services/store/authStore';

const PAGE_SIZE = 20;
const STATUS_FILTERS = ['all', 'pending_review', 'approved', 'processing', 'completed', 'rejected', 'failed'] as const;
type StatusFilter = (typeof STATUS_FILTERS)[number];

function formatUsd(value?: number) {
  const amount = Number.isFinite(value) ? Number(value) : 0;
  return amount.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatTransactionTime(value?: string) {
  if (!value) return '--';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '--';
  return d.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function resolveSignedTransactionAmount(tx: { direction: 'credit' | 'debit' | 'internal'; amount: number; net_amount: number; type: string }) {
  if (tx.type === 'spot_buy') return -Math.abs(tx.amount);
  if (tx.type === 'spot_sell') return Math.abs(tx.amount);
  if (tx.type === 'spot_fee') return -Math.abs(tx.amount);
  if (Number.isFinite(tx.net_amount) && tx.net_amount !== 0) {
    return Number(tx.net_amount);
  }
  if (tx.direction === 'credit') return Math.abs(tx.amount);
  if (tx.direction === 'debit') return -Math.abs(tx.amount);
  if (tx.type === 'transfer_to_futures') return -Math.abs(tx.amount);
  if (tx.type === 'transfer_to_main') return Math.abs(tx.amount);
  return Number(tx.amount) || 0;
}

function transactionAmountColor(value: number) {
  if (value > 0) return Colors.up;
  if (value < 0) return Colors.down;
  return Colors.primary;
}

function transactionLabel(type: string, t: (key: string) => string) {
  const keyMap: Record<string, string> = {
    deposit: 'assets.txDeposit',
    withdraw: 'assets.txWithdraw',
    order_freeze: 'assets.txOrderFreeze',
    order_unfreeze: 'assets.txOrderUnfreeze',
    trade_pnl: 'assets.txTradePnl',
    fee: 'assets.txFee',
    copy_allocate: 'assets.txCopyAllocate',
    copy_withdraw: 'assets.txCopyWithdraw',
    copy_pnl_settle: 'assets.txCopyPnlSettle',
    copy_profit_share_in: 'assets.txCopyProfitShareIn',
    copy_profit_share_out: 'assets.txCopyProfitShareOut',
    spot_buy: 'assets.txSpotBuy',
    spot_sell: 'assets.txSpotSell',
    spot_fee: 'assets.txSpotFee',
    transfer_to_futures: 'assets.txTransferToFutures',
    transfer_to_main: 'assets.txTransferToMain',
    referral_commission_in: 'assets.txReferralCommission',
    agent_override_in: 'assets.txAgentOverride',
  };
  return t(keyMap[type] || 'assets.txSystemAdjustment');
}

function transactionIconName(type: string): 'wallet' | 'send' | 'chart' | 'paper' {
  if (type === 'deposit') return 'wallet';
  if (type === 'withdraw') return 'send';
  if (type === 'copy_profit_share_in' || type === 'copy_profit_share_out') return 'chart';
  if (type === 'spot_buy' || type === 'spot_sell') return 'chart';
  if (type === 'spot_fee') return 'send';
  if (type.startsWith('transfer_')) return 'chart';
  return 'paper';
}

function withdrawalStatusLabel(status: string | undefined, t: (key: string) => string) {
  const keyMap: Record<string, string> = {
    pending_review: 'assets.withdrawStatusPendingReview',
    approved: 'assets.withdrawStatusApproved',
    processing: 'assets.withdrawStatusProcessing',
    completed: 'assets.withdrawStatusCompleted',
    rejected: 'assets.withdrawStatusRejected',
    failed: 'assets.withdrawStatusFailed',
  };
  return status ? t(keyMap[status] || 'assets.withdrawStatusCompleted') : '';
}

function accountDisplayLabel(accountType: string, t: (key: string) => string) {
  const keyMap: Record<string, string> = {
    main: 'assets.distributionMain',
    spot: 'assets.distributionMain',
    futures: 'assets.distributionFutures',
  };
  return t(keyMap[accountType] || 'assets.distributionMain');
}

export default function AssetTransactionsScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ status?: string }>();
  const { t } = useTranslation();
  const user = useAuthStore((s) => s.user);
  const [items, setItems] = useState<AssetTransaction[]>([]);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const initialStatus =
    typeof params.status === 'string' && (STATUS_FILTERS as readonly string[]).includes(params.status)
      ? (params.status as StatusFilter)
      : 'all';
  const [selectedStatus, setSelectedStatus] = useState<StatusFilter>(initialStatus);

  const loadTransactions = useCallback(
    async (mode: 'initial' | 'refresh' | 'more') => {
      if (!user?.uid) return;

      if (mode === 'initial') setLoading(true);
      if (mode === 'refresh') setRefreshing(true);
      if (mode === 'more') setLoadingMore(true);
      if (mode !== 'more') setError(null);

      try {
        const offset = mode === 'more' ? items.length : 0;
        const next = await getAssetTransactions(
          PAGE_SIZE,
          offset,
          selectedStatus === 'all' ? '' : selectedStatus,
        );
        setHasMore(next.length === PAGE_SIZE);
        setItems((current) => (mode === 'more' ? [...current, ...next] : next));
      } catch (e: any) {
        setError(e?.response?.data?.error || e?.message || t('assets.transactionsLoadFailed'));
      } finally {
        setLoading(false);
        setRefreshing(false);
        setLoadingMore(false);
      }
    },
    [items.length, selectedStatus, t, user?.uid],
  );

  useEffect(() => {
    void loadTransactions('initial');
  }, [loadTransactions, selectedStatus]);

  const statusFilters = useMemo(
    () => [
      { key: 'all' as StatusFilter, label: t('assets.transactionStatusFilterAll') },
      { key: 'pending_review' as StatusFilter, label: t('assets.transactionStatusFilterPending') },
      { key: 'approved' as StatusFilter, label: t('assets.transactionStatusFilterApproved') },
      { key: 'processing' as StatusFilter, label: t('assets.transactionStatusFilterProcessing') },
      { key: 'completed' as StatusFilter, label: t('assets.transactionStatusFilterCompleted') },
      { key: 'rejected' as StatusFilter, label: t('assets.transactionStatusFilterRejected') },
      { key: 'failed' as StatusFilter, label: t('assets.transactionStatusFilterFailed') },
    ],
    [t],
  );

  const summary = useMemo(() => {
    return items.reduce(
      (acc, item) => {
        const signedAmount = resolveSignedTransactionAmount(item);
        if (signedAmount > 0) {
          acc.inflow += signedAmount;
        } else if (signedAmount < 0) {
          acc.outflow += Math.abs(signedAmount);
        }
        return acc;
      },
      { inflow: 0, outflow: 0 },
    );
  }, [items]);

  if (!user) {
    return (
      <View style={styles.centerState}>
        <Text style={styles.centerTitle}>{t('assets.loginRequiredTitle')}</Text>
        <Text style={styles.centerBody}>{t('assets.loginRequiredBody')}</Text>
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void loadTransactions('refresh')} tintColor={Colors.primary} />}
    >
      <View style={styles.header}>
        <TouchableOpacity style={styles.backBtn} activeOpacity={0.8} onPress={() => router.back()}>
          <AppIcon name="back" size={18} color={Colors.textSecondary} />
        </TouchableOpacity>
        <View style={styles.headerBody}>
          <Text style={styles.title}>{t('assets.allTransactionsTitle')}</Text>
          <Text style={styles.subtitle}>{t('assets.allTransactionsSubtitle')}</Text>
        </View>
      </View>

      <View style={styles.summaryRow}>
        <View style={styles.summaryCard}>
          <Text style={styles.summaryLabel}>{t('assets.transactionsInflow')}</Text>
          <Text style={[styles.summaryValue, { color: Colors.up }]}>+{formatUsd(summary.inflow)} USDT</Text>
        </View>
        <View style={styles.summaryCard}>
          <Text style={styles.summaryLabel}>{t('assets.transactionsOutflow')}</Text>
          <Text style={[styles.summaryValue, { color: Colors.down }]}>-{formatUsd(summary.outflow)} USDT</Text>
        </View>
      </View>

      <View style={styles.filterCard}>
        <Text style={styles.filterTitle}>{t('assets.transactionStatusSection')}</Text>
        <View style={styles.filterRow}>
          {statusFilters.map((filter) => (
            <TouchableOpacity
              key={filter.key}
              style={[
                styles.filterChip,
                selectedStatus === filter.key && styles.filterChipActive,
              ]}
              activeOpacity={0.85}
              onPress={() => setSelectedStatus(filter.key)}
            >
              <Text
                style={[
                  styles.filterChipText,
                  selectedStatus === filter.key && styles.filterChipTextActive,
                ]}
              >
                {filter.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      <View style={styles.panelCard}>
        {error ? (
          <View style={styles.errorCard}>
            <Text style={styles.errorTitle}>{t('assets.transactionsLoadFailed')}</Text>
            <Text style={styles.errorBody}>{error}</Text>
          </View>
        ) : null}

        {loading ? (
          <View style={styles.centerState}>
            <ActivityIndicator color={Colors.primary} />
            <Text style={styles.centerBody}>{t('assets.loading')}</Text>
          </View>
        ) : items.length ? (
          <View style={styles.txList}>
            {items.map((tx) => {
              const signedAmount = resolveSignedTransactionAmount(tx);
              const positive = signedAmount > 0;
              const negative = signedAmount < 0;
              const internal = tx.direction === 'internal';
              return (
                <View key={tx.id} style={styles.txItem}>
                  <View style={styles.txHead}>
                    <View style={styles.txTitleCluster}>
                      <View
                        style={[
                          styles.txIconWrap,
                          positive && styles.txIconWrapSuccess,
                          negative && styles.txIconWrapDanger,
                          internal && styles.txIconWrapInfo,
                        ]}
                      >
                        <AppIcon
                          name={transactionIconName(tx.type)}
                          size={16}
                          color={transactionAmountColor(signedAmount)}
                        />
                      </View>
                      <View style={styles.txTitleBlock}>
                        <View style={styles.txTypeRow}>
                          <Text style={styles.txType}>{transactionLabel(tx.type, t)}</Text>
                          {tx.status ? (
                            <View
                              style={[
                                styles.statusBadge,
                                tx.status === 'completed' && styles.statusBadgeSuccess,
                                tx.status === 'rejected' && styles.statusBadgeDanger,
                                tx.status === 'failed' && styles.statusBadgeDanger,
                                tx.status === 'approved' && styles.statusBadgeInfo,
                                tx.status === 'processing' && styles.statusBadgeInfo,
                              ]}
                            >
                              <Text style={styles.statusBadgeText}>{withdrawalStatusLabel(tx.status, t)}</Text>
                            </View>
                          ) : null}
                        </View>
                        <Text style={styles.txTime}>{formatTransactionTime(tx.created_at)}</Text>
                      </View>
                    </View>
                    <Text style={[styles.txAmountHero, { color: transactionAmountColor(signedAmount) }]}>
                      {signedAmount > 0 ? '+' : signedAmount < 0 ? '-' : ''}{formatUsd(Math.abs(signedAmount))} USDT
                    </Text>
                  </View>

                  <View style={styles.txMain}>
                    <Text style={styles.txNote} numberOfLines={2}>{tx.note || '--'}</Text>
                    <View style={styles.txMetaGrid}>
                      <View style={styles.txMetaCard}>
                        <Text style={styles.txMetaLabel}>{internal ? t('assets.transferFromLabel') : t('assets.headerAccounts')}</Text>
                        <Text style={styles.txMetaValue}>
                          {accountDisplayLabel(tx.account_type, t)}
                        </Text>
                      </View>
                      <View style={styles.txMetaCard}>
                        <Text style={styles.txMetaLabel}>
                          {internal ? t('assets.transferToLabel') : t('assets.transactionBalanceAfter')}
                        </Text>
                        <Text style={styles.txMetaValue}>
                          {internal
                            ? accountDisplayLabel(tx.counterparty_account_type || 'futures', t)
                            : `${formatUsd(tx.balance_after)} USDT`}
                        </Text>
                      </View>
                    </View>
                  </View>
                </View>
              );
            })}

            {hasMore ? (
              <TouchableOpacity
                style={styles.loadMoreBtn}
                activeOpacity={0.85}
                onPress={() => void loadTransactions('more')}
                disabled={loadingMore}
              >
                <Text style={styles.loadMoreText}>
                  {loadingMore ? t('assets.loading') : t('assets.loadMoreTransactions')}
                </Text>
              </TouchableOpacity>
            ) : (
              <Text style={styles.endText}>{t('assets.transactionsEnd')}</Text>
            )}
          </View>
        ) : (
          <Text style={styles.emptyText}>{t('assets.emptyTransactions')}</Text>
        )}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  content: {
    padding: 20,
    gap: 18,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  backBtn: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
  },
  headerBody: {
    flex: 1,
  },
  title: {
    color: Colors.textActive,
    fontSize: 28,
    fontWeight: '800',
  },
  subtitle: {
    marginTop: 6,
    color: Colors.textSecondary,
    fontSize: 14,
  },
  summaryRow: {
    flexDirection: 'row',
    gap: 12,
    flexWrap: 'wrap',
  },
  filterCard: {
    gap: 10,
  },
  filterTitle: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
  },
  filterRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  filterChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  filterChipActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  filterChipText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },
  filterChipTextActive: {
    color: Colors.primary,
  },
  summaryCard: {
    flexGrow: 1,
    minWidth: 220,
    backgroundColor: Colors.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 8,
    ...Shadows.card,
  },
  summaryLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  summaryValue: {
    fontSize: 22,
    fontWeight: '800',
  },
  panelCard: {
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 18,
    ...Shadows.card,
  },
  txList: {
    gap: 12,
  },
  txItem: {
    gap: 14,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
  },
  txHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 12,
  },
  txMain: {
    flex: 1,
    gap: 10,
  },
  txTitleCluster: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  txTitleBlock: {
    flex: 1,
    gap: 6,
  },
  txIconWrap: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  txIconWrapSuccess: {
    backgroundColor: Colors.up + '12',
    borderColor: Colors.up + '22',
  },
  txIconWrapDanger: {
    backgroundColor: Colors.down + '12',
    borderColor: Colors.down + '22',
  },
  txIconWrapInfo: {
    backgroundColor: Colors.primary + '12',
    borderColor: Colors.primary + '22',
  },
  txTypeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexWrap: 'wrap',
  },
  txType: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  statusBadge: {
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 3,
    backgroundColor: Colors.surfaceAlt,
  },
  statusBadgeSuccess: {
    backgroundColor: 'rgba(16, 185, 129, 0.16)',
  },
  statusBadgeDanger: {
    backgroundColor: 'rgba(239, 68, 68, 0.16)',
  },
  statusBadgeInfo: {
    backgroundColor: 'rgba(212, 181, 76, 0.18)',
  },
  statusBadgeText: {
    color: Colors.textSecondary,
    fontSize: 11,
    fontWeight: '700',
  },
  txNote: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  txMeta: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  txAmountHero: {
    fontSize: 18,
    fontWeight: '900',
    textAlign: 'right',
  },
  txTime: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  txMetaGrid: {
    flexDirection: 'row',
    gap: 10,
    flexWrap: 'wrap',
  },
  txMetaCard: {
    flexGrow: 1,
    minWidth: 140,
    backgroundColor: Colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 4,
  },
  txMetaLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  txMetaValue: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '800',
  },
  loadMoreBtn: {
    alignSelf: 'center',
    marginTop: 4,
    borderRadius: 14,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  loadMoreText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '800',
  },
  endText: {
    color: Colors.textMuted,
    fontSize: 12,
    textAlign: 'center',
    marginTop: 4,
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
  },
  centerState: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 36,
    gap: 10,
  },
  centerTitle: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '800',
  },
  centerBody: {
    color: Colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
  errorCard: {
    backgroundColor: Colors.downDim,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,180,171,0.22)',
    padding: 16,
    gap: 6,
    marginBottom: 12,
  },
  errorTitle: {
    color: Colors.down,
    fontSize: 15,
    fontWeight: '800',
  },
  errorBody: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 19,
  },
});
