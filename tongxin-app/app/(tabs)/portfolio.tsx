import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Modal,
  Platform,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  useWindowDimensions,
  View,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useFocusEffect, useRouter } from 'expo-router';
import QRCode from 'react-native-qrcode-svg';
import { Colors, Shadows } from '../../theme/colors';
import AppIcon from '../../components/ui/AppIcon';
import { showAlert } from '../../services/utils/dialog';
import { useAssetsStore } from '../../services/store/assetsStore';
import { useAuthStore } from '../../services/store/authStore';
import { Config } from '../../services/config';
import { ChangeSeriesChart, DistributionChart, PnlCalendar } from '../../components/assets/AssetsCharts';
import {
  getCopyAccountHistory,
  getCopyAccountOpenPositions,
  getCopyAccountOverview,
  getCopyAccountPools,
  getSpotHoldings,
  getDepositAddresses,
  getDepositOptions,
  getDepositRecords,
  transferAssets,
  withdrawFromSpotAccount,
  type CopyAccountHistoryItem,
  type CopyAccountOverviewResponse,
  type CopyAccountOpenPositionItem,
  type CopyAccountPoolItem,
  type AssetDepositAddress,
  type AssetDepositAssetOption,
  type AssetDepositRecord,
  type AssetRangeKey,
  type SpotHoldingItem,
} from '../../services/api/assetsApi';
import { toDisplaySymbol } from '../../services/utils/symbolFormat';

function formatUsd(value?: number) {
  const amount = Number.isFinite(value) ? Number(value) : 0;
  return amount.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatSignedUsd(value?: number) {
  const amount = Number.isFinite(value) ? Number(value) : 0;
  return `${amount >= 0 ? '+' : '-'}${formatUsd(Math.abs(amount))}`;
}

function formatTransactionTime(value?: string) {
  if (!value) return '--';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '--';
  return d.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function formatPercent(value?: number) {
  const amount = Number.isFinite(value) ? Number(value) : 0;
  return `${(amount * 100).toFixed(2)}%`;
}

function formatAssetQuantity(value?: number) {
  const amount = Number.isFinite(value) ? Number(value) : 0;
  return amount.toLocaleString(undefined, {
    minimumFractionDigits: amount >= 100 ? 2 : 4,
    maximumFractionDigits: amount >= 100 ? 2 : 8,
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

function resolveAssetIconUrl(url?: string | null) {
  if (!url) return null;
  return url.startsWith('/') ? `${Config.API_BASE_URL}${url}` : url;
}

function AssetGlyph({
  item,
}: {
  item: SpotHoldingItem;
}) {
  const [failed, setFailed] = useState(false);
  const resolvedIconUrl = useMemo(() => resolveAssetIconUrl(item.icon_url || null), [item.icon_url]);
  const fallbackName = item.category === 'crypto' ? 'bitcoin' : 'chart';
  const fallbackColor = item.category === 'crypto' ? Colors.primary : '#7FA7FF';

  if (resolvedIconUrl && !failed) {
    return (
      <Image
        source={{ uri: resolvedIconUrl }}
        style={styles.assetIconImage}
        resizeMode="contain"
        onError={() => setFailed(true)}
      />
    );
  }

  return <AppIcon name={fallbackName} size={16} color={fallbackColor} />;
}

function formatRealtimeClock(value?: number | null) {
  if (!value) return '--:--:--';
  const d = new Date(value);
  return d.toLocaleTimeString(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
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

function copyStatusLabel(status: string, t: (key: string) => string) {
  const keyMap: Record<string, string> = {
    active: 'assets.copyStatusActive',
    paused: 'assets.copyStatusPaused',
    stopped: 'assets.copyStatusStopped',
  };
  return t(keyMap[status] || 'assets.copyStatusStopped');
}

function accountDisplayLabel(accountType: string, fallback: string, t: (key: string) => string) {
  const keyMap: Record<string, string> = {
    main: 'assets.distributionMain',
    spot: 'assets.distributionMain',
    futures: 'assets.distributionFutures',
  };
  return keyMap[accountType] ? t(keyMap[accountType]) : fallback;
}

function accountTypeCodeLabel(accountType: string) {
  const keyMap: Record<string, string> = {
    main: 'SPOT',
    spot: 'SPOT',
    futures: 'FUTURES',
  };
  return keyMap[accountType] || accountType.toUpperCase();
}

const DEFAULT_SPOT_DEPOSIT_OPTIONS: AssetDepositAssetOption[] = [
  {
    asset_code: 'USDT',
    label: 'USDT',
    networks: [
      { value: 'TRC20', label: 'TRC20' },
      { value: 'ERC20', label: 'ERC20' },
      { value: 'BEP20', label: 'BEP20' },
    ],
  },
  {
    asset_code: 'USDC',
    label: 'USDC',
    networks: [{ value: 'ERC20', label: 'ERC20' }],
  },
  {
    asset_code: 'BTC',
    label: 'BTC',
    networks: [{ value: 'BTC', label: 'BTC' }],
  },
  {
    asset_code: 'ETH',
    label: 'ETH',
    networks: [{ value: 'ERC20', label: 'ERC20' }],
  },
  {
    asset_code: 'TRX',
    label: 'TRX',
    networks: [{ value: 'TRC20', label: 'TRC20' }],
  },
  {
    asset_code: 'TON',
    label: 'TON',
    networks: [{ value: 'TON', label: 'TON' }],
  },
];

const DEFAULT_ASSET_CATEGORY: 'all' | 'crypto' | 'stock' = 'all';
const DEFAULT_OWNED_ONLY = true;
const DEFAULT_HIDE_DUST = false;
const DEFAULT_ASSET_SEARCH = '';

const spotHoldingsCache = new Map<string, SpotHoldingItem[]>();

function buildSpotHoldingsCacheKey(
  userID: string | undefined,
  category: 'all' | 'crypto' | 'stock',
  ownedOnly: boolean,
  hideDust: boolean,
  query: string,
) {
  return [
    userID || 'guest',
    category,
    ownedOnly ? 'owned' : 'all',
    hideDust ? 'hide-dust' : 'show-dust',
    query.trim().toLowerCase(),
  ].join('::');
}

function depositStatusLabel(status: string | undefined, t: (key: string) => string) {
  const keyMap: Record<string, string> = {
    pending_confirm: 'assets.depositStatusPending',
    credited: 'assets.depositStatusCredited',
    failed: 'assets.depositStatusFailed',
    detected: 'assets.depositStatusDetected',
  };
  return status ? t(keyMap[status] || 'assets.depositStatusDetected') : '';
}

export default function AssetsScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 1100;
  const user = useAuthStore((s) => s.user);
  const {
    overview,
    liveOverview,
    range,
    calendar,
    calendarLoading,
    calendarYear,
    calendarMonth,
    positions,
    lastRealtimeAt,
    wsConnected,
    loading,
    refreshing,
    error,
    fetchOverview,
    setRange,
    fetchCalendar,
    connectRealtime,
    disconnectRealtime,
    reset,
  } = useAssetsStore();
  const [selectedAccountType, setSelectedAccountType] = useState<string | null>(null);
  const [selectedCopyTraderUid, setSelectedCopyTraderUid] = useState<string | null>(null);
  const [showDepositModal, setShowDepositModal] = useState(false);
  const [depositAssetCode, setDepositAssetCode] = useState('USDT');
  const [depositNetwork, setDepositNetwork] = useState('TRC20');
  const [showDepositAssetMenu, setShowDepositAssetMenu] = useState(false);
  const [depositAddressRecord, setDepositAddressRecord] = useState<AssetDepositAddress | null>(null);
  const [depositRecords, setDepositRecords] = useState<AssetDepositRecord[]>([]);
  const [depositOptions, setDepositOptions] = useState<AssetDepositAssetOption[]>(DEFAULT_SPOT_DEPOSIT_OPTIONS);
  const [loadingDepositAddress, setLoadingDepositAddress] = useState(false);
  const [loadingDepositRecords, setLoadingDepositRecords] = useState(false);
  const [showWithdrawModal, setShowWithdrawModal] = useState(false);
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [withdrawAddress, setWithdrawAddress] = useState('');
  const [withdrawNetwork, setWithdrawNetwork] = useState('TRC20');
  const [showWithdrawNetworkMenu, setShowWithdrawNetworkMenu] = useState(false);
  const [withdrawing, setWithdrawing] = useState(false);
  const [showTransferModal, setShowTransferModal] = useState(false);
  const [transferAmount, setTransferAmount] = useState('');
  const [transferDirection, setTransferDirection] = useState<'spot_to_futures' | 'futures_to_spot'>('spot_to_futures');
  const [transferring, setTransferring] = useState(false);
  const [realtimeNow, setRealtimeNow] = useState(() => Date.now());
  const [showRealtimeDriversModal, setShowRealtimeDriversModal] = useState(false);
  const [showPnlCalendarModal, setShowPnlCalendarModal] = useState(false);
  const [selectedCalendarDate, setSelectedCalendarDate] = useState<string | null>(null);
  const [assetCategory, setAssetCategory] = useState<'all' | 'crypto' | 'stock'>(DEFAULT_ASSET_CATEGORY);
  const [assetSearch, setAssetSearch] = useState(DEFAULT_ASSET_SEARCH);
  const [assetSearchDebounced, setAssetSearchDebounced] = useState(DEFAULT_ASSET_SEARCH);
  const [ownedOnly, setOwnedOnly] = useState(DEFAULT_OWNED_ONLY);
  const [hideDust, setHideDust] = useState(DEFAULT_HIDE_DUST);
  const [workspaceView, setWorkspaceView] = useState<'assets' | 'accounts' | 'copy'>('assets');
  const [spotHoldings, setSpotHoldings] = useState<SpotHoldingItem[]>(() => {
    const defaultCacheKey = buildSpotHoldingsCacheKey(
      user?.uid,
      DEFAULT_ASSET_CATEGORY,
      DEFAULT_OWNED_ONLY,
      DEFAULT_HIDE_DUST,
      DEFAULT_ASSET_SEARCH,
    );
    return spotHoldingsCache.get(defaultCacheKey) || [];
  });
  const [spotHoldingsLoading, setSpotHoldingsLoading] = useState(() => {
    const defaultCacheKey = buildSpotHoldingsCacheKey(
      user?.uid,
      DEFAULT_ASSET_CATEGORY,
      DEFAULT_OWNED_ONLY,
      DEFAULT_HIDE_DUST,
      DEFAULT_ASSET_SEARCH,
    );
    return !spotHoldingsCache.has(defaultCacheKey);
  });
  const [copyAccountOverview, setCopyAccountOverview] = useState<CopyAccountOverviewResponse | null>(null);
  const [copyAccountPools, setCopyAccountPools] = useState<CopyAccountPoolItem[]>([]);
  const [copyAccountPositions, setCopyAccountPositions] = useState<CopyAccountOpenPositionItem[]>([]);
  const [copyAccountHistory, setCopyAccountHistory] = useState<CopyAccountHistoryItem[]>([]);
  const [copyAccountHistoryTotal, setCopyAccountHistoryTotal] = useState(0);
  const [copyAccountLoading, setCopyAccountLoading] = useState(false);
  const [copyActivityTab, setCopyActivityTab] = useState<'positions' | 'history'>('positions');

  useEffect(() => {
    if (!user?.uid) {
      disconnectRealtime();
      reset();
      return;
    }
    void fetchOverview();
    void fetchCalendar();
  }, [disconnectRealtime, fetchOverview, reset, user?.uid]);

  useFocusEffect(
    useCallback(() => {
      if (user?.uid) {
        connectRealtime();
        void fetchOverview({ silent: true });
        void fetchCalendar();
      }
      return () => {
        disconnectRealtime();
      };
    }, [connectRealtime, disconnectRealtime, fetchCalendar, fetchOverview, user?.uid]),
  );

  useEffect(() => {
    const timer = setInterval(() => {
      setRealtimeNow(Date.now());
    }, 5000);
    return () => clearInterval(timer);
  }, []);

  const displayOverview = liveOverview || overview;
  const pnlPositive = (displayOverview?.today_pnl || 0) >= 0;
  const accountCards = displayOverview?.accounts || [];
  const transactions = displayOverview?.recent_transactions || [];
  const pendingWithdrawals = displayOverview?.pending_withdrawals || [];
  const pendingWithdrawalCount = displayOverview?.pending_withdrawal_count || 0;
  const pendingWithdrawalAmount = displayOverview?.pending_withdrawal_amount || 0;
  const copySummary = displayOverview?.copy_summary;
  const spotAccount = accountCards.find((account) => account.account_type === 'spot' || account.account_type === 'main');
  const futuresAccount = accountCards.find((account) => account.account_type === 'futures');
  const spotAvailable = spotAccount?.available || 0;
  const selectedAccount = accountCards.find((account) => account.account_type === selectedAccountType) || accountCards[0];
  const selectedCopyItem = copySummary?.items?.find((item) => item.trader_uid === selectedCopyTraderUid) || copySummary?.items?.[0];
  const selectedCopyPool =
    copyAccountPools.find((item) => item.trader_uid === selectedCopyTraderUid) || copyAccountPools[0];
  const copyUtilization = selectedCopyItem?.allocated_capital
    ? selectedCopyItem.frozen_capital / selectedCopyItem.allocated_capital
    : 0;
  const copyPoolUtilization = selectedCopyPool?.allocated_capital
    ? selectedCopyPool.frozen_capital / selectedCopyPool.allocated_capital
    : 0;
  const copyCurrentNetPnl =
    (copyAccountOverview?.total_equity || 0) - (copyAccountOverview?.total_allocated || 0);

  // 把 useAssetsStore.positions（由 tradingWs 实时推送）合并进当前选中池子的跟单仓位：
  // - REST `getCopyAccountOpenPositions` 提供初始 snapshot（含 trader_name、opened_at 等元数据）
  // - WebSocket 推送 position_update 持续更新 current_price / unrealized_pnl / roe / margin_amount
  // - 如果 WS 先于 REST 拿到新开仓，用 snapshot 字段补全后插入到列表头
  const liveCopyPositions = useMemo<CopyAccountOpenPositionItem[]>(() => {
    if (!selectedCopyPool) return copyAccountPositions;
    const liveMap = new Map<string, (typeof positions)[number]>();
    for (const p of positions) {
      if (!p.is_copy_trade) continue;
      if (p.copy_trading_id !== selectedCopyPool.copy_trading_id) continue;
      liveMap.set(p.id, p);
    }
    const merged = copyAccountPositions.map((item) => {
      const live = liveMap.get(item.position_id);
      if (!live) return item;
      return {
        ...item,
        current_price: live.current_price ?? item.current_price,
        unrealized_pnl: live.unrealized_pnl ?? item.unrealized_pnl,
        margin_amount: live.margin_amount ?? item.margin_amount,
        roe: live.roe ?? item.roe,
      };
    });
    const known = new Set(copyAccountPositions.map((i) => i.position_id));
    for (const [id, p] of liveMap) {
      if (known.has(id)) continue;
      merged.unshift({
        position_id: id,
        copy_trading_id: p.copy_trading_id || selectedCopyPool.copy_trading_id,
        trader_uid: p.source_trader_id || selectedCopyPool.trader_uid,
        trader_name: selectedCopyPool.trader_name,
        symbol: p.symbol,
        side: p.side,
        qty: p.qty,
        entry_price: p.entry_price,
        current_price: p.current_price || 0,
        margin_amount: p.margin_amount,
        unrealized_pnl: p.unrealized_pnl || 0,
        roe: p.roe || 0,
        leverage: p.leverage,
        opened_at: p.created_at,
      });
    }
    return merged;
  }, [copyAccountPositions, positions, selectedCopyPool]);

  // 所有跟单仓位的浮盈浮亏合计（跨池子），用于顶部"未实现盈亏"卡片的实时展示，
  // 避免依赖 REST overview 的快照值（会与仓位列表合计出现短暂不一致）。
  const liveCopyUnrealizedPnlAll = useMemo(
    () =>
      positions
        .filter((p) => p.is_copy_trade)
        .reduce((sum, p) => sum + (p.unrealized_pnl || 0), 0),
    [positions],
  );

  // "跟单资金"侧栏展示 PNL / ROI 时需要的池子详情来自 copyAccountPools（由
  // loadCopyAccountOverviewAndPools 加载）。用 trader_uid 建 map 做 O(1) 查询，
  // 避免每次渲染都 find。
  const copyPoolByTrader = useMemo(() => {
    const map = new Map<string, CopyAccountPoolItem>();
    for (const pool of copyAccountPools) {
      map.set(pool.trader_uid, pool);
    }
    return map;
  }, [copyAccountPools]);
  const withdrawValue = Number.parseFloat(withdrawAmount || '0');
  const canSubmitWithdraw =
    Number.isFinite(withdrawValue) &&
    withdrawValue > 0 &&
    withdrawValue <= spotAvailable &&
    withdrawAddress.trim().length > 0 &&
    withdrawNetwork.trim().length > 0 &&
    !withdrawing;
  const transferValue = Number.parseFloat(transferAmount || '0');
  const transferSourceAccount = transferDirection === 'spot_to_futures' ? spotAccount : futuresAccount;
  const transferTargetAccount = transferDirection === 'spot_to_futures' ? futuresAccount : spotAccount;
  const transferSourceAvailable = transferSourceAccount?.available || 0;
  const transferTargetAvailable = transferTargetAccount?.available || 0;
  const transferAvailableAfter = Math.max(transferSourceAvailable - (Number.isFinite(transferValue) ? transferValue : 0), 0);
  const canSubmitTransfer =
    Number.isFinite(transferValue) &&
    transferValue > 0 &&
    transferValue <= transferSourceAvailable &&
    !transferring;
  const distributionItems = useMemo(() => {
    const mainAccount = accountCards.find((account) => account.account_type === 'spot' || account.account_type === 'main');
    const futuresAccount = accountCards.find((account) => account.account_type === 'futures');
    const copyValue = (copySummary?.total_available || 0) + (copySummary?.total_frozen || 0);
    return [
      { key: 'main', label: t('assets.distributionMain'), value: mainAccount?.equity || 0, color: '#7ED9A3' },
      { key: 'futures', label: t('assets.distributionFutures'), value: futuresAccount?.equity || 0, color: Colors.primary },
      { key: 'copy', label: t('assets.distributionCopy'), value: copyValue, color: '#7FA7FF' },
    ];
  }, [accountCards, copySummary?.total_available, copySummary?.total_frozen, t]);

  const topGridStyle = useMemo(
    () => [styles.topGrid, isDesktop && styles.topGridDesktop],
    [isDesktop],
  );
  const actionGridStyle = useMemo(
    () => [styles.actionsRow, isDesktop && styles.actionsRowDesktop],
    [isDesktop],
  );
  const detailGridStyle = useMemo(
    () => [styles.detailGrid, isDesktop && styles.detailGridDesktop],
    [isDesktop],
  );
  const realtimeDrivers = useMemo(
    () => [...positions].sort((a, b) => Math.abs(b.unrealized_pnl || 0) - Math.abs(a.unrealized_pnl || 0)),
    [positions],
  );
  const changeRangeOptions: { key: AssetRangeKey; label: string }[] = [
    { key: '1d', label: t('assets.changeRange1d') },
    { key: '7d', label: t('assets.changeRange7d') },
    { key: '30d', label: t('assets.changeRange30d') },
    { key: '90d', label: t('assets.changeRange90d') },
  ];
  const calendarWeekdays = [
    t('assets.weekdaySun'),
    t('assets.weekdayMon'),
    t('assets.weekdayTue'),
    t('assets.weekdayWed'),
    t('assets.weekdayThu'),
    t('assets.weekdayFri'),
    t('assets.weekdaySat'),
  ];
  const calendarMonthLabel = useMemo(() => {
    if (calendar?.month_label) {
      const [yearPart, monthPart] = calendar.month_label.split('-');
      return `${yearPart}/${monthPart}`;
    }
    return `${calendarYear}/${String(calendarMonth).padStart(2, '0')}`;
  }, [calendar?.month_label, calendarMonth, calendarYear]);
  const selectedCalendarDay = useMemo(() => {
    const days = calendar?.days || [];
    if (!days.length) return null;
    if (selectedCalendarDate) {
      const matched = days.find((item) => item.date === selectedCalendarDate);
      if (matched) return matched;
    }
    return days.find((item) => item.is_today) || [...days].reverse().find((item) => item.has_data) || days[days.length - 1];
  }, [calendar?.days, selectedCalendarDate]);
  const selectedCalendarCumulative = useMemo(() => {
    if (!calendar?.days?.length || !selectedCalendarDay) return 0;
    return calendar.days
      .filter((item) => item.date <= selectedCalendarDay.date)
      .reduce((sum, item) => sum + (item.net_pnl || 0), 0);
  }, [calendar?.days, selectedCalendarDay]);
  const realtimeAge = lastRealtimeAt ? realtimeNow - lastRealtimeAt : Number.POSITIVE_INFINITY;
  const realtimeStatus: 'live' | 'syncing' | 'paused' =
    !user?.uid || !wsConnected || !lastRealtimeAt
      ? 'syncing'
      : realtimeAge <= 15000
        ? 'live'
        : 'paused';
  const realtimeStatusColor =
    realtimeStatus === 'live'
      ? Colors.up
      : realtimeStatus === 'syncing'
        ? Colors.primary
        : Colors.textMuted;
  const realtimeStatusLabel =
    realtimeStatus === 'live'
      ? t('assets.realtimeLive')
      : realtimeStatus === 'syncing'
      ? t('assets.realtimeSyncing')
        : t('assets.realtimePaused');
  const actionCards = [
    {
      key: 'deposit',
      icon: 'wallet' as const,
      title: t('assets.depositAction'),
      body: t('assets.depositActionHint'),
      primary: true,
      onPress: () => setShowDepositModal(true),
    },
    {
      key: 'transfer',
      icon: 'chart' as const,
      title: t('assets.transferAction'),
      body: t('assets.transferActionHint'),
      primary: false,
      onPress: () => setShowTransferModal(true),
    },
    {
      key: 'withdraw',
      icon: 'send' as const,
      title: t('assets.withdrawAction'),
      body: t('assets.withdrawActionHint'),
      primary: false,
      onPress: () => setShowWithdrawModal(true),
    },
    {
      key: 'transactions',
      icon: 'paper' as const,
      title: t('assets.allTransactionsAction'),
      body: t('assets.allTransactionsHint'),
      primary: false,
      onPress: () => router.push('/portfolio/transactions' as any),
    },
  ];
  const selectedDepositAsset = useMemo(
    () => depositOptions.find((item) => item.asset_code === depositAssetCode) || depositOptions[0],
    [depositAssetCode, depositOptions],
  );
  const assetOptionSource = depositOptions.length ? depositOptions : DEFAULT_SPOT_DEPOSIT_OPTIONS;
  const depositNetworks = selectedDepositAsset?.networks || [];
  const withdrawAsset = useMemo(
    () => depositOptions.find((item) => item.asset_code === 'USDT') || DEFAULT_SPOT_DEPOSIT_OPTIONS[0],
    [depositOptions],
  );
  const withdrawNetworks = withdrawAsset?.networks || [];
  const withdrawEstimatedReceive = Number.isFinite(withdrawValue) && withdrawValue > 0 ? withdrawValue : 0;
  const withdrawAvailableAfter = Math.max(spotAvailable - withdrawEstimatedReceive, 0);
  const spotHoldingsCacheKey = useMemo(
    () => buildSpotHoldingsCacheKey(user?.uid, assetCategory, ownedOnly, hideDust, assetSearchDebounced),
    [assetCategory, assetSearchDebounced, hideDust, ownedOnly, user?.uid],
  );
  const depositAddressPreview = useMemo(() => {
    const address = depositAddressRecord?.address || '';
    if (!address) {
      return { prefix: '', middle: '', suffix: '', fontSize: 16 };
    }
    if (address.length <= 6) {
      return { prefix: address, middle: '', suffix: '', fontSize: 16 };
    }
    const fontSize = address.length > 72 ? 11 : address.length > 60 ? 12 : address.length > 48 ? 13 : 15;
    return {
      prefix: address.slice(0, 3),
      middle: address.slice(3, -3),
      suffix: address.slice(-3),
      fontSize,
    };
  }, [depositAddressRecord?.address]);

  useEffect(() => {
    const timer = setTimeout(() => {
      setAssetSearchDebounced(assetSearch.trim());
    }, 250);
    return () => clearTimeout(timer);
  }, [assetSearch]);

  const handleOpenAssetDeposit = useCallback((assetCode: string, networks: AssetDepositAssetOption['networks']) => {
    setDepositAssetCode(assetCode);
    if (networks.length) {
      setDepositNetwork(networks[0].value);
    }
    setShowDepositModal(true);
  }, []);

  useEffect(() => {
    if (!depositNetworks.length) return;
    if (!depositNetworks.some((item) => item.value === depositNetwork)) {
      setDepositNetwork(depositNetworks[0].value);
    }
  }, [depositNetwork, depositNetworks]);

  useEffect(() => {
    if (!withdrawNetworks.length) return;
    if (!withdrawNetworks.some((item) => item.value === withdrawNetwork)) {
      setWithdrawNetwork(withdrawNetworks[0].value);
    }
  }, [withdrawNetwork, withdrawNetworks]);

  useEffect(() => {
    if (!accountCards.length) {
      setSelectedAccountType(null);
      return;
    }
    setSelectedAccountType((current) =>
      current && accountCards.some((account) => account.account_type === current)
        ? current
        : accountCards[0].account_type,
    );
  }, [accountCards]);

  useEffect(() => {
    if (!user?.uid) {
      setSpotHoldings([]);
      return;
    }
    const cached = spotHoldingsCache.get(spotHoldingsCacheKey);
    if (cached?.length) {
      setSpotHoldings(cached);
    }
  }, [spotHoldingsCacheKey, user?.uid]);

  const loadSpotHoldings = useCallback(async () => {
    if (!user?.uid) {
      setSpotHoldings([]);
      return;
    }
    const cached = spotHoldingsCache.get(spotHoldingsCacheKey);
    if (!cached?.length) {
      setSpotHoldingsLoading(true);
    }
    try {
      const resp = await getSpotHoldings(assetCategory, ownedOnly, hideDust, assetSearchDebounced);
      const items = resp.items || [];
      setSpotHoldings(items);
      spotHoldingsCache.set(spotHoldingsCacheKey, items);
    } catch {
      // Keep the last successful holdings snapshot so the asset tab does not flash empty.
    } finally {
      setSpotHoldingsLoading(false);
    }
  }, [assetCategory, assetSearchDebounced, hideDust, ownedOnly, spotHoldingsCacheKey, user?.uid]);

  useEffect(() => {
    void loadSpotHoldings();
  }, [loadSpotHoldings]);

  const loadCopyAccountOverviewAndPools = useCallback(async () => {
    if (!user?.uid) {
      setCopyAccountOverview(null);
      setCopyAccountPools([]);
      return;
    }
    setCopyAccountLoading(true);
    try {
      const [overviewResp, poolsResp] = await Promise.all([
        getCopyAccountOverview(),
        getCopyAccountPools('current'),
      ]);
      setCopyAccountOverview(overviewResp);
      setCopyAccountPools(poolsResp.items || []);
    } catch {
      setCopyAccountOverview(null);
      setCopyAccountPools([]);
    } finally {
      setCopyAccountLoading(false);
    }
  }, [user?.uid]);

  const loadCopyAccountActivity = useCallback(async (traderUID: string) => {
    if (!user?.uid) {
      setCopyAccountPositions([]);
      setCopyAccountHistory([]);
      setCopyAccountHistoryTotal(0);
      return;
    }
    setCopyAccountLoading(true);
    try {
      const [positionsResp, historyResp] = await Promise.all([
        getCopyAccountOpenPositions(traderUID),
        getCopyAccountHistory(traderUID, 20, 0),
      ]);
      setCopyAccountPositions(positionsResp.items || []);
      setCopyAccountHistory(historyResp.items || []);
      setCopyAccountHistoryTotal(historyResp.total_count || 0);
    } catch {
      setCopyAccountPositions([]);
      setCopyAccountHistory([]);
      setCopyAccountHistoryTotal(0);
    } finally {
      setCopyAccountLoading(false);
    }
  }, [user?.uid]);

  useEffect(() => {
    void loadCopyAccountOverviewAndPools();
  }, [loadCopyAccountOverviewAndPools]);

  useEffect(() => {
    if (!copySummary?.items?.length) {
      setSelectedCopyTraderUid(null);
      return;
    }
    setSelectedCopyTraderUid((current) =>
      current && copySummary.items.some((item) => item.trader_uid === current)
        ? current
        : copySummary.items[0].trader_uid,
    );
  }, [copySummary]);

  useEffect(() => {
    if (!copyAccountPools.length) {
      return;
    }
    setSelectedCopyTraderUid((current) =>
      current && copyAccountPools.some((item) => item.trader_uid === current)
        ? current
        : copyAccountPools[0].trader_uid,
      );
  }, [copyAccountPools]);

  useEffect(() => {
    if (!selectedCopyTraderUid) {
      setCopyAccountPositions([]);
      setCopyAccountHistory([]);
      setCopyAccountHistoryTotal(0);
      return;
    }
    void loadCopyAccountActivity(selectedCopyTraderUid);
  }, [loadCopyAccountActivity, selectedCopyTraderUid]);

  const showMessage = useCallback(
    (title: string, body: string) => {
      showAlert(body, title);
    },
    [],
  );

  const loadDepositAddress = useCallback(async (assetCode: string, network: string) => {
    setLoadingDepositAddress(true);
    try {
      const existing = await getDepositAddresses(assetCode, network);
      setDepositAddressRecord(existing[0] || null);
    } catch (e: any) {
      showMessage(
        t('assets.depositFailedTitle'),
        e?.response?.data?.error || e?.message || t('assets.depositAddressLoadFailed'),
      );
    } finally {
      setLoadingDepositAddress(false);
    }
  }, [showMessage, t]);

  const loadDepositHistory = useCallback(async (assetCode: string) => {
    setLoadingDepositRecords(true);
    try {
      const items = await getDepositRecords(assetCode, 8, 0);
      setDepositRecords(items);
    } catch (e: any) {
      showMessage(
        t('assets.depositFailedTitle'),
        e?.response?.data?.error || e?.message || t('assets.depositHistoryLoadFailed'),
      );
    } finally {
      setLoadingDepositRecords(false);
    }
  }, [showMessage, t]);

  const loadDepositOptions = useCallback(async () => {
    try {
      const items = await getDepositOptions();
      if (!items.length) return;
      setDepositOptions(items);
      if (!items.some((item) => item.asset_code === depositAssetCode)) {
        setDepositAssetCode(items[0].asset_code);
      }
    } catch {
      setDepositOptions(DEFAULT_SPOT_DEPOSIT_OPTIONS);
    }
  }, [depositAssetCode]);

  useEffect(() => {
    if (!user?.uid) return;
    void loadDepositOptions();
  }, [loadDepositOptions, user?.uid]);

  const handleRefreshDepositAddress = useCallback(async () => {
    await loadDepositAddress(depositAssetCode, depositNetwork);
  }, [depositAssetCode, depositNetwork, loadDepositAddress]);

  const handleCopyDepositAddress = useCallback(async () => {
    if (!depositAddressRecord?.address) return;
    try {
      if (Platform.OS === 'web' && typeof navigator !== 'undefined' && navigator.clipboard) {
        await navigator.clipboard.writeText(depositAddressRecord.address);
        showMessage(t('assets.depositCopySuccessTitle'), t('assets.depositCopySuccessBody'));
        return;
      }
      showMessage(t('assets.depositAddressLabel'), depositAddressRecord.address);
    } catch (e: any) {
      showMessage(t('assets.depositFailedTitle'), e?.message || t('assets.depositCopyFailedBody'));
    }
  }, [depositAddressRecord?.address, showMessage, t]);

  useEffect(() => {
    if (!showDepositModal || !user?.uid) return;
    setShowDepositAssetMenu(false);
    void loadDepositOptions();
    void loadDepositAddress(depositAssetCode, depositNetwork);
    void loadDepositHistory(depositAssetCode);
  }, [depositAssetCode, depositNetwork, loadDepositAddress, loadDepositHistory, loadDepositOptions, showDepositModal, user?.uid]);

  const handleTransfer = useCallback(async () => {
    const amount = Number.parseFloat(transferAmount || '0');
    if (!Number.isFinite(amount) || amount <= 0) {
      showMessage(t('assets.transferFailedTitle'), t('assets.transferInvalidAmount'));
      return;
    }
    if (amount > transferSourceAvailable) {
      showMessage(t('assets.transferFailedTitle'), t('assets.transferExceedsAvailable'));
      return;
    }
    setTransferring(true);
    try {
      await transferAssets({
        from_account: transferDirection === 'spot_to_futures' ? 'spot' : 'futures',
        to_account: transferDirection === 'spot_to_futures' ? 'futures' : 'spot',
        amount,
      });
      setTransferAmount('');
      setShowTransferModal(false);
      await fetchOverview({ silent: true });
      await loadSpotHoldings();
      showMessage(t('assets.transferSuccessTitle'), t('assets.transferSuccessBody', { amount: formatUsd(amount) }));
    } catch (e: any) {
      showMessage(
        t('assets.transferFailedTitle'),
        e?.response?.data?.error || e?.message || t('assets.transferFailedBody'),
      );
    } finally {
      setTransferring(false);
    }
  }, [fetchOverview, showMessage, t, transferAmount, transferDirection, transferSourceAvailable]);

  const handleWithdraw = useCallback(async () => {
    const amount = Number.parseFloat(withdrawAmount || '0');
    if (!Number.isFinite(amount) || amount <= 0) {
      showMessage(t('assets.withdrawFailedTitle'), t('assets.withdrawInvalidAmount'));
      return;
    }
    if (!withdrawAddress.trim()) {
      showMessage(t('assets.withdrawFailedTitle'), t('assets.withdrawInvalidAddress'));
      return;
    }
    if (!withdrawNetwork.trim()) {
      showMessage(t('assets.withdrawFailedTitle'), t('assets.withdrawInvalidNetwork'));
      return;
    }
    if (amount > spotAvailable) {
      showMessage(t('assets.withdrawFailedTitle'), t('assets.withdrawExceedsAvailable'));
      return;
    }
    setWithdrawing(true);
    try {
      await withdrawFromSpotAccount({
        amount,
        address: withdrawAddress.trim(),
        network: withdrawNetwork.trim(),
      });
      setWithdrawAmount('');
      setWithdrawAddress('');
      setWithdrawNetwork('TRC20');
      setShowWithdrawNetworkMenu(false);
      setShowWithdrawModal(false);
      await fetchOverview({ silent: true });
      await loadSpotHoldings();
      showMessage(t('assets.withdrawSuccessTitle'), t('assets.withdrawSuccessBody', { amount: formatUsd(amount) }));
    } catch (e: any) {
      showMessage(
        t('assets.withdrawFailedTitle'),
        e?.response?.data?.error || e?.message || t('assets.withdrawFailedBody'),
      );
    } finally {
      setWithdrawing(false);
    }
  }, [fetchOverview, showMessage, t, withdrawAddress, withdrawAmount, withdrawNetwork]);

  const handleRefreshAll = useCallback(async () => {
    await fetchOverview({ silent: true });
    await fetchCalendar();
    await loadSpotHoldings();
    await loadCopyAccountOverviewAndPools();
    if (selectedCopyTraderUid) {
      await loadCopyAccountActivity(selectedCopyTraderUid);
    }
  }, [fetchCalendar, fetchOverview, loadCopyAccountActivity, loadCopyAccountOverviewAndPools, loadSpotHoldings, selectedCopyTraderUid]);

  const handleChangeRange = useCallback(async (nextRange: AssetRangeKey) => {
    setRange(nextRange);
    await fetchOverview({ silent: true }, nextRange);
  }, [fetchOverview, setRange]);

  const handleCalendarShift = useCallback(async (delta: number) => {
    const base = new Date(calendarYear, calendarMonth - 1, 1);
    base.setMonth(base.getMonth() + delta);
    await fetchCalendar(base.getFullYear(), base.getMonth() + 1);
  }, [calendarMonth, calendarYear, fetchCalendar]);

  useEffect(() => {
    if (!calendar?.days?.length) {
      setSelectedCalendarDate(null);
      return;
    }
    setSelectedCalendarDate((current) => {
      if (current && calendar.days.some((item) => item.date === current)) {
        return current;
      }
      return (
        calendar.days.find((item) => item.is_today)?.date ||
        [...calendar.days].reverse().find((item) => item.has_data)?.date ||
        calendar.days[calendar.days.length - 1]?.date ||
        null
      );
    });
  }, [calendar]);

  if (!user) {
    return (
      <View style={styles.centerState}>
        <AppIcon name="wallet" size={34} color={Colors.primary} />
        <Text style={styles.centerStateTitle}>{t('assets.loginRequiredTitle')}</Text>
        <Text style={styles.centerStateBody}>{t('assets.loginRequiredBody')}</Text>
      </View>
    );
  }

  if (loading && !displayOverview) {
    return (
      <View style={styles.centerState}>
        <ActivityIndicator color={Colors.primary} />
        <Text style={styles.centerStateBody}>{t('assets.loading')}</Text>
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void handleRefreshAll()} tintColor={Colors.primary} />}
    >
      <View style={styles.headerRow}>
        <View style={styles.headerContent}>
          <Text style={styles.pageTitle}>{t('assets.title')}</Text>
          <Text style={styles.pageSubtitle}>{t('assets.subtitle')}</Text>
        </View>
        <TouchableOpacity style={styles.refreshBtn} activeOpacity={0.8} onPress={() => void handleRefreshAll()}>
          <AppIcon name="clock" size={16} color={Colors.primary} />
          <Text style={styles.refreshBtnText}>{t('assets.refresh')}</Text>
        </TouchableOpacity>
      </View>

      {error ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorTitle}>{t('assets.loadFailedTitle')}</Text>
          <Text style={styles.errorBody}>{error}</Text>
        </View>
      ) : null}

      <View style={[styles.heroCard, isDesktop && styles.heroCardDesktop]}>
        <View style={styles.heroLayout}>
          <View style={styles.heroSummary}>
            <View style={styles.heroSummaryTop}>
              <View style={styles.heroValueBlock}>
                <Text style={styles.heroLabel}>{t('assets.totalEquity')}</Text>
                <Text style={styles.heroValue}>{formatUsd(displayOverview?.total_equity)} USDT</Text>
                <Text style={styles.heroApproxValue}>≈ ${formatUsd(displayOverview?.total_equity)}</Text>
              </View>
              {workspaceView !== 'copy' ? (
                <TouchableOpacity
                  style={styles.heroCalendarBtn}
                  activeOpacity={0.85}
                  onPress={() => setShowPnlCalendarModal(true)}
                >
                  <AppIcon name="calendar" size={19} color={Colors.primary} />
                </TouchableOpacity>
              ) : (
                <View style={styles.heroCalendarSpacer} />
              )}
            </View>
            <View style={styles.heroPnlRow}>
              <Text style={styles.heroPnlLabel}>{t('assets.todayPnl')}</Text>
              <Text style={[styles.heroPnlValue, { color: pnlPositive ? Colors.up : Colors.down }]}>
                {pnlPositive ? '+' : ''}{formatUsd(displayOverview?.today_pnl)} USDT
              </Text>
              <Text style={[styles.heroPnlRate, { color: pnlPositive ? Colors.up : Colors.down }]}>
                ({((displayOverview?.today_pnl_rate || 0) * 100).toFixed(2)}%)
              </Text>
            </View>
            <View style={styles.realtimeRow}>
              <View style={[styles.realtimeBadge, { borderColor: realtimeStatusColor + '55', backgroundColor: realtimeStatus === 'live' ? Colors.up + '14' : realtimeStatus === 'syncing' ? Colors.primaryDim : Colors.surfaceAlt }]}>
                <View style={[styles.realtimeDot, { backgroundColor: realtimeStatusColor }]} />
                <Text style={[styles.realtimeBadgeText, { color: realtimeStatusColor }]}>{realtimeStatusLabel}</Text>
              </View>
              <Text style={styles.realtimeMeta}>
                {t('assets.realtimeTrackedPositions', { count: positions.length })} · {t('assets.realtimeLastUpdate', { time: formatRealtimeClock(lastRealtimeAt) })}
              </Text>
              <TouchableOpacity style={styles.realtimeDriversBtn} activeOpacity={0.85} onPress={() => setShowRealtimeDriversModal(true)}>
                <Text style={styles.realtimeDriversBtnText}>{t('assets.realtimeDriversAction')}</Text>
              </TouchableOpacity>
            </View>
          </View>
          <View style={styles.heroActions}>
            {actionCards.map((item) => (
              <TouchableOpacity
                key={item.key}
                style={[styles.heroActionPill, item.primary && styles.heroActionPillPrimary]}
                activeOpacity={0.88}
                onPress={item.onPress}
              >
                <Text style={[styles.heroActionPillText, item.primary && styles.heroActionPillTextPrimary]}>
                  {item.title}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>
      </View>

      <View style={styles.panelCard}>
        <View style={styles.assetWorkbenchHead}>
          <View style={styles.assetWorkbenchTabs}>
            {([
              { key: 'assets', label: t('assets.spotAssetsTitle') },
              { key: 'accounts', label: t('assets.accountsTitle') },
              { key: 'copy', label: t('assets.copyAccountTitle') },
            ] as const).map((tab) => (
              <TouchableOpacity
                key={tab.key}
                activeOpacity={0.85}
                style={[
                  styles.assetWorkbenchTab,
                  workspaceView === tab.key && styles.assetWorkbenchTabActive,
                ]}
                onPress={() => setWorkspaceView(tab.key)}
              >
                <Text
                  style={[
                    styles.assetWorkbenchTabText,
                    workspaceView === tab.key && styles.assetWorkbenchTabTextActive,
                  ]}
                >
                  {tab.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
          {workspaceView === 'assets' ? (
            <View style={styles.assetSearchWrap}>
              <AppIcon name="search" size={16} color={Colors.textMuted} />
              <TextInput
                value={assetSearch}
                onChangeText={setAssetSearch}
                placeholder={t('assets.assetSearchPlaceholder')}
                placeholderTextColor={Colors.textMuted}
                style={styles.assetSearchInput}
              />
            </View>
          ) : null}
        </View>

        {workspaceView === 'assets' ? (
        <View style={[styles.assetControlsCard, isDesktop && styles.assetControlsCardDesktop]}>
          <View style={styles.assetControlsPrimaryRow}>
            <View style={styles.assetCategoryRow}>
              {(['all', 'crypto', 'stock'] as const).map((category) => (
                <TouchableOpacity
                  key={category}
                  activeOpacity={0.85}
                  style={[
                    styles.assetCategoryChip,
                    assetCategory === category && styles.assetCategoryChipActive,
                  ]}
                  onPress={() => setAssetCategory(category)}
                >
                  <Text
                    style={[
                      styles.assetCategoryChipText,
                      assetCategory === category && styles.assetCategoryChipTextActive,
                    ]}
                  >
                    {category === 'all'
                      ? t('assets.assetCategoryAll')
                      : category === 'crypto'
                      ? t('assets.assetCategoryCrypto')
                      : t('assets.assetCategoryStock')}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
          <View style={styles.assetControlsSecondaryRow}>
            <View style={styles.assetToggleRow}>
              <TouchableOpacity
                activeOpacity={0.85}
                style={[styles.assetToggleChip, ownedOnly && styles.assetToggleChipActive]}
                onPress={() => setOwnedOnly((current) => !current)}
              >
                <Text style={[styles.assetToggleChipText, ownedOnly && styles.assetToggleChipTextActive]}>
                  {t('assets.ownedOnlyToggle')}
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                activeOpacity={0.85}
                style={[styles.assetToggleChip, hideDust && styles.assetToggleChipActive]}
                onPress={() => setHideDust((current) => !current)}
              >
                <Text style={[styles.assetToggleChipText, hideDust && styles.assetToggleChipTextActive]}>
                  {t('assets.hideDustToggle')}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
        ) : null}

        {workspaceView === 'assets' && spotHoldingsLoading && !spotHoldings.length ? (
          <View style={styles.assetEmptyState}>
            <ActivityIndicator color={Colors.primary} />
            <Text style={styles.assetEmptyBody}>{t('assets.loading')}</Text>
          </View>
        ) : workspaceView === 'assets' && spotHoldings.length ? (
          isDesktop ? (
            <View style={styles.assetTable}>
              <View style={styles.assetTableHead}>
                <Text style={[styles.assetTableHeadCell, styles.assetTableAssetCell]}>{t('assets.assetTableAsset')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTableAmountCell]}>{t('assets.assetTotalLabel')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTablePriceCell]}>{t('assets.assetTablePriceCost')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTablePnlCell]}>{t('assets.assetTablePnl')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTableAvailableCell]}>{t('assets.assetTableAvailableFrozen')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTableActionCell]}>{t('assets.assetTableAction')}</Text>
              </View>
              {spotHoldings.map((item) => {
                const depositNetworksForAsset =
                  assetOptionSource.find((option) => option.asset_code === item.asset_code)?.networks || [];
                const unrealizedPositive = (item.unrealized_pnl || 0) >= 0;
                const realizedPositive = (item.lifetime_realized_pnl || 0) >= 0;
                const isStockAsset = item.category === 'stock';
                const canDepositAsset = !isStockAsset && depositNetworksForAsset.length > 0;
                const canTransferAsset = !isStockAsset && item.can_transfer;
                const canWithdrawAsset = !isStockAsset && item.can_withdraw;
                return (
                  <View key={item.key} style={styles.assetTableRow}>
                    <View style={[styles.assetTableCell, styles.assetTableAssetCell]}>
                      <View style={styles.assetIdentity}>
                        <View style={styles.assetIconWrap}>
                          <AssetGlyph item={item} />
                        </View>
                        <View style={styles.assetIdentityBody}>
                          <View style={styles.assetCodeRow}>
                            <Text style={styles.assetCode}>{item.asset_code}</Text>
                            <View
                              style={[
                                styles.assetCategoryBadge,
                                isStockAsset && styles.assetCategoryBadgeStock,
                              ]}
                            >
                              <Text
                                style={[
                                  styles.assetCategoryBadgeText,
                                  isStockAsset && styles.assetCategoryBadgeTextStock,
                                ]}
                              >
                                {isStockAsset ? t('assets.assetCategoryStock') : t('assets.assetCategoryCrypto')}
                              </Text>
                            </View>
                            {item.is_dust ? (
                              <View style={styles.assetDustBadge}>
                                <Text style={styles.assetDustBadgeText}>{t('assets.dustBadge')}</Text>
                              </View>
                            ) : null}
                          </View>
                          <Text style={styles.assetName}>{item.asset_name}</Text>
                        </View>
                      </View>
                    </View>
                    <View style={[styles.assetTableCell, styles.assetTableAmountCell]}>
                      <Text style={styles.assetTableValue}>{formatAssetQuantity(item.balance_total)}</Text>
                      <Text style={styles.assetTableSubValue}>≈ {formatUsd(item.valuation)} USDT</Text>
                    </View>
                    <View style={[styles.assetTableCell, styles.assetTablePriceCell]}>
                      <Text style={styles.assetTableValue}>${formatUsd(item.price || 0)}</Text>
                      <Text style={styles.assetTableSubValue}>
                        {t('assets.avgCost')}: {item.avg_cost > 0 ? `$${formatUsd(item.avg_cost)}` : t('assets.noCostBasis')}
                        {item.cost_estimated ? ` · ${t('assets.costEstimatedShort')}` : ''}
                      </Text>
                    </View>
                    <View style={[styles.assetTableCell, styles.assetTablePnlCell]}>
                      <Text style={[styles.assetTableValue, { color: unrealizedPositive ? Colors.up : Colors.down }]}>
                        {formatSignedUsd(item.unrealized_pnl)} USDT
                      </Text>
                      <Text style={[styles.assetTableSubValue, { color: realizedPositive ? Colors.up : Colors.down }]}>
                        {t('assets.lifetimeRealizedPnlShort')}: {formatSignedUsd(item.lifetime_realized_pnl)} USDT
                      </Text>
                    </View>
                    <View style={[styles.assetTableCell, styles.assetTableAvailableCell]}>
                      <Text style={styles.assetTableValue}>{formatAssetQuantity(item.balance_available)}</Text>
                      <Text style={styles.assetTableSubValue}>
                        {t('assets.frozen')}: {formatAssetQuantity(item.balance_frozen)}
                      </Text>
                    </View>
                    <View style={[styles.assetTableCell, styles.assetTableActionCell]}>
                      {canDepositAsset || canTransferAsset || canWithdrawAsset ? (
                        <View style={styles.assetActionRow}>
                          {canDepositAsset ? (
                            <TouchableOpacity
                              activeOpacity={0.85}
                              style={[styles.assetActionBtn, styles.assetActionBtnPrimary]}
                              onPress={() => handleOpenAssetDeposit(item.asset_code, depositNetworksForAsset)}
                            >
                              <Text style={styles.assetActionBtnPrimaryText}>{t('assets.depositAction')}</Text>
                            </TouchableOpacity>
                          ) : null}
                          {canTransferAsset ? (
                            <TouchableOpacity
                              activeOpacity={0.85}
                              style={styles.assetActionBtn}
                              onPress={() => setShowTransferModal(true)}
                            >
                              <Text style={styles.assetActionBtnText}>{t('assets.transferAction')}</Text>
                            </TouchableOpacity>
                          ) : null}
                          {canWithdrawAsset ? (
                            <TouchableOpacity
                              activeOpacity={0.85}
                              style={styles.assetActionBtn}
                              onPress={() => setShowWithdrawModal(true)}
                            >
                              <Text style={styles.assetActionBtnText}>{t('assets.withdrawAction')}</Text>
                            </TouchableOpacity>
                          ) : null}
                        </View>
                      ) : (
                        <Text style={styles.assetActionHint}>{t('assets.stockActionHint')}</Text>
                      )}
                    </View>
                  </View>
                );
              })}
            </View>
          ) : (
            <View style={styles.assetList}>
              {spotHoldings.map((item) => {
                const depositNetworksForAsset =
                  assetOptionSource.find((option) => option.asset_code === item.asset_code)?.networks || [];
                const unrealizedPositive = (item.unrealized_pnl || 0) >= 0;
                const realizedPositive = (item.lifetime_realized_pnl || 0) >= 0;
                const isStockAsset = item.category === 'stock';
                const canDepositAsset = !isStockAsset && depositNetworksForAsset.length > 0;
                const canTransferAsset = !isStockAsset && item.can_transfer;
                const canWithdrawAsset = !isStockAsset && item.can_withdraw;
                return (
                  <View key={item.key} style={styles.assetRow}>
                    <View style={styles.assetRowHead}>
                      <View style={styles.assetIdentity}>
                        <View style={styles.assetIconWrap}>
                          <AssetGlyph item={item} />
                        </View>
                        <View style={styles.assetIdentityBody}>
                          <View style={styles.assetCodeRow}>
                            <Text style={styles.assetCode}>{item.asset_code}</Text>
                            <View
                              style={[
                                styles.assetCategoryBadge,
                                isStockAsset && styles.assetCategoryBadgeStock,
                              ]}
                            >
                              <Text
                                style={[
                                  styles.assetCategoryBadgeText,
                                  isStockAsset && styles.assetCategoryBadgeTextStock,
                                ]}
                              >
                                {isStockAsset ? t('assets.assetCategoryStock') : t('assets.assetCategoryCrypto')}
                              </Text>
                            </View>
                            {item.is_dust ? (
                              <View style={styles.assetDustBadge}>
                                <Text style={styles.assetDustBadgeText}>{t('assets.dustBadge')}</Text>
                              </View>
                            ) : null}
                          </View>
                          <Text style={styles.assetName}>{item.asset_name}</Text>
                        </View>
                      </View>
                      <View style={styles.assetValuationBlock}>
                        <Text style={styles.assetValuation}>{formatUsd(item.valuation)} USDT</Text>
                        <Text style={styles.assetValuationSub}>
                          {item.daily_change_rate ? formatPercent(item.daily_change_rate) : t('assets.assetNoDailyChange')}
                        </Text>
                      </View>
                    </View>

                    <View style={styles.assetMetricsRow}>
                      <View style={styles.assetMetricCard}>
                        <Text style={styles.assetMetricLabel}>{t('assets.assetTotalLabel')}</Text>
                        <Text style={styles.assetMetricValue}>{formatAssetQuantity(item.balance_total)}</Text>
                      </View>
                      <View style={styles.assetMetricCard}>
                        <Text style={styles.assetMetricLabel}>{t('assets.avgCost')}</Text>
                        <Text style={styles.assetMetricValue}>
                          {item.avg_cost > 0 ? `$${formatUsd(item.avg_cost)}` : t('assets.noCostBasis')}
                        </Text>
                      </View>
                      <View style={styles.assetMetricCard}>
                        <Text style={styles.assetMetricLabel}>{t('assets.unrealizedPnl')}</Text>
                        <Text style={[styles.assetMetricValue, { color: unrealizedPositive ? Colors.up : Colors.down }]}>
                          {formatSignedUsd(item.unrealized_pnl)} USDT
                        </Text>
                      </View>
                    </View>

                    <View style={styles.assetMetricsRow}>
                      <View style={styles.assetMetricCard}>
                        <Text style={styles.assetMetricLabel}>{t('assets.lifetimeRealizedPnlShort')}</Text>
                        <Text style={[styles.assetMetricValue, { color: realizedPositive ? Colors.up : Colors.down }]}>
                          {formatSignedUsd(item.lifetime_realized_pnl)} USDT
                        </Text>
                      </View>
                      <View style={styles.assetMetricCard}>
                        <Text style={styles.assetMetricLabel}>{t('assets.available')}</Text>
                        <Text style={styles.assetMetricValue}>{formatAssetQuantity(item.balance_available)}</Text>
                      </View>
                      <View style={styles.assetMetricCard}>
                        <Text style={styles.assetMetricLabel}>{t('assets.frozen')}</Text>
                        <Text style={styles.assetMetricValue}>{formatAssetQuantity(item.balance_frozen)}</Text>
                      </View>
                    </View>

                    <View style={styles.assetActionRow}>
                      {canDepositAsset ? (
                        <TouchableOpacity
                          activeOpacity={0.85}
                          style={[styles.assetActionBtn, styles.assetActionBtnPrimary]}
                          onPress={() => handleOpenAssetDeposit(item.asset_code, depositNetworksForAsset)}
                        >
                          <Text style={styles.assetActionBtnPrimaryText}>{t('assets.depositAction')}</Text>
                        </TouchableOpacity>
                      ) : null}
                      {canTransferAsset ? (
                        <TouchableOpacity
                          activeOpacity={0.85}
                          style={styles.assetActionBtn}
                          onPress={() => setShowTransferModal(true)}
                        >
                          <Text style={styles.assetActionBtnText}>{t('assets.transferAction')}</Text>
                        </TouchableOpacity>
                      ) : null}
                      {canWithdrawAsset ? (
                        <TouchableOpacity
                          activeOpacity={0.85}
                          style={styles.assetActionBtn}
                          onPress={() => setShowWithdrawModal(true)}
                        >
                          <Text style={styles.assetActionBtnText}>{t('assets.withdrawAction')}</Text>
                        </TouchableOpacity>
                      ) : null}
                      {!canDepositAsset && !canTransferAsset && !canWithdrawAsset ? (
                        <Text style={styles.assetActionHint}>{t('assets.stockActionHint')}</Text>
                      ) : null}
                    </View>
                  </View>
                );
              })}
            </View>
          )
        ) : workspaceView === 'accounts' ? (
          isDesktop ? (
            <View style={styles.assetTable}>
              <View style={styles.assetTableHead}>
                <Text style={[styles.assetTableHeadCell, styles.assetTableAssetCell]}>{t('assets.accountsTitle')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTableAmountCell]}>{t('assets.equity')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTablePriceCell]}>{t('assets.available')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTableAvailableCell]}>{t('assets.frozen')}</Text>
                <Text style={[styles.assetTableHeadCell, styles.assetTableActionCell]}>{t('assets.accountDetailTitle')}</Text>
              </View>
              {accountCards.map((account) => (
                <TouchableOpacity
                  key={account.account_type}
                  activeOpacity={0.88}
                  onPress={() => setSelectedAccountType(account.account_type)}
                  style={[styles.assetTableRow, selectedAccount?.account_type === account.account_type && styles.accountItemActive]}
                >
                  <View style={[styles.assetTableCell, styles.assetTableAssetCell]}>
                    <View style={styles.assetIdentity}>
                      <View style={styles.assetIconWrap}>
                        <AppIcon name={account.account_type === 'futures' ? 'futures' : 'wallet'} size={16} color={account.account_type === 'futures' ? Colors.primary : Colors.textSecondary} />
                      </View>
                      <View style={styles.assetIdentityBody}>
                        <Text style={styles.assetCode}>{accountDisplayLabel(account.account_type, account.display_name, t)}</Text>
                        <Text style={styles.assetName}>{accountTypeCodeLabel(account.account_type)}</Text>
                      </View>
                    </View>
                  </View>
                  <View style={[styles.assetTableCell, styles.assetTableAmountCell]}>
                    <Text style={styles.assetTableValue}>{formatUsd(account.equity)} USDT</Text>
                  </View>
                  <View style={[styles.assetTableCell, styles.assetTablePriceCell]}>
                    <Text style={styles.assetTableValue}>{formatUsd(account.available)} USDT</Text>
                  </View>
                  <View style={[styles.assetTableCell, styles.assetTableAvailableCell]}>
                    <Text style={styles.assetTableValue}>{formatUsd(account.frozen)} USDT</Text>
                  </View>
                  <View style={[styles.assetTableCell, styles.assetTableActionCell]}>
                    <Text style={styles.assetTableSubValue}>
                      {account.is_virtual ? t('assets.virtualTag') : t('assets.viewAllTransactions')}
                    </Text>
                  </View>
                </TouchableOpacity>
              ))}
            </View>
          ) : (
            <View style={styles.accountList}>
              {accountCards.map((account) => (
                <TouchableOpacity
                  key={account.account_type}
                  activeOpacity={0.88}
                  onPress={() => setSelectedAccountType(account.account_type)}
                  style={[
                    styles.accountItem,
                    selectedAccount?.account_type === account.account_type && styles.accountItemActive,
                  ]}
                >
                  <View style={styles.accountTopRow}>
                    <View style={styles.accountNameRow}>
                      <View style={styles.accountIconWrap}>
                        <AppIcon name={account.account_type === 'futures' ? 'futures' : 'wallet'} size={16} color={account.account_type === 'futures' ? Colors.primary : Colors.textSecondary} />
                      </View>
                      <View>
                        <Text style={styles.accountName}>{accountDisplayLabel(account.account_type, account.display_name, t)}</Text>
                        <Text style={styles.accountType}>{accountTypeCodeLabel(account.account_type)}</Text>
                      </View>
                    </View>
                    {account.is_virtual ? (
                      <View style={styles.virtualBadge}>
                        <Text style={styles.virtualBadgeText}>{t('assets.virtualTag')}</Text>
                      </View>
                    ) : null}
                  </View>

                  <View style={styles.accountMetricsRow}>
                    <View style={styles.metricBlock}>
                      <Text style={styles.metricLabel}>{t('assets.equity')}</Text>
                      <Text style={styles.metricValue}>{formatUsd(account.equity)} USDT</Text>
                    </View>
                    <View style={styles.metricBlock}>
                      <Text style={styles.metricLabel}>{t('assets.available')}</Text>
                      <Text style={styles.metricValue}>{formatUsd(account.available)} USDT</Text>
                    </View>
                    <View style={styles.metricBlock}>
                      <Text style={styles.metricLabel}>{t('assets.frozen')}</Text>
                      <Text style={styles.metricValue}>{formatUsd(account.frozen)} USDT</Text>
                    </View>
                  </View>
                </TouchableOpacity>
              ))}
            </View>
          )
        ) : workspaceView === 'copy' ? (
          copyAccountLoading && !copyAccountOverview && !copyAccountPools.length ? (
            <View style={styles.assetEmptyState}>
              <ActivityIndicator color={Colors.primary} />
              <Text style={styles.assetEmptyBody}>{t('assets.loading')}</Text>
            </View>
          ) : copyAccountPools.length ? (
            <View style={styles.copyWorkspace}>
              <View style={styles.copyOverviewGrid}>
                <View style={styles.copyOverviewCard}>
                  <Text style={styles.metricLabel}>{t('assets.copyOverviewTotalEquity')}</Text>
                  <Text style={styles.copyOverviewValue}>{formatUsd(copyAccountOverview?.total_equity)} USDT</Text>
                  <Text style={styles.copyOverviewSub}>{t('assets.copyOverviewCurrentPools', { count: copyAccountOverview?.current_pool_count || 0 })}</Text>
                </View>
                <View style={styles.copyOverviewCard}>
                  <Text style={styles.metricLabel}>{t('assets.copyOverviewCurrentNet')}</Text>
                  <Text style={[styles.copyOverviewValue, { color: copyCurrentNetPnl >= 0 ? Colors.up : Colors.down }]}>
                    {copyCurrentNetPnl >= 0 ? '+' : ''}{formatUsd(copyCurrentNetPnl)} USDT
                  </Text>
                  <Text style={styles.copyOverviewSub}>
                    {t('assets.copyOverviewCurrentNetBreakdown', {
                      equity: formatUsd(copyAccountOverview?.total_equity),
                      allocated: formatUsd(copyAccountOverview?.total_allocated),
                    })}
                  </Text>
                </View>
                <View style={styles.copyOverviewCard}>
                  <Text style={styles.metricLabel}>{t('assets.copyOverviewUnrealizedPnl')}</Text>
                  <Text
                    style={[
                      styles.copyOverviewValue,
                      {
                        color: liveCopyUnrealizedPnlAll >= 0 ? Colors.up : Colors.down,
                      },
                    ]}
                  >
                    {liveCopyUnrealizedPnlAll >= 0 ? '+' : ''}
                    {formatUsd(liveCopyUnrealizedPnlAll)} USDT
                  </Text>
                  <Text style={styles.copyOverviewSub}>
                    {t('assets.copyOverviewUnrealizedPnlHint')}
                  </Text>
                </View>
                <View style={styles.copyOverviewCard}>
                  <Text style={styles.metricLabel}>{t('assets.copyOverviewTodayNet')}</Text>
                  <Text style={[styles.copyOverviewValue, { color: (copyAccountOverview?.today_net_pnl || 0) >= 0 ? Colors.up : Colors.down }]}>
                    {(copyAccountOverview?.today_net_pnl || 0) >= 0 ? '+' : ''}{formatUsd(copyAccountOverview?.today_net_pnl)} USDT
                  </Text>
                  <Text style={styles.copyOverviewSub}>
                    {t('assets.copyOverviewTodayBreakdown', {
                      realized: formatUsd(copyAccountOverview?.today_realized_pnl),
                      share: formatUsd(copyAccountOverview?.today_profit_share),
                    })}
                  </Text>
                </View>
                <View style={styles.copyOverviewCard}>
                  <Text style={styles.metricLabel}>{t('assets.copyOverviewLifetimeRealizedNet')}</Text>
                  <Text style={[styles.copyOverviewValue, { color: (copyAccountOverview?.lifetime_net_pnl || 0) >= 0 ? Colors.up : Colors.down }]}> 
                    {(copyAccountOverview?.lifetime_net_pnl || 0) >= 0 ? '+' : ''}{formatUsd(copyAccountOverview?.lifetime_net_pnl)} USDT
                  </Text>
                  <Text style={styles.copyOverviewSub}>
                    {t('assets.copyOverviewLifetimeBreakdown', {
                      realized: formatUsd(copyAccountOverview?.lifetime_realized_pnl),
                      share: formatUsd(copyAccountOverview?.lifetime_profit_share),
                    })}
                  </Text>
                </View>
              </View>

              <View style={[styles.copyWorkspaceBody, isDesktop && styles.copyWorkspaceBodyDesktop]}>
                <View style={styles.copyPoolsPanel}>
                  <View style={styles.sectionHead}>
                    <Text style={styles.sectionTitle}>{t('assets.copyPoolsTitle')}</Text>
                    <Text style={styles.sectionHint}>{t('assets.copyPoolsHint')}</Text>
                  </View>
                  <View style={styles.copyItems}>
                    {copyAccountPools.map((item) => {
                      const active = selectedCopyPool?.trader_uid === item.trader_uid;
                      const positive = item.current_net_pnl >= 0;
                      return (
                        <TouchableOpacity
                          key={item.copy_trading_id}
                          activeOpacity={0.88}
                          onPress={() => setSelectedCopyTraderUid(item.trader_uid)}
                          style={[styles.copyItem, active && styles.copyItemActive]}
                        >
                          <View style={styles.copyItemTop}>
                            <Text style={styles.copyTraderName}>{item.trader_name}</Text>
                            <Text style={styles.copyTraderStatus}>{copyStatusLabel(item.status, t)}</Text>
                          </View>
                          <Text style={styles.copyTraderMeta}>
                            {t('assets.copyTraderAllocated', { amount: formatUsd(item.allocated_capital) })}
                          </Text>
                          <Text style={styles.copyTraderMeta}>
                            {t('assets.copyTraderEquity', {
                              amount: formatUsd(item.current_equity),
                            })}
                          </Text>
                          <View style={styles.copyPoolBottomRow}>
                            <Text style={[styles.copyPoolPnl, { color: positive ? Colors.up : Colors.down }]}>
                              {(item.current_net_pnl || 0) >= 0 ? '+' : ''}{formatUsd(item.current_net_pnl)} USDT
                            </Text>
                            <Text style={styles.copyPoolReturn}>{formatPercent(item.current_return_rate || 0)}</Text>
                          </View>
                        </TouchableOpacity>
                      );
                    })}
                  </View>
                </View>

                <View style={styles.copyActivityPanel}>
                  <View style={styles.sectionHead}>
                    <View style={styles.sectionTitleRow}>
                      <Text style={styles.sectionTitle}>{selectedCopyPool?.trader_name || t('assets.copyActivityTitle')}</Text>
                      <View style={styles.segmentedRow}>
                        {([
                          { key: 'positions', label: t('assets.copyOpenPositionsTitle') },
                          { key: 'history', label: t('assets.copyHistoryTitle') },
                        ] as const).map((tab) => (
                          <TouchableOpacity
                            key={tab.key}
                            activeOpacity={0.85}
                            style={[styles.segmentBtn, copyActivityTab === tab.key && styles.segmentBtnActive]}
                            onPress={() => setCopyActivityTab(tab.key)}
                          >
                            <Text style={[styles.segmentBtnText, copyActivityTab === tab.key && styles.segmentBtnTextActive]}>
                              {tab.label}
                            </Text>
                          </TouchableOpacity>
                        ))}
                      </View>
                    </View>
                    <Text style={styles.sectionHint}>
                      {selectedCopyPool
                        ? t('assets.copyActivityHint', { name: selectedCopyPool.trader_name })
                        : t('assets.copyPoolsHint')}
                    </Text>
                  </View>

                  {selectedCopyPool ? (
                    <>
                      {/* 注：原先这里还有一行重复展示"当前权益 / 当前总收益"的 summary line，
                          左侧池子卡片里已经显示过，故去除避免冗余；"累计已实现净收益"并入下方 meta 网格。 */}
                      <View style={styles.copyPoolMetaGrid}>
                        <View style={styles.copyPoolMetaCard}>
                          <Text style={styles.metricLabel}>{t('assets.copyAvailable')}</Text>
                          <Text style={styles.copyPoolMetaValue}>{formatUsd(selectedCopyPool.available_capital)} USDT</Text>
                        </View>
                        <View style={styles.copyPoolMetaCard}>
                          <Text style={styles.metricLabel}>{t('assets.copyFrozen')}</Text>
                          <Text style={styles.copyPoolMetaValue}>{formatUsd(selectedCopyPool.frozen_capital)} USDT</Text>
                        </View>
                        <View style={styles.copyPoolMetaCard}>
                          <Text style={styles.metricLabel}>{t('assets.detailUtilization')}</Text>
                          <Text style={styles.copyPoolMetaValue}>{formatPercent(copyPoolUtilization)}</Text>
                        </View>
                        <View style={styles.copyPoolMetaCard}>
                          <Text style={styles.metricLabel}>{t('assets.copyOverviewLifetimeRealizedNet')}</Text>
                          <Text
                            style={[
                              styles.copyPoolMetaValue,
                              {
                                color:
                                  (selectedCopyPool.lifetime_net_pnl || 0) >= 0 ? Colors.up : Colors.down,
                              },
                            ]}
                          >
                            {(selectedCopyPool.lifetime_net_pnl || 0) >= 0 ? '+' : ''}
                            {formatUsd(selectedCopyPool.lifetime_net_pnl)} USDT
                          </Text>
                        </View>
                      </View>

                      {copyActivityTab === 'positions' ? (
                        liveCopyPositions.length ? (
                          <View style={styles.copyActivityList}>
                            {liveCopyPositions.map((position) => {
                              const positive = (position.unrealized_pnl || 0) >= 0;
                              return (
                                <View key={position.position_id} style={styles.copyActivityItem}>
                                  <View style={styles.copyActivityItemHead}>
                                    <View>
                                      <Text style={styles.copyActivitySymbol}>{toDisplaySymbol(position.symbol)}</Text>
                                      <Text style={styles.copyActivityMeta}>
                                        {position.side.toUpperCase()} · {formatAssetQuantity(position.qty)} · {t('assets.copyOverviewOpenedAt', { time: formatTransactionTime(position.opened_at) })}
                                      </Text>
                                    </View>
                                    <Text style={[styles.copyActivityPnl, { color: positive ? Colors.up : Colors.down }]}>
                                      {positive ? '+' : ''}{formatUsd(position.unrealized_pnl)} USDT
                                    </Text>
                                  </View>
                                  <View style={styles.copyActivityMetrics}>
                                    <Text style={styles.copyActivityMetric}>{t('assets.realtimeDriverEntry')}: {formatUsd(position.entry_price)}</Text>
                                    <Text style={styles.copyActivityMetric}>{t('assets.realtimeDriverCurrent')}: {formatUsd(position.current_price)}</Text>
                                    <Text style={styles.copyActivityMetric}>{t('assets.realtimeDriverMargin')}: {formatUsd(position.margin_amount)}</Text>
                                    <Text style={styles.copyActivityMetric}>ROE: {formatPercent((position.roe || 0) / 100)}</Text>
                                  </View>
                                </View>
                              );
                            })}
                          </View>
                        ) : (
                          <View style={styles.assetEmptyState}>
                            <Text style={styles.assetEmptyTitle}>{t('assets.copyOpenPositionsEmptyTitle')}</Text>
                            <Text style={styles.assetEmptyBody}>{t('assets.copyOpenPositionsEmptyBody')}</Text>
                          </View>
                        )
                      ) : copyAccountHistory.length ? (
                        <View style={styles.copyActivityList}>
                          {copyAccountHistory.map((item) => {
                            const positive = (item.net_pnl || 0) >= 0;
                            return (
                              <View key={item.position_id} style={styles.copyActivityItem}>
                                <View style={styles.copyActivityItemHead}>
                                  <View>
                                    <Text style={styles.copyActivitySymbol}>{toDisplaySymbol(item.symbol)}</Text>
                                    <Text style={styles.copyActivityMeta}>
                                      {item.side.toUpperCase()} · {t('assets.copyOverviewOpenedAt', { time: formatTransactionTime(item.opened_at) })}
                                    </Text>
                                  </View>
                                  <Text style={[styles.copyActivityPnl, { color: positive ? Colors.up : Colors.down }]}>
                                    {positive ? '+' : ''}{formatUsd(item.net_pnl)} USDT
                                  </Text>
                                </View>
                                <View style={styles.copyActivityMetrics}>
                                  <Text style={styles.copyActivityMetric}>{t('assets.copyHistoryGrossPnl')}: {formatUsd(item.gross_pnl)}</Text>
                                  <Text style={styles.copyActivityMetric}>{t('assets.copyHistoryFees')}: {formatUsd((item.open_fee || 0) + (item.close_fee || 0))}</Text>
                                  <Text style={styles.copyActivityMetric}>{t('assets.copyHistoryProfitShare')}: {formatUsd(item.profit_shared)}</Text>
                                  <Text style={styles.copyActivityMetric}>{t('assets.copyHistoryClosedAt')}: {formatTransactionTime(item.closed_at)}</Text>
                                </View>
                              </View>
                            );
                          })}
                          <Text style={styles.copyHistoryCountText}>
                            {t('assets.copyHistoryCount', { count: copyAccountHistoryTotal })}
                          </Text>
                        </View>
                      ) : (
                        <View style={styles.assetEmptyState}>
                          <Text style={styles.assetEmptyTitle}>{t('assets.copyHistoryEmptyTitle')}</Text>
                          <Text style={styles.assetEmptyBody}>{t('assets.copyHistoryEmptyBody')}</Text>
                        </View>
                      )}
                    </>
                  ) : (
                    <View style={styles.assetEmptyState}>
                      <Text style={styles.assetEmptyTitle}>{t('assets.copyAccountEmptyTitle')}</Text>
                      <Text style={styles.assetEmptyBody}>{t('assets.copyAccountEmptyBody')}</Text>
                    </View>
                  )}
                </View>
              </View>
            </View>
          ) : (
            <View style={styles.assetEmptyState}>
              <AppIcon name="chart" size={24} color={Colors.textMuted} />
              <Text style={styles.assetEmptyTitle}>{t('assets.copyAccountEmptyTitle')}</Text>
              <Text style={styles.assetEmptyBody}>{t('assets.copyAccountEmptyBody')}</Text>
            </View>
          )
        ) : workspaceView === 'assets' ? (
          <View style={styles.assetEmptyState}>
            <AppIcon
              name={assetCategory === 'stock' ? 'chart' : 'wallet'}
              size={24}
              color={Colors.textMuted}
            />
            <Text style={styles.assetEmptyTitle}>
              {assetCategory === 'stock'
                ? t('assets.stockAssetsEmptyTitle')
                : t('assets.spotAssetsEmptyTitle')}
            </Text>
            <Text style={styles.assetEmptyBody}>
              {assetCategory === 'stock'
                ? t('assets.stockAssetsEmptyBody')
                : t('assets.spotAssetsEmptyBody')}
            </Text>
          </View>
        ) : (
          <View style={styles.assetEmptyState}>
            <AppIcon name="wallet" size={24} color={Colors.textMuted} />
            <Text style={styles.assetEmptyTitle}>{t('assets.noAccountData')}</Text>
            <Text style={styles.assetEmptyBody}>{t('assets.accountsHint')}</Text>
          </View>
        )}
      </View>

      {pendingWithdrawalCount > 0 ? (
        <View style={styles.panelCard}>
          <View style={styles.sectionHead}>
            <View style={styles.sectionTitleRow}>
              <Text style={styles.sectionTitle}>{t('assets.pendingWithdrawalsTitle')}</Text>
              <TouchableOpacity
                activeOpacity={0.8}
                onPress={() =>
                  router.push({
                    pathname: '/portfolio/transactions',
                    params: { status: 'pending_review' },
                  } as any)
                }
              >
                <Text style={styles.viewAllLink}>{t('assets.viewPendingWithdrawals')}</Text>
              </TouchableOpacity>
            </View>
            <Text style={styles.sectionHint}>{t('assets.pendingWithdrawalsHint')}</Text>
          </View>

          <View style={styles.pendingHero}>
            <View style={styles.pendingHeroMetric}>
              <Text style={styles.metricLabel}>{t('assets.pendingWithdrawalsCount')}</Text>
              <Text style={styles.pendingHeroValue}>{pendingWithdrawalCount}</Text>
            </View>
            <View style={styles.pendingHeroMetric}>
              <Text style={styles.metricLabel}>{t('assets.pendingWithdrawalsAmount')}</Text>
              <Text style={styles.pendingHeroValue}>{formatUsd(pendingWithdrawalAmount)} USDT</Text>
            </View>
          </View>

          <View style={styles.pendingList}>
            {pendingWithdrawals.map((item) => (
              <View key={item.id} style={styles.pendingItem}>
                <View style={styles.pendingCardHead}>
                  <View style={styles.txTitleCluster}>
                    <View style={[styles.txIconWrap, styles.txIconWrapDanger]}>
                      <AppIcon name="send" size={16} color={Colors.down} />
                    </View>
                    <View style={styles.txTitleBlock}>
                      <View style={styles.txTypeRow}>
                        <Text style={styles.txType}>{t('assets.txWithdraw')}</Text>
                        <View style={styles.statusBadge}>
                          <Text style={styles.statusBadgeText}>{withdrawalStatusLabel(item.status, t)}</Text>
                        </View>
                      </View>
                      <Text style={styles.txTime}>{formatTransactionTime(item.created_at)}</Text>
                    </View>
                  </View>
                  <Text style={[styles.txAmountHero, { color: Colors.down }]}>-{formatUsd(item.amount)} USDT</Text>
                </View>
                <View style={styles.pendingItemMain}>
                  <Text style={styles.pendingMeta}>
                    {item.network} · {t('assets.pendingWithdrawalAddress', { address: item.address.slice(-8) })}
                  </Text>
                </View>
              </View>
            ))}
          </View>
        </View>
      ) : null}

      <View style={detailGridStyle}>
        <View style={[styles.panelCard, styles.flexCard]}>
          <View style={styles.sectionHead}>
            <Text style={styles.sectionTitle}>{t('assets.distributionTitle')}</Text>
            <Text style={styles.sectionHint}>{t('assets.distributionHint')}</Text>
          </View>
          <DistributionChart items={distributionItems} />
        </View>

        {workspaceView !== 'copy' ? (
        <View style={[styles.panelCard, styles.sideCard]}>
          <View style={styles.sectionHeadRow}>
            <View style={styles.sectionHeadCompact}>
              <Text style={styles.sectionTitle}>{t('assets.changeSeriesTitle')}</Text>
              <Text style={styles.sectionHint}>{t('assets.changeSeriesHint')}</Text>
            </View>
            <View style={styles.rangeTabs}>
              {changeRangeOptions.map((item) => (
                <TouchableOpacity
                  key={item.key}
                  activeOpacity={0.85}
                  style={[styles.rangeTab, range === item.key && styles.rangeTabActive]}
                  onPress={() => void handleChangeRange(item.key)}
                >
                  <Text style={[styles.rangeTabText, range === item.key && styles.rangeTabTextActive]}>
                    {item.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
          <ChangeSeriesChart points={displayOverview?.change_series || []} />
        </View>
        ) : null}
      </View>

      <View style={topGridStyle}>
        <View style={[styles.panelCard, styles.flexCard]}>
          <View style={styles.sectionHeadRow}>
            <View style={styles.sectionHeadText}>
              <Text style={styles.sectionTitle}>{t('assets.accountsTitle')}</Text>
              <Text style={styles.sectionHint}>{t('assets.accountsHint')}</Text>
            </View>
            {accountCards.length ? (
              <View style={styles.accountTotalBadge}>
                <Text style={styles.accountTotalLabel}>{t('assets.accountsTotalEquity')}</Text>
                <Text style={styles.accountTotalValue}>
                  {formatUsd(accountCards.reduce((sum, a) => sum + (a.equity || 0), 0))}
                  <Text style={styles.accountTotalUnit}> USDT</Text>
                </Text>
              </View>
            ) : null}
          </View>

          {accountCards.length ? (
            <View style={styles.accountListV2}>
              {accountCards.map((account) => {
                const isActive = selectedAccount?.account_type === account.account_type;
                const isFutures = account.account_type === 'futures';
                const pnl = account.unrealized_pnl || 0;
                const margin = account.margin_used || 0;
                return (
                  <TouchableOpacity
                    key={account.account_type}
                    activeOpacity={0.9}
                    onPress={() => setSelectedAccountType(account.account_type)}
                    style={[styles.accountItemV2, isActive && styles.accountItemV2Active]}
                  >
                    {isActive ? <View style={styles.accountActiveBar} /> : null}
                    <View style={styles.accountRowV2}>
                      <View
                        style={[
                          styles.accountIconV2,
                          isFutures && styles.accountIconV2Futures,
                        ]}
                      >
                        <AppIcon
                          name={isFutures ? 'futures' : 'wallet'}
                          size={18}
                          color={isFutures ? Colors.primary : Colors.textSecondary}
                        />
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.accountNameV2} numberOfLines={1}>
                          {accountDisplayLabel(account.account_type, account.display_name, t)}
                        </Text>
                        <Text style={styles.accountTypeV2}>{account.account_type.toUpperCase()}</Text>
                      </View>
                      {account.is_virtual ? (
                        <View style={styles.virtualBadge}>
                          <Text style={styles.virtualBadgeText}>{t('assets.virtualTag')}</Text>
                        </View>
                      ) : null}
                    </View>

                    <View style={styles.accountEquityRow}>
                      <Text style={styles.accountEquityValue}>
                        {formatUsd(account.equity)}
                        <Text style={styles.accountEquityUnit}> USDT</Text>
                      </Text>
                      {pnl !== 0 ? (
                        <View
                          style={[
                            styles.accountPnlChip,
                            { backgroundColor: pnl >= 0 ? Colors.upDim : Colors.downDim },
                          ]}
                        >
                          <Text
                            style={[
                              styles.accountPnlChipText,
                              { color: pnl >= 0 ? Colors.up : Colors.down },
                            ]}
                          >
                            {pnl >= 0 ? '+' : ''}
                            {formatUsd(pnl)}
                          </Text>
                        </View>
                      ) : null}
                    </View>

                    <View style={styles.accountMetaRowV2}>
                      <View style={styles.accountMetaItem}>
                        <Text style={styles.metricLabel}>{t('assets.available')}</Text>
                        <Text style={styles.accountMetaValue}>
                          {formatUsd(account.available)}
                        </Text>
                      </View>
                      <View style={styles.accountMetaDivider} />
                      <View style={styles.accountMetaItem}>
                        <Text style={styles.metricLabel}>{t('assets.frozen')}</Text>
                        <Text style={styles.accountMetaValue}>
                          {formatUsd(account.frozen)}
                        </Text>
                      </View>
                      {margin ? (
                        <>
                          <View style={styles.accountMetaDivider} />
                          <View style={styles.accountMetaItem}>
                            <Text style={styles.metricLabel}>{t('assets.marginUsed')}</Text>
                            <Text style={styles.accountMetaValue}>{formatUsd(margin)}</Text>
                          </View>
                        </>
                      ) : null}
                    </View>

                    {account.is_virtual ? (
                      <Text style={styles.accountVirtualHint}>{t('assets.virtualAccountHint')}</Text>
                    ) : null}
                  </TouchableOpacity>
                );
              })}
            </View>
          ) : (
            <Text style={styles.emptyText}>{t('assets.noAccountData')}</Text>
          )}
        </View>

        {workspaceView !== 'copy' ? (
        <View style={[styles.panelCard, styles.sideCard]}>
          <View style={styles.sectionHead}>
            <View style={styles.readOnlyTitleRow}>
              <Text style={styles.sectionTitle}>{t('assets.copySummaryTitle')}</Text>
              <View style={styles.readOnlyBadge}>
                <Text style={styles.readOnlyBadgeText}>{t('assets.readOnlyTag')}</Text>
              </View>
            </View>
            <Text style={styles.sectionHint}>{t('assets.copySummaryHint')}</Text>
          </View>

          {/* 池子总权益主卡：数字聚焦 + 交易员/持仓数即时反馈 + 可用/冻结/累计分配三列明细 */}
          <View style={styles.copyHeroCard}>
            <Text style={styles.copyHeroLabel}>{t('assets.copySummaryPoolEquity')}</Text>
            <Text style={styles.copyHeroValue}>
              {formatUsd((copySummary?.total_available || 0) + (copySummary?.total_frozen || 0))}
              <Text style={styles.copyHeroUnit}> USDT</Text>
            </Text>
            <Text style={styles.copyHeroHint}>
              {t('assets.copySummaryPoolEquityHint', {
                count: copySummary?.active_trader_count || 0,
                positions: copySummary?.open_position_count || 0,
              })}
            </Text>
            <View style={styles.copyHeroMetaRow}>
              <View style={styles.copyHeroMetaItem}>
                <Text style={styles.metricLabel}>{t('assets.copyAvailable')}</Text>
                <Text style={styles.copyHeroMetaValue}>{formatUsd(copySummary?.total_available)}</Text>
              </View>
              <View style={styles.copyHeroDivider} />
              <View style={styles.copyHeroMetaItem}>
                <Text style={styles.metricLabel}>{t('assets.copyFrozen')}</Text>
                <Text style={styles.copyHeroMetaValue}>{formatUsd(copySummary?.total_frozen)}</Text>
              </View>
              <View style={styles.copyHeroDivider} />
              <View style={styles.copyHeroMetaItem}>
                <Text style={styles.metricLabel}>{t('assets.copyAllocated')}</Text>
                <Text style={styles.copyHeroMetaValue}>{formatUsd(copySummary?.total_allocated)}</Text>
              </View>
            </View>
          </View>

          {copySummary?.items?.length ? (
            <View style={styles.copyItemsV2}>
              {copySummary.items.map((item) => {
                const active = selectedCopyItem?.trader_uid === item.trader_uid;
                // 从 copyAccountPools（富字段）里取 PNL / ROI；若尚未加载成功则退化到 0。
                const pool = copyPoolByTrader.get(item.trader_uid);
                const pnl = pool?.current_net_pnl || 0;
                const roi = pool?.current_return_rate || 0;
                const pnlPositive = pnl >= 0;
                const roiPositive = roi >= 0;
                return (
                  <TouchableOpacity
                    key={item.trader_uid}
                    activeOpacity={0.9}
                    onPress={() => {
                      // 点击池子直接跳到跟单账户详情 tab，避免用户还要再切换一次
                      setSelectedCopyTraderUid(item.trader_uid);
                      setWorkspaceView('copy');
                    }}
                    style={[styles.copyItemV2, active && styles.copyItemV2Active]}
                  >
                    <View style={styles.copyItemV2Head}>
                      <View style={styles.copyItemV2NameRow}>
                        <Text style={styles.copyTraderName} numberOfLines={1}>
                          {item.trader_name}
                        </Text>
                        <View style={styles.copyStatusPill}>
                          <View style={styles.copyStatusDot} />
                          <Text style={styles.copyStatusPillText}>
                            {copyStatusLabel(item.status, t)}
                          </Text>
                        </View>
                      </View>
                      {pool ? (
                        <View style={styles.copyItemV2PnlCol}>
                          <Text
                            style={[
                              styles.copyItemV2Pnl,
                              { color: pnlPositive ? Colors.up : Colors.down },
                            ]}
                            numberOfLines={1}
                          >
                            {pnlPositive ? '+' : ''}
                            {formatUsd(pnl)} USDT
                          </Text>
                          <Text
                            style={[
                              styles.copyItemV2Roi,
                              { color: roiPositive ? Colors.up : Colors.down },
                            ]}
                            numberOfLines={1}
                          >
                            {roiPositive ? '+' : ''}
                            {formatPercent(roi)}
                          </Text>
                        </View>
                      ) : null}
                      <Text style={styles.copyItemV2Chevron}>›</Text>
                    </View>
                    <View style={styles.copyItemV2MetaRow}>
                      <View style={styles.copyItemV2MetaCell}>
                        <Text style={styles.metricLabel}>{t('assets.copyAllocated')}</Text>
                        <Text style={styles.copyItemV2MetaValue}>
                          {formatUsd(item.allocated_capital)}
                        </Text>
                      </View>
                      <View style={styles.copyItemV2MetaCell}>
                        <Text style={styles.metricLabel}>{t('assets.copyAvailable')}</Text>
                        <Text style={styles.copyItemV2MetaValue}>
                          {formatUsd(item.available_capital)}
                        </Text>
                      </View>
                      <View style={styles.copyItemV2MetaCell}>
                        <Text style={styles.metricLabel}>{t('assets.copyFrozen')}</Text>
                        <Text style={styles.copyItemV2MetaValue}>
                          {formatUsd(item.frozen_capital)}
                        </Text>
                      </View>
                    </View>
                  </TouchableOpacity>
                );
              })}
            </View>
          ) : (
            <Text style={styles.emptyText}>{t('assets.copySummaryEmpty')}</Text>
          )}
        </View>
        ) : null}
      </View>

      {workspaceView === 'accounts' ? (
      <View style={detailGridStyle}>
        <View style={[styles.panelCard, styles.flexCard]}>
          <View style={styles.sectionHead}>
            <Text style={styles.sectionTitle}>{t('assets.accountDetailTitle')}</Text>
            <Text style={styles.sectionHint}>{t('assets.accountDetailHint')}</Text>
          </View>

          {selectedAccount ? (
            <View style={styles.detailBody}>
              <View style={styles.detailHero}>
                <View>
                  <Text style={styles.detailHeroTitle}>{accountDisplayLabel(selectedAccount.account_type, selectedAccount.display_name, t)}</Text>
                  <Text style={styles.detailHeroSub}>{accountTypeCodeLabel(selectedAccount.account_type)}</Text>
                </View>
                {selectedAccount.is_virtual ? (
                  <View style={styles.virtualBadge}>
                    <Text style={styles.virtualBadgeText}>{t('assets.virtualTag')}</Text>
                  </View>
                ) : null}
              </View>

              <View style={styles.detailMetricGrid}>
                <View style={styles.detailMetricCard}>
                  <Text style={styles.metricLabel}>{t('assets.equity')}</Text>
                  <Text style={styles.detailMetricValue}>{formatUsd(selectedAccount.equity)} USDT</Text>
                </View>
                <View style={styles.detailMetricCard}>
                  <Text style={styles.metricLabel}>{t('assets.available')}</Text>
                  <Text style={styles.detailMetricValue}>{formatUsd(selectedAccount.available)} USDT</Text>
                </View>
                <View style={styles.detailMetricCard}>
                  <Text style={styles.metricLabel}>{t('assets.frozen')}</Text>
                  <Text style={styles.detailMetricValue}>{formatUsd(selectedAccount.frozen)} USDT</Text>
                </View>
                <View style={styles.detailMetricCard}>
                  <Text style={styles.metricLabel}>{t('assets.marginUsed')}</Text>
                  <Text style={styles.detailMetricValue}>{formatUsd(selectedAccount.margin_used)} USDT</Text>
                </View>
              </View>

              <View style={styles.detailNoteCard}>
                <Text style={styles.detailNoteText}>
                  {selectedAccount.account_type === 'futures'
                    ? t('assets.accountDetailFuturesHint')
                    : t('assets.accountDetailMainHint')}
                </Text>
                {selectedAccount.is_virtual ? (
                  <Text style={styles.detailNoteMuted}>{t('assets.virtualAccountHint')}</Text>
                ) : (
                  <Text style={styles.detailNoteMuted}>
                    {t('assets.unrealizedPnl')}: {formatUsd(selectedAccount.unrealized_pnl)} USDT
                  </Text>
                )}
              </View>
            </View>
          ) : (
            <Text style={styles.emptyText}>{t('assets.noAccountData')}</Text>
          )}
        </View>
      </View>
      ) : null}

      <View style={styles.panelCard}>
        <View style={styles.sectionHead}>
          <View style={styles.sectionTitleRow}>
            <Text style={styles.sectionTitle}>{t('assets.recentTransactions')}</Text>
            <TouchableOpacity activeOpacity={0.8} onPress={() => router.push('/portfolio/transactions' as any)}>
              <Text style={styles.viewAllLink}>{t('assets.viewAllTransactions')}</Text>
            </TouchableOpacity>
          </View>
          <Text style={styles.sectionHint}>{t('assets.recentTransactionsHint')}</Text>
        </View>

        {transactions.length ? (
          <View style={styles.txList}>
            {transactions.map((tx) => {
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
                  <Text style={styles.txNote} numberOfLines={1}>{tx.note || '--'}</Text>
                </View>
              );
            })}
          </View>
        ) : (
          <Text style={styles.emptyText}>{t('assets.emptyTransactions')}</Text>
        )}
      </View>

      <Modal visible={showPnlCalendarModal} transparent animationType="fade" onRequestClose={() => setShowPnlCalendarModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={[styles.modalCard, styles.calendarModalCard]}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>{t('assets.pnlCalendarTitle')}</Text>
                <Text style={styles.modalSubtitle}>{t('assets.pnlCalendarHint')}</Text>
              </View>
              <TouchableOpacity style={styles.modalClose} activeOpacity={0.8} onPress={() => setShowPnlCalendarModal(false)}>
                <AppIcon name="close" size={16} color={Colors.textSecondary} />
              </TouchableOpacity>
            </View>

            <View style={styles.calendarToolbar}>
              <TouchableOpacity style={styles.calendarNavBtn} activeOpacity={0.85} onPress={() => void handleCalendarShift(-1)}>
                <AppIcon name="back" size={14} color={Colors.textSecondary} />
              </TouchableOpacity>
              <Text style={styles.calendarMonthLabel}>{calendarMonthLabel}</Text>
              <TouchableOpacity style={styles.calendarNavBtn} activeOpacity={0.85} onPress={() => void handleCalendarShift(1)}>
                <AppIcon name="back" size={14} color={Colors.textSecondary} style={{ transform: [{ rotate: '180deg' }] }} />
              </TouchableOpacity>
            </View>

            <View style={styles.calendarSummaryRow}>
              <View style={styles.calendarSummaryMetric}>
                <Text style={styles.calendarSummaryLabel}>{t('assets.pnlCalendarNet')}</Text>
                <Text
                  style={[
                    styles.calendarSummaryValue,
                    { color: (calendar?.net_pnl || 0) >= 0 ? Colors.up : Colors.down },
                  ]}
                >
                  {(calendar?.net_pnl || 0) >= 0 ? '+' : ''}
                  {formatUsd(calendar?.net_pnl)} USDT
                </Text>
              </View>
              <View style={styles.calendarSummaryMetric}>
                <Text style={styles.calendarSummaryLabel}>{t('assets.pnlCalendarPositiveDays')}</Text>
                <Text style={styles.calendarSummaryValue}>{calendar?.positive_days || 0}</Text>
              </View>
              <View style={styles.calendarSummaryMetric}>
                <Text style={styles.calendarSummaryLabel}>{t('assets.pnlCalendarNegativeDays')}</Text>
                <Text style={styles.calendarSummaryValue}>{calendar?.negative_days || 0}</Text>
              </View>
            </View>

            {calendarLoading && !calendar ? (
              <View style={styles.assetEmptyState}>
                <ActivityIndicator color={Colors.primary} />
                <Text style={styles.assetEmptyBody}>{t('assets.loading')}</Text>
              </View>
            ) : (
              <>
                <PnlCalendar
                  data={calendar}
                  weekdays={calendarWeekdays}
                  selectedDate={selectedCalendarDay?.date || null}
                  onSelectDate={setSelectedCalendarDate}
                />
                {selectedCalendarDay ? (
                  <View style={styles.calendarDetailCard}>
                    <Text style={styles.calendarDetailDate}>{selectedCalendarDay.date}</Text>
                    <View style={styles.calendarDetailRow}>
                      <Text style={styles.calendarDetailLabel}>{t('assets.pnlCalendarDayNet')}</Text>
                      <Text
                        style={[
                          styles.calendarDetailValue,
                          { color: selectedCalendarDay.net_pnl >= 0 ? Colors.up : Colors.down },
                        ]}
                      >
                        {selectedCalendarDay.net_pnl >= 0 ? '+' : ''}
                        {formatUsd(selectedCalendarDay.net_pnl)} USDT
                      </Text>
                    </View>
                    <View style={styles.calendarDetailRow}>
                      <Text style={styles.calendarDetailLabel}>{t('assets.pnlCalendarMonthNet')}</Text>
                      <Text style={styles.calendarDetailValue}>
                        {selectedCalendarCumulative >= 0 ? '+' : ''}
                        {formatUsd(selectedCalendarCumulative)} USDT
                      </Text>
                    </View>
                  </View>
                ) : null}
              </>
            )}
          </View>
        </View>
      </Modal>

      <Modal visible={showDepositModal} transparent animationType="fade" onRequestClose={() => setShowDepositModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalCard}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>{t('assets.depositModalTitle')}</Text>
                <Text style={styles.modalSubtitle}>{t('assets.depositModalSubtitle')}</Text>
              </View>
              <TouchableOpacity style={styles.modalClose} activeOpacity={0.8} onPress={() => setShowDepositModal(false)}>
                <AppIcon name="close" size={16} color={Colors.textSecondary} />
              </TouchableOpacity>
            </View>

            <View style={styles.depositInfoCard}>
              <Text style={styles.depositInfoLabel}>{t('assets.distributionMain')}</Text>
              <Text style={styles.depositInfoValue}>
                {formatUsd(accountCards.find((account) => account.account_type === 'spot' || account.account_type === 'main')?.available)} USDT
              </Text>
              <Text style={styles.depositInfoHint}>{t('assets.depositHint')}</Text>
            </View>

            <View style={styles.inputGroup}>
              <Text style={styles.inputLabel}>{t('assets.depositAssetLabel')}</Text>
              <View style={styles.selectorCard}>
                <TouchableOpacity
                  activeOpacity={0.85}
                  style={styles.dropdownTrigger}
                  onPress={() => setShowDepositAssetMenu((current) => !current)}
                >
                  <View style={styles.dropdownValueWrap}>
                    <Text style={styles.dropdownValue}>{selectedDepositAsset?.label || depositAssetCode}</Text>
                    <Text style={styles.dropdownMeta}>{t('assets.depositAssetDropdownHint')}</Text>
                  </View>
                  <Text style={styles.dropdownCaret}>{showDepositAssetMenu ? '▴' : '▾'}</Text>
                </TouchableOpacity>

                {showDepositAssetMenu ? (
                  <View style={styles.dropdownMenu}>
                    {depositOptions.map((item) => (
                      <TouchableOpacity
                        key={item.asset_code}
                        activeOpacity={0.85}
                        style={[
                          styles.dropdownItem,
                          depositAssetCode === item.asset_code && styles.dropdownItemActive,
                        ]}
                        onPress={() => {
                          setDepositAssetCode(item.asset_code);
                          setShowDepositAssetMenu(false);
                        }}
                      >
                        <Text
                          style={[
                            styles.dropdownItemText,
                            depositAssetCode === item.asset_code && styles.dropdownItemTextActive,
                          ]}
                        >
                          {item.label}
                        </Text>
                        {depositAssetCode === item.asset_code ? (
                          <AppIcon name="check" size={14} color={Colors.primary} />
                        ) : null}
                      </TouchableOpacity>
                    ))}
                  </View>
                ) : null}
              </View>
            </View>

            <View style={styles.inputGroup}>
              <Text style={styles.inputLabel}>{t('assets.depositNetworkLabel')}</Text>
              <View style={styles.networkCard}>
                {depositNetworks.map((item) => (
                  <TouchableOpacity
                    key={item.value}
                    activeOpacity={0.85}
                    style={[styles.optionChip, depositNetwork === item.value && styles.optionChipActive]}
                    onPress={() => setDepositNetwork(item.value)}
                  >
                    <Text style={[styles.optionChipText, depositNetwork === item.value && styles.optionChipTextActive]}>
                      {item.label}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>

            <View style={styles.depositAddressCard}>
              <Text style={styles.depositInfoLabel}>{t('assets.depositAddressLabel')}</Text>
              {loadingDepositAddress ? (
                <View style={styles.depositAddressLoadingRow}>
                  <ActivityIndicator color={Colors.primary} />
                  <Text style={styles.depositInfoHint}>{t('assets.depositAddressLoading')}</Text>
                </View>
              ) : depositAddressRecord ? (
                <>
                  <View style={styles.depositQrCard}>
                    <QRCode
                      value={depositAddressRecord.address}
                      size={180}
                      quietZone={16}
                      color={Colors.background}
                      backgroundColor="#FFFFFF"
                    />
                  </View>
                  <Text style={styles.depositQrHint}>
                    {t('assets.depositQrHint', { asset: depositAssetCode, network: depositNetwork })}
                  </Text>
                  <View style={styles.depositAddressDisplayCard}>
                    <ScrollView
                      horizontal
                      showsHorizontalScrollIndicator={false}
                      contentContainerStyle={styles.depositAddressScrollContent}
                      style={styles.depositAddressScroll}
                    >
                      <Text style={[styles.depositAddressSingleLine, { fontSize: depositAddressPreview.fontSize }]}>
                        <Text style={styles.depositAddressHighlight}>{depositAddressPreview.prefix}</Text>
                        <Text style={styles.depositAddressMuted}>{depositAddressPreview.middle}</Text>
                        <Text style={styles.depositAddressHighlight}>{depositAddressPreview.suffix}</Text>
                      </Text>
                    </ScrollView>
                  </View>
                  {depositAddressRecord.memo ? (
                    <Text style={styles.depositMemoText}>{t('assets.depositMemoLabel')}: {depositAddressRecord.memo}</Text>
                  ) : null}
                </>
              ) : (
                <Text style={styles.depositInfoHint}>{t('assets.depositAddressEmpty')}</Text>
              )}
            </View>

            <View style={styles.depositHistoryCard}>
              <View style={styles.sectionTitleRow}>
                <Text style={styles.depositInfoLabel}>{t('assets.depositHistoryTitle')}</Text>
                <TouchableOpacity activeOpacity={0.8} onPress={() => void loadDepositHistory(depositAssetCode)}>
                  <Text style={styles.viewAllLink}>{t('assets.refresh')}</Text>
                </TouchableOpacity>
              </View>

              {loadingDepositRecords ? (
                <View style={styles.depositAddressLoadingRow}>
                  <ActivityIndicator color={Colors.primary} />
                  <Text style={styles.depositInfoHint}>{t('assets.depositHistoryLoading')}</Text>
                </View>
              ) : depositRecords.length ? (
                <View style={styles.depositHistoryList}>
                  {depositRecords.map((item) => (
                    <View key={item.id} style={styles.depositHistoryItem}>
                      <View style={styles.depositHistoryMain}>
                        <View style={styles.txTypeRow}>
                          <Text style={styles.txType}>{item.asset_code} · {item.network}</Text>
                          <View style={[
                            styles.statusBadge,
                            item.status === 'credited' && styles.statusBadgeSuccess,
                            item.status === 'failed' && styles.statusBadgeDanger,
                          ]}>
                            <Text style={styles.statusBadgeText}>{depositStatusLabel(item.status, t)}</Text>
                          </View>
                        </View>
                        <Text style={styles.txNote}>
                          {t('assets.depositHistoryAddress', { address: item.address.slice(-10) })}
                        </Text>
                        <Text style={styles.txTime}>{formatTransactionTime(item.credited_at || item.created_at)}</Text>
                      </View>
                      <View style={styles.depositHistorySide}>
                        <Text style={[styles.txAmount, { color: Colors.up }]}>+{formatUsd(item.amount)}</Text>
                        {item.confirmations > 0 ? (
                          <Text style={styles.depositHistoryMeta}>
                            {t('assets.depositHistoryConfirmations', { count: item.confirmations })}
                          </Text>
                        ) : null}
                      </View>
                    </View>
                  ))}
                </View>
              ) : (
                <Text style={styles.depositInfoHint}>{t('assets.depositHistoryEmpty')}</Text>
              )}
            </View>

            <View style={styles.modalActions}>
              <TouchableOpacity style={styles.modalSecondaryBtn} activeOpacity={0.85} onPress={() => setShowDepositModal(false)}>
                <Text style={styles.modalSecondaryBtnText}>{t('common.close')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.modalPrimaryBtn, loadingDepositAddress && styles.modalPrimaryBtnDisabled]}
                activeOpacity={0.85}
                onPress={() => void handleCopyDepositAddress()}
                disabled={loadingDepositAddress || !depositAddressRecord?.address}
              >
                <Text style={styles.modalPrimaryBtnText}>
                  {loadingDepositAddress
                    ? t('assets.depositAddressLoading')
                    : t('assets.depositCopyAction')}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal
        visible={showWithdrawModal}
        transparent
        animationType="fade"
        onRequestClose={() => {
          setShowWithdrawNetworkMenu(false);
          setShowWithdrawModal(false);
        }}
      >
        <View style={styles.modalBackdrop}>
          <View style={[styles.modalCard, styles.withdrawModalCard]}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>{t('assets.withdrawModalTitle')}</Text>
                <Text style={styles.modalSubtitle}>{t('assets.withdrawModalSubtitle')}</Text>
              </View>
              <TouchableOpacity
                style={styles.modalClose}
                activeOpacity={0.8}
                onPress={() => {
                  setShowWithdrawNetworkMenu(false);
                  setShowWithdrawModal(false);
                }}
              >
                <AppIcon name="close" size={16} color={Colors.textSecondary} />
              </TouchableOpacity>
            </View>
            <ScrollView
              style={styles.withdrawScroll}
              contentContainerStyle={styles.withdrawScrollContent}
              showsVerticalScrollIndicator={false}
            >
              <View style={styles.withdrawHeroCard}>
                <View style={styles.withdrawHeroTop}>
                  <View>
                    <Text style={styles.depositInfoLabel}>{t('assets.distributionMain')}</Text>
                    <Text style={styles.depositInfoValue}>{formatUsd(spotAvailable)} USDT</Text>
                  </View>
                  <View style={styles.withdrawAssetPill}>
                    <Text style={styles.withdrawAssetPillText}>USDT</Text>
                  </View>
                </View>
                <Text style={styles.depositInfoHint}>{t('assets.withdrawHint')}</Text>
              </View>

              <View style={styles.withdrawSection}>
                <Text style={styles.withdrawSectionTitle}>{t('assets.withdrawDestinationTitle')}</Text>
                <View style={styles.inputGroup}>
                  <Text style={styles.inputLabel}>{t('assets.withdrawNetworkLabel')}</Text>
                  <View style={styles.selectorCard}>
                    <TouchableOpacity
                      activeOpacity={0.85}
                      style={styles.dropdownTrigger}
                      onPress={() => setShowWithdrawNetworkMenu((current) => !current)}
                    >
                      <View style={styles.dropdownValueWrap}>
                        <Text style={styles.dropdownValue}>
                          {withdrawNetworks.find((item) => item.value === withdrawNetwork)?.label || withdrawNetwork}
                        </Text>
                        <Text style={styles.dropdownMeta}>{t('assets.withdrawNetworkDropdownHint')}</Text>
                      </View>
                      <Text style={styles.dropdownCaret}>{showWithdrawNetworkMenu ? '▴' : '▾'}</Text>
                    </TouchableOpacity>

                    {showWithdrawNetworkMenu ? (
                      <View style={styles.dropdownMenu}>
                        {withdrawNetworks.map((item) => (
                          <TouchableOpacity
                            key={item.value}
                            activeOpacity={0.85}
                            style={[
                              styles.dropdownItem,
                              withdrawNetwork === item.value && styles.dropdownItemActive,
                            ]}
                            onPress={() => {
                              setWithdrawNetwork(item.value);
                              setShowWithdrawNetworkMenu(false);
                            }}
                          >
                            <Text
                              style={[
                                styles.dropdownItemText,
                                withdrawNetwork === item.value && styles.dropdownItemTextActive,
                              ]}
                            >
                              {item.label}
                            </Text>
                            {withdrawNetwork === item.value ? (
                              <AppIcon name="check" size={14} color={Colors.primary} />
                            ) : null}
                          </TouchableOpacity>
                        ))}
                      </View>
                    ) : null}
                  </View>
                </View>

                <View style={styles.inputGroup}>
                  <Text style={styles.inputLabel}>{t('assets.withdrawAddressLabel')}</Text>
                  <TextInput
                    value={withdrawAddress}
                    onChangeText={setWithdrawAddress}
                    placeholder={t('assets.withdrawAddressPlaceholder')}
                    placeholderTextColor={Colors.textMuted}
                    style={[styles.input, styles.withdrawAddressInput]}
                    multiline
                    textAlignVertical="top"
                    autoCapitalize="none"
                    autoCorrect={false}
                  />
                  <Text style={styles.withdrawAddressHint}>{t('assets.withdrawAddressHint')}</Text>
                </View>
              </View>

              <View style={styles.withdrawSection}>
                <View style={styles.withdrawAmountHead}>
                  <Text style={styles.withdrawSectionTitle}>{t('assets.withdrawAmountLabel')}</Text>
                  <TouchableOpacity
                    activeOpacity={0.85}
                    style={styles.withdrawMaxBtn}
                    onPress={() => setWithdrawAmount(spotAvailable > 0 ? spotAvailable.toFixed(2) : '')}
                  >
                    <Text style={styles.withdrawMaxBtnText}>{t('assets.withdrawMaxAction')}</Text>
                  </TouchableOpacity>
                </View>
                <View style={styles.withdrawAmountCard}>
                  <TextInput
                    value={withdrawAmount}
                    onChangeText={setWithdrawAmount}
                    keyboardType="decimal-pad"
                    placeholder={t('assets.withdrawAmountPlaceholder')}
                    placeholderTextColor={Colors.textMuted}
                    style={styles.withdrawAmountInput}
                  />
                  <Text style={styles.withdrawAmountSuffix}>USDT</Text>
                </View>
                <View style={styles.withdrawPercentRow}>
                  {[0.25, 0.5, 1].map((ratio) => (
                    <TouchableOpacity
                      key={ratio}
                      activeOpacity={0.85}
                      style={styles.withdrawPercentChip}
                      onPress={() => setWithdrawAmount(spotAvailable > 0 ? (spotAvailable * ratio).toFixed(2) : '')}
                    >
                      <Text style={styles.withdrawPercentChipText}>{Math.round(ratio * 100)}%</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              <View style={styles.withdrawSummaryCard}>
                <Text style={styles.withdrawSectionTitle}>{t('assets.withdrawSummaryTitle')}</Text>
                <View style={styles.withdrawSummaryRow}>
                  <Text style={styles.withdrawSummaryLabel}>{t('assets.withdrawSummaryReceive')}</Text>
                  <Text style={styles.withdrawSummaryValue}>{formatUsd(withdrawEstimatedReceive)} USDT</Text>
                </View>
                <View style={styles.withdrawSummaryRow}>
                  <Text style={styles.withdrawSummaryLabel}>{t('assets.withdrawSummaryAsset')}</Text>
                  <Text style={styles.withdrawSummaryValue}>USDT · {withdrawNetwork}</Text>
                </View>
                <View style={styles.withdrawSummaryRow}>
                  <Text style={styles.withdrawSummaryLabel}>{t('assets.withdrawSummaryAvailableAfter')}</Text>
                  <Text style={styles.withdrawSummaryValue}>{formatUsd(withdrawAvailableAfter)} USDT</Text>
                </View>
                <View style={[styles.withdrawSummaryRow, styles.withdrawSummaryRowWrap]}>
                  <Text style={styles.withdrawSummaryLabel}>{t('assets.withdrawSummaryReviewPath')}</Text>
                  <Text style={styles.withdrawSummaryPath}>{t('assets.withdrawReviewFlow')}</Text>
                </View>
              </View>

              <View style={styles.withdrawRiskCard}>
                <View style={styles.withdrawRiskTitleRow}>
                  <AppIcon name="shield" size={14} color={Colors.warning} />
                  <Text style={styles.withdrawRiskTitle}>{t('assets.withdrawRiskTitle')}</Text>
                </View>
                <Text style={styles.withdrawRiskBody}>
                  {t('assets.withdrawRiskBody', { network: withdrawNetwork || 'TRC20' })}
                </Text>
              </View>
            </ScrollView>

            <View style={styles.modalActions}>
              <TouchableOpacity
                style={styles.modalSecondaryBtn}
                activeOpacity={0.85}
                onPress={() => {
                  setShowWithdrawNetworkMenu(false);
                  setShowWithdrawModal(false);
                }}
              >
                <Text style={styles.modalSecondaryBtnText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.modalPrimaryBtn, !canSubmitWithdraw && styles.modalPrimaryBtnDisabled]}
                activeOpacity={0.85}
                onPress={() => void handleWithdraw()}
                disabled={!canSubmitWithdraw}
              >
                <Text style={styles.modalPrimaryBtnText}>
                  {withdrawing ? t('assets.withdrawSubmitting') : t('assets.withdrawConfirmAction')}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal visible={showTransferModal} transparent animationType="fade" onRequestClose={() => setShowTransferModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalCard}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>{t('assets.transferModalTitle')}</Text>
                <Text style={styles.modalSubtitle}>{t('assets.transferModalSubtitle')}</Text>
              </View>
              <TouchableOpacity style={styles.modalClose} activeOpacity={0.8} onPress={() => setShowTransferModal(false)}>
                <AppIcon name="close" size={16} color={Colors.textSecondary} />
              </TouchableOpacity>
            </View>

            <View style={styles.transferHeroCard}>
              <View style={styles.transferHeroTop}>
                <Text style={styles.metricLabel}>{t('assets.transferAvailableTitle')}</Text>
                <View style={styles.withdrawAssetPill}>
                  <Text style={styles.withdrawAssetPillText}>USDT</Text>
                </View>
              </View>
              <Text style={styles.transferHeroValue}>{formatUsd(transferSourceAvailable)} USDT</Text>
              <Text style={styles.transferHeroHint}>
                {transferDirection === 'spot_to_futures'
                  ? t('assets.transferMainToFutures')
                  : t('assets.transferFuturesToMain')}
              </Text>
            </View>

            <View style={styles.transferRouteSection}>
              <View style={[styles.transferRouteCard, styles.transferRouteCardActive]}>
                <View style={styles.transferRouteHead}>
                  <Text style={styles.transferRouteLabel}>{t('assets.transferFromLabel')}</Text>
                  <View style={[styles.transferRoutePill, styles.transferRoutePillActive]}>
                    <Text style={[styles.transferRoutePillText, styles.transferRoutePillTextActive]}>
                      {t('assets.transferFromLabel')}
                    </Text>
                  </View>
                </View>
                <Text style={styles.transferRouteValue}>
                  {accountDisplayLabel(
                    transferSourceAccount?.account_type || '',
                    transferSourceAccount?.display_name || '',
                    t,
                  )}
                </Text>
                <Text style={styles.transferRouteMeta}>
                  {t('assets.transferAvailableLabel')}: {formatUsd(transferSourceAvailable)} USDT
                </Text>
              </View>
              <TouchableOpacity
                style={styles.transferSwapButton}
                activeOpacity={0.85}
                onPress={() =>
                  setTransferDirection((current) =>
                    current === 'spot_to_futures' ? 'futures_to_spot' : 'spot_to_futures',
                  )
                }
              >
                <Text style={styles.transferSwapButtonText}>⇅</Text>
              </TouchableOpacity>
              <View style={styles.transferRouteCard}>
                <View style={styles.transferRouteHead}>
                  <Text style={styles.transferRouteLabel}>{t('assets.transferToLabel')}</Text>
                  <View style={styles.transferRoutePill}>
                    <Text style={styles.transferRoutePillText}>{t('assets.transferToLabel')}</Text>
                  </View>
                </View>
                <Text style={styles.transferRouteValue}>
                  {accountDisplayLabel(
                    transferTargetAccount?.account_type || '',
                    transferTargetAccount?.display_name || '',
                    t,
                  )}
                </Text>
                <Text style={styles.transferRouteMeta}>
                  {t('assets.transferAvailableLabel')}: {formatUsd(transferTargetAvailable)} USDT
                </Text>
              </View>
            </View>

            <View style={styles.transferAmountSection}>
              <View style={styles.withdrawAmountHead}>
                <Text style={styles.inputLabel}>{t('assets.transferAmountLabel')}</Text>
                <TouchableOpacity
                  style={styles.withdrawMaxBtn}
                  activeOpacity={0.85}
                  onPress={() =>
                    setTransferAmount(
                      transferSourceAvailable > 0 ? String(Number(transferSourceAvailable.toFixed(8))) : '',
                    )
                  }
                >
                  <Text style={styles.withdrawMaxBtnText}>{t('assets.transferMaxAction')}</Text>
                </TouchableOpacity>
              </View>
              <View style={styles.withdrawAmountCard}>
                <TextInput
                  value={transferAmount}
                  onChangeText={setTransferAmount}
                  keyboardType="decimal-pad"
                  placeholder={t('assets.transferAmountPlaceholder')}
                  placeholderTextColor={Colors.textMuted}
                  style={styles.withdrawAmountInput}
                />
                <Text style={styles.withdrawAmountSuffix}>USDT</Text>
              </View>
              <View style={styles.withdrawPercentRow}>
                {[0.25, 0.5, 1].map((ratio) => (
                  <TouchableOpacity
                    key={ratio}
                    style={styles.withdrawPercentChip}
                    activeOpacity={0.85}
                    onPress={() =>
                      setTransferAmount(
                        transferSourceAvailable > 0
                          ? String(Number((transferSourceAvailable * ratio).toFixed(8)))
                          : '',
                      )
                    }
                  >
                    <Text style={styles.withdrawPercentChipText}>{ratio === 1 ? '100%' : `${ratio * 100}%`}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>

            <View style={styles.withdrawSummaryCard}>
              <Text style={styles.withdrawSectionTitle}>{t('assets.transferSummaryTitle')}</Text>
              <View style={styles.withdrawSummaryRow}>
                <Text style={styles.withdrawSummaryLabel}>{t('assets.transferSummaryReceive')}</Text>
                <Text style={styles.withdrawSummaryValue}>
                  {formatUsd(Math.max(Number.isFinite(transferValue) ? transferValue : 0, 0))} USDT
                </Text>
              </View>
              <View style={styles.withdrawSummaryRow}>
                <Text style={styles.withdrawSummaryLabel}>{t('assets.transferFromLabel')}</Text>
                <Text style={styles.withdrawSummaryValue}>
                  {accountDisplayLabel(
                    transferSourceAccount?.account_type || '',
                    transferSourceAccount?.display_name || '',
                    t,
                  )}
                </Text>
              </View>
              <View style={styles.withdrawSummaryRow}>
                <Text style={styles.withdrawSummaryLabel}>{t('assets.transferToLabel')}</Text>
                <Text style={styles.withdrawSummaryValue}>
                  {accountDisplayLabel(
                    transferTargetAccount?.account_type || '',
                    transferTargetAccount?.display_name || '',
                    t,
                  )}
                </Text>
              </View>
              <View style={styles.withdrawSummaryRow}>
                <Text style={styles.withdrawSummaryLabel}>{t('assets.transferSummaryAvailableAfter')}</Text>
                <Text style={styles.withdrawSummaryValue}>{formatUsd(transferAvailableAfter)} USDT</Text>
              </View>
              <View style={styles.withdrawSummaryRow}>
                <Text style={styles.withdrawSummaryLabel}>{t('assets.transferSummaryRoute')}</Text>
                <Text style={styles.withdrawSummaryValue}>{t('assets.transferSummaryInstant')}</Text>
              </View>
            </View>

            <View style={styles.withdrawRiskCard}>
              <View style={styles.withdrawRiskTitleRow}>
                <AppIcon name="shield" size={16} color={Colors.primary} />
                <Text style={styles.withdrawRiskTitle}>{t('assets.transferInfoTitle')}</Text>
              </View>
              <Text style={styles.withdrawRiskBody}>{t('assets.transferInfoBody')}</Text>
            </View>

            <View style={styles.modalActions}>
              <TouchableOpacity style={styles.modalSecondaryBtn} activeOpacity={0.85} onPress={() => setShowTransferModal(false)}>
                <Text style={styles.modalSecondaryBtnText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.modalPrimaryBtn, !canSubmitTransfer && styles.modalPrimaryBtnDisabled]}
                activeOpacity={0.85}
                onPress={() => void handleTransfer()}
                disabled={!canSubmitTransfer}
              >
                <Text style={styles.modalPrimaryBtnText}>
                  {transferring ? t('assets.transferSubmitting') : t('assets.transferConfirmAction')}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      <Modal visible={showRealtimeDriversModal} transparent animationType="fade" onRequestClose={() => setShowRealtimeDriversModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalCard}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>{t('assets.realtimeDriversTitle')}</Text>
                <Text style={styles.modalSubtitle}>{t('assets.realtimeDriversSubtitle')}</Text>
              </View>
              <TouchableOpacity style={styles.modalClose} activeOpacity={0.8} onPress={() => setShowRealtimeDriversModal(false)}>
                <AppIcon name="close" size={16} color={Colors.textSecondary} />
              </TouchableOpacity>
            </View>

            {realtimeDrivers.length ? (
              <ScrollView style={styles.realtimeDriversList} contentContainerStyle={styles.realtimeDriversListContent}>
                {realtimeDrivers.map((position) => {
                  const positive = (position.unrealized_pnl || 0) >= 0;
                  const sideColor = position.side === 'long' ? Colors.up : Colors.down;
                  return (
                    <View key={position.id} style={styles.realtimeDriverItem}>
                      <View style={styles.realtimeDriverTop}>
                        <View style={styles.realtimeDriverTitleWrap}>
                          <Text style={styles.realtimeDriverSymbol}>{toDisplaySymbol(position.symbol)}</Text>
                          <View style={[styles.realtimeDriverSideTag, { borderColor: sideColor + '55', backgroundColor: sideColor + '14' }]}>
                            <Text style={[styles.realtimeDriverSideTagText, { color: sideColor }]}>
                              {position.side === 'long' ? t('trading.longSide') : t('trading.shortSide')}
                            </Text>
                          </View>
                          {position.is_copy_trade ? (
                            <View style={styles.realtimeDriverCopyTag}>
                              <Text style={styles.realtimeDriverCopyTagText}>{t('trading.copyTrade')}</Text>
                            </View>
                          ) : null}
                        </View>
                        <Text style={[styles.realtimeDriverPnl, { color: positive ? Colors.up : Colors.down }]}>
                          {positive ? '+' : ''}{formatUsd(position.unrealized_pnl)} USDT
                        </Text>
                      </View>

                      <View style={styles.realtimeDriverMetrics}>
                        <Text style={styles.realtimeDriverMeta}>
                          {t('assets.realtimeDriverEntry')}: {formatUsd(position.entry_price)}
                        </Text>
                        <Text style={styles.realtimeDriverMeta}>
                          {t('assets.realtimeDriverCurrent')}: {formatUsd(position.current_price)}
                        </Text>
                        <Text style={styles.realtimeDriverMeta}>
                          {t('assets.realtimeDriverMargin')}: {formatUsd(position.margin_amount)}
                        </Text>
                        <Text style={styles.realtimeDriverMeta}>
                          ROE: {formatPercent((position.roe || 0) / 100)}
                        </Text>
                      </View>
                    </View>
                  );
                })}
              </ScrollView>
            ) : (
              <View style={styles.realtimeDriversEmpty}>
                <Text style={styles.emptyText}>{t('assets.realtimeDriversEmpty')}</Text>
              </View>
            )}

            <View style={styles.modalActions}>
              <TouchableOpacity style={styles.modalPrimaryBtn} activeOpacity={0.85} onPress={() => setShowRealtimeDriversModal(false)}>
                <Text style={styles.modalPrimaryBtnText}>{t('common.close')}</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
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
  centerState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.background,
    padding: 24,
    gap: 10,
  },
  centerStateTitle: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '800',
  },
  centerStateBody: {
    color: Colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 16,
  },
  headerContent: {
    flex: 1,
  },
  pageEyebrow: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1.6,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  pageTitle: {
    color: Colors.textActive,
    fontSize: 32,
    fontWeight: '800',
  },
  pageSubtitle: {
    marginTop: 6,
    color: Colors.textSecondary,
    fontSize: 14,
  },
  headerStatsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
    marginTop: 14,
  },
  headerStatPill: {
    minWidth: 92,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  headerStatLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    marginBottom: 6,
  },
  headerStatValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  refreshBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 12,
  },
  refreshBtnText: {
    color: Colors.primary,
    fontWeight: '700',
  },
  heroCard: {
    backgroundColor: Colors.surface,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 24,
    ...Shadows.card,
  },
  heroCardDesktop: {
    paddingVertical: 12,
    paddingHorizontal: 0,
    borderWidth: 0,
    backgroundColor: 'transparent',
    shadowOpacity: 0,
    elevation: 0,
  },
  heroLayout: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 24,
    flexWrap: 'wrap',
  },
  heroSummary: {
    flex: 1,
    minWidth: 280,
  },
  heroSummaryTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 16,
    marginBottom: 10,
  },
  heroValueBlock: {
    flex: 1,
    minWidth: 220,
  },
  heroActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    gap: 10,
    maxWidth: 520,
  },
  heroActionPill: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 18,
    paddingVertical: 11,
  },
  heroActionPillPrimary: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  heroActionPillText: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '800',
  },
  heroActionPillTextPrimary: {
    color: Colors.background,
  },
  heroLabel: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 1.2,
    marginBottom: 12,
  },
  heroCalendarBtn: {
    width: 44,
    height: 44,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    alignItems: 'center',
    justifyContent: 'center',
    alignSelf: 'flex-start',
    marginTop: 2,
  },
  heroCalendarSpacer: {
    width: 44,
    height: 44,
  },
  heroCurrencyPill: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  heroCurrencyText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  heroValue: {
    color: Colors.textActive,
    fontSize: 40,
    fontWeight: '800',
    marginBottom: 8,
  },
  heroApproxValue: {
    color: Colors.textSecondary,
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 10,
  },
  heroPnlRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 8,
  },
  realtimeRow: {
    marginTop: 14,
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 10,
  },
  realtimeBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderWidth: 1,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  realtimeDot: {
    width: 8,
    height: 8,
    borderRadius: 999,
  },
  realtimeBadgeText: {
    fontSize: 12,
    fontWeight: '800',
  },
  realtimeMeta: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  realtimeDriversBtn: {
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
  },
  realtimeDriversBtnText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '800',
  },
  heroPnlLabel: {
    color: Colors.textSecondary,
    fontSize: 14,
  },
  heroPnlValue: {
    fontSize: 16,
    fontWeight: '800',
  },
  heroPnlRate: {
    fontSize: 14,
    fontWeight: '700',
  },
  actionsRow: {
    gap: 12,
  },
  actionsRowDesktop: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  actionCard: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 15,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    minHeight: 78,
  },
  actionCardPrimary: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  actionIconWrap: {
    width: 36,
    height: 36,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  actionIconWrapPrimary: {
    backgroundColor: 'rgba(10, 12, 18, 0.14)',
    borderColor: 'rgba(10, 12, 18, 0.12)',
  },
  actionTextWrap: {
    flex: 1,
    gap: 4,
  },
  actionTitle: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '800',
  },
  actionTitlePrimary: {
    color: Colors.background,
  },
  actionBody: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  actionBodyPrimary: {
    color: 'rgba(10, 12, 18, 0.72)',
  },
  pendingHero: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    marginBottom: 16,
  },
  pendingHeroMetric: {
    flexGrow: 1,
    minWidth: 160,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 8,
  },
  pendingHeroValue: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
  },
  pendingList: {
    gap: 12,
  },
  pendingItem: {
    gap: 10,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
  },
  pendingCardHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 12,
  },
  pendingItemMain: {
    flex: 1,
    gap: 4,
  },
  pendingMeta: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  actionBtnText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '800',
  },
  actionBtnPrimaryText: {
    color: Colors.background,
    fontSize: 13,
    fontWeight: '800',
  },
  assetControlsCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 14,
    marginBottom: 16,
  },
  assetControlsCardDesktop: {
    backgroundColor: 'transparent',
    borderWidth: 0,
    paddingHorizontal: 0,
    paddingTop: 0,
    paddingBottom: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 20,
  },
  assetControlsPrimaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    flexWrap: 'wrap',
  },
  assetControlsSecondaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 10,
    flexWrap: 'wrap',
  },
  assetWorkbenchHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 16,
    flexWrap: 'wrap',
    marginBottom: 16,
  },
  assetWorkbenchTabs: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    flexWrap: 'wrap',
  },
  assetWorkbenchTab: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  assetWorkbenchTabActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  assetWorkbenchTabText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '800',
  },
  assetWorkbenchTabTextActive: {
    color: Colors.primary,
  },
  copyEntryBanner: {
    marginBottom: 16,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 16,
    paddingVertical: 14,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 16,
    flexWrap: 'wrap',
  },
  copyEntryBannerActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primary,
  },
  copyEntryBannerBody: {
    flex: 1,
    minWidth: 260,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  copyEntryBannerIcon: {
    width: 38,
    height: 38,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  copyEntryBannerTextWrap: {
    flex: 1,
    gap: 4,
  },
  copyEntryBannerTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    flexWrap: 'wrap',
  },
  copyEntryBannerTitle: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '900',
  },
  copyEntryBannerCount: {
    minWidth: 24,
    height: 24,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
    backgroundColor: Colors.primary,
  },
  copyEntryBannerCountText: {
    color: Colors.background,
    fontSize: 11,
    fontWeight: '900',
  },
  copyEntryBannerBodyText: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  copyEntryBannerAction: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.surface,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  copyEntryBannerActionText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '900',
  },
  assetCategoryRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  assetCategoryChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  assetCategoryChipActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  assetCategoryChipText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },
  assetCategoryChipTextActive: {
    color: Colors.primary,
  },
  assetSearchWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  assetSearchInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 14,
    padding: 0,
  },
  assetToggleRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  assetToggleChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  assetToggleChipActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  assetToggleChipText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },
  assetToggleChipTextActive: {
    color: Colors.primary,
  },
  assetList: {
    gap: 14,
  },
  assetTable: {
    gap: 0,
    borderRadius: 16,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
  },
  assetTableHead: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    backgroundColor: Colors.surface,
  },
  assetTableHeadCell: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '800',
  },
  assetTableRow: {
    flexDirection: 'row',
    alignItems: 'stretch',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  assetTableCell: {
    justifyContent: 'center',
  },
  assetTableAssetCell: {
    flex: 2.2,
    minWidth: 210,
  },
  assetTableAmountCell: {
    flex: 1.2,
    minWidth: 120,
    alignItems: 'flex-end',
  },
  assetTablePriceCell: {
    flex: 1.2,
    minWidth: 120,
    alignItems: 'flex-end',
  },
  assetTablePnlCell: {
    flex: 1.35,
    minWidth: 150,
    alignItems: 'flex-end',
  },
  assetTableAvailableCell: {
    flex: 1.3,
    minWidth: 130,
    alignItems: 'flex-end',
  },
  assetTableActionCell: {
    flex: 1.4,
    minWidth: 180,
    alignItems: 'flex-end',
  },
  assetTableValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
    textAlign: 'right',
  },
  assetTableSubValue: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 4,
    textAlign: 'right',
  },
  assetRow: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 14,
  },
  assetRowHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 12,
  },
  assetIdentity: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  assetIconWrap: {
    width: 38,
    height: 38,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.background,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  assetIconImage: {
    width: 22,
    height: 22,
    borderRadius: 999,
  },
  assetIdentityBody: {
    flex: 1,
    gap: 6,
  },
  assetCodeRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    gap: 8,
  },
  assetCode: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '900',
  },
  assetCategoryBadge: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  assetCategoryBadgeText: {
    color: Colors.primary,
    fontSize: 10,
    fontWeight: '800',
  },
  assetCategoryBadgeStock: {
    borderColor: '#7FA7FF44',
    backgroundColor: '#7FA7FF14',
  },
  assetCategoryBadgeTextStock: {
    color: '#9EB9FF',
  },
  assetDustBadge: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.warning + '44',
    backgroundColor: Colors.warning + '16',
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  assetDustBadgeText: {
    color: Colors.primaryLight,
    fontSize: 10,
    fontWeight: '800',
  },
  assetName: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  assetValuationBlock: {
    alignItems: 'flex-end',
    gap: 6,
  },
  assetValuation: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '900',
    textAlign: 'right',
  },
  assetValuationSub: {
    color: Colors.textMuted,
    fontSize: 11,
    textAlign: 'right',
  },
  assetMetricsRow: {
    flexDirection: 'row',
    gap: 10,
    flexWrap: 'wrap',
  },
  assetMetricCard: {
    flexGrow: 1,
    minWidth: 110,
    backgroundColor: Colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 4,
  },
  assetMetricLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  assetMetricValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '800',
  },
  assetActionRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  assetActionBtn: {
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surface,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  assetActionBtnPrimary: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primary,
  },
  assetActionBtnText: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '800',
  },
  assetActionBtnPrimaryText: {
    color: Colors.background,
    fontSize: 12,
    fontWeight: '900',
  },
  assetActionHint: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  assetEmptyState: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingVertical: 28,
    paddingHorizontal: 20,
  },
  assetEmptyTitle: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
    textAlign: 'center',
  },
  assetEmptyBody: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
    textAlign: 'center',
  },
  topGrid: {
    gap: 18,
  },
  topGridDesktop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  detailGrid: {
    gap: 18,
  },
  detailGridDesktop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  segmentedRow: {
    flexDirection: 'row',
    gap: 10,
  },
  segmentBtn: {
    flex: 1,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 12,
    paddingVertical: 12,
  },
  segmentBtnActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  segmentBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '800',
    textAlign: 'center',
  },
  segmentBtnTextActive: {
    color: Colors.primary,
  },
  panelCard: {
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    ...Shadows.card,
  },
  flexCard: {
    flex: 1.15,
  },
  sideCard: {
    flex: 0.85,
  },
  sectionHead: {
    marginBottom: 16,
    gap: 6,
  },
  sectionHeadRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    marginBottom: 16,
    gap: 12,
  },
  sectionHeadCompact: {
    gap: 6,
  },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '800',
  },
  sectionTitleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 12,
    flexWrap: 'wrap',
  },
  sectionHint: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 19,
  },
  rangeTabs: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  rangeTab: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  rangeTabActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  rangeTabText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },
  rangeTabTextActive: {
    color: Colors.primary,
  },
  calendarToolbar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    alignSelf: 'center',
    marginBottom: 12,
  },
  calendarNavBtn: {
    width: 32,
    height: 32,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
  },
  calendarMonthLabel: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '800',
    minWidth: 70,
    textAlign: 'center',
  },
  calendarSummaryRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    marginBottom: 14,
  },
  calendarSummaryMetric: {
    flexGrow: 1,
    minWidth: 150,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 12,
    paddingVertical: 12,
    gap: 6,
  },
  calendarSummaryLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
  },
  calendarSummaryValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '900',
  },
  calendarModalCard: {
    width: '100%',
    maxWidth: 560,
  },
  calendarDetailCard: {
    marginTop: 14,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 14,
    paddingVertical: 14,
    gap: 10,
  },
  calendarDetailDate: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '900',
  },
  calendarDetailRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  calendarDetailLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
  },
  calendarDetailValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '900',
  },
  viewAllLink: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '800',
  },
  readOnlyTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexWrap: 'wrap',
  },
  readOnlyBadge: {
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
  },
  readOnlyBadgeText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '800',
  },
  accountList: {
    gap: 14,
  },
  accountItem: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 14,
  },
  accountItemActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  accountTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  accountNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  accountIconWrap: {
    width: 34,
    height: 34,
    borderRadius: 10,
    backgroundColor: Colors.background,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    alignItems: 'center',
    justifyContent: 'center',
  },
  accountName: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  accountType: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    marginTop: 2,
  },
  virtualBadge: {
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: Colors.downDim,
    borderWidth: 1,
    borderColor: 'rgba(255,180,171,0.18)',
  },
  virtualBadgeText: {
    color: Colors.down,
    fontSize: 11,
    fontWeight: '800',
  },
  accountMetricsRow: {
    flexDirection: 'row',
    gap: 14,
    flexWrap: 'wrap',
  },
  // ── 账户概览 v2 ────────────────────────────────────────────────
  sectionHeadText: {
    flex: 1,
    minWidth: 180,
    gap: 6,
  },
  accountTotalBadge: {
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 10,
    alignItems: 'flex-end',
    gap: 4,
  },
  accountTotalLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  accountTotalValue: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '900',
  },
  accountTotalUnit: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  accountListV2: {
    gap: 12,
  },
  accountItemV2: {
    position: 'relative',
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 16,
    paddingVertical: 14,
    gap: 12,
    overflow: 'hidden',
  },
  accountItemV2Active: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  accountActiveBar: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    width: 3,
    backgroundColor: Colors.primary,
  },
  accountRowV2: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  accountIconV2: {
    width: 38,
    height: 38,
    borderRadius: 12,
    backgroundColor: Colors.background,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    alignItems: 'center',
    justifyContent: 'center',
  },
  accountIconV2Futures: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  accountNameV2: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '800',
  },
  accountTypeV2: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 1.2,
    marginTop: 2,
  },
  accountEquityRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    gap: 8,
  },
  accountEquityValue: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '900',
    letterSpacing: -0.3,
  },
  accountEquityUnit: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  accountPnlChip: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
  },
  accountPnlChipText: {
    fontSize: 12,
    fontWeight: '800',
  },
  accountMetaRowV2: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  accountMetaItem: {
    flex: 1,
    gap: 4,
  },
  accountMetaValue: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '700',
  },
  accountMetaDivider: {
    width: 1,
    alignSelf: 'stretch',
    backgroundColor: Colors.border,
    opacity: 0.7,
  },
  // ── 跟单资金 v2 ────────────────────────────────────────────────
  copyHeroCard: {
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    borderRadius: 16,
    paddingHorizontal: 16,
    paddingVertical: 16,
    gap: 8,
    marginBottom: 14,
  },
  copyHeroLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },
  copyHeroValue: {
    color: Colors.textActive,
    fontSize: 28,
    fontWeight: '900',
    letterSpacing: -0.4,
  },
  copyHeroUnit: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '700',
  },
  copyHeroHint: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  copyHeroMetaRow: {
    marginTop: 6,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  copyHeroMetaItem: {
    flex: 1,
    gap: 4,
  },
  copyHeroMetaValue: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  copyHeroDivider: {
    width: 1,
    height: 22,
    backgroundColor: Colors.border,
  },
  copyItemsV2: {
    gap: 10,
  },
  copyItemV2: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 14,
    paddingVertical: 12,
    gap: 10,
  },
  copyItemV2Active: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  copyItemV2Head: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  copyItemV2NameRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    minWidth: 0,
  },
  copyItemV2Chevron: {
    color: Colors.textMuted,
    fontSize: 22,
    fontWeight: '800',
    lineHeight: 22,
    marginLeft: 4,
  },
  copyItemV2PnlCol: {
    alignItems: 'flex-end',
    gap: 2,
  },
  copyItemV2Pnl: {
    fontSize: 14,
    fontWeight: '900',
    letterSpacing: -0.2,
  },
  copyItemV2Roi: {
    fontSize: 11,
    fontWeight: '800',
  },
  copyStatusPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    backgroundColor: Colors.background,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
  },
  copyStatusDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.up,
  },
  copyStatusPillText: {
    color: Colors.textSecondary,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.4,
  },
  copyItemV2MetaRow: {
    flexDirection: 'row',
    gap: 10,
  },
  copyItemV2MetaCell: {
    flex: 1,
    gap: 3,
  },
  copyItemV2MetaValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '800',
  },
  metricBlock: {
    minWidth: 120,
    gap: 6,
  },
  metricLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  metricValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  accountSubRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
    flexWrap: 'wrap',
  },
  accountSubText: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  accountVirtualHint: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },
  copySummaryTotals: {
    gap: 12,
    marginBottom: 16,
  },
  copySummaryMetric: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
  },
  copyStatsRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 16,
  },
  copyStatChip: {
    flex: 1,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    alignItems: 'center',
    gap: 4,
  },
  copyStatValue: {
    color: Colors.primary,
    fontSize: 22,
    fontWeight: '800',
  },
  copyStatLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    textAlign: 'center',
  },
  copyItems: {
    gap: 12,
  },
  copyWorkspace: {
    gap: 18,
  },
  copyOverviewGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  copyOverviewCard: {
    flexGrow: 1,
    minWidth: 180,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 8,
  },
  copyOverviewValue: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '800',
  },
  copyOverviewSub: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  copyWorkspaceBody: {
    gap: 18,
  },
  copyWorkspaceBodyDesktop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  copyPoolsPanel: {
    flex: 0.9,
    gap: 12,
  },
  copyActivityPanel: {
    flex: 1.1,
    gap: 12,
  },
  copyItem: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 6,
  },
  copyItemActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  copyItemTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
  },
  copyTraderName: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '800',
  },
  copyTraderStatus: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '700',
  },
  copyTraderMeta: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  copyPoolBottomRow: {
    marginTop: 4,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  copyPoolMetaGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    marginBottom: 4,
  },
  copyPoolMetaCard: {
    flexGrow: 1,
    minWidth: 150,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 4,
  },
  copyPoolMetaValue: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  copyPoolPnl: {
    fontSize: 14,
    fontWeight: '800',
  },
  copyPoolReturn: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
  },
  copySelectedSummaryLine: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    marginBottom: 12,
  },
  copySelectedSummaryText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '700',
  },
  copyActivitySummaryRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  copyActivityList: {
    gap: 12,
  },
  copyActivityItem: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 10,
  },
  copyActivityItemHead: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  copyActivitySymbol: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  copyActivityMeta: {
    marginTop: 4,
    color: Colors.textSecondary,
    fontSize: 12,
  },
  copyActivityPnl: {
    fontSize: 16,
    fontWeight: '800',
    textAlign: 'right',
  },
  copyActivityMetrics: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  copyActivityMetric: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  copyHistoryCountText: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
    textAlign: 'right',
    marginTop: 4,
  },
  detailBody: {
    gap: 16,
  },
  detailHero: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
    alignItems: 'flex-start',
  },
  detailHeroTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
  },
  detailHeroSub: {
    marginTop: 6,
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '700',
  },
  detailMetricGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  detailMetricCard: {
    minWidth: 150,
    flexGrow: 1,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 8,
  },
  detailMetricValue: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
  },
  detailNoteCard: {
    backgroundColor: Colors.background,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 8,
  },
  detailNoteText: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
    lineHeight: 20,
  },
  detailNoteMuted: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  transferBalancesRow: {
    flexDirection: 'row',
    gap: 12,
    flexWrap: 'wrap',
  },
  transferBalanceCard: {
    flexGrow: 1,
    minWidth: 160,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 6,
  },
  transferHeroCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 18,
    gap: 8,
  },
  transferHeroTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 12,
  },
  transferHeroValue: {
    color: Colors.textActive,
    fontSize: 28,
    fontWeight: '900',
    letterSpacing: -0.8,
  },
  transferHeroHint: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  transferRouteSection: {
    gap: 10,
  },
  transferRouteCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 6,
  },
  transferRouteCardActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  transferRouteHead: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  transferRouteLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  transferRoutePill: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.background,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  transferRoutePillActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primary + '18',
  },
  transferRoutePillText: {
    color: Colors.textSecondary,
    fontSize: 10,
    fontWeight: '800',
  },
  transferRoutePillTextActive: {
    color: Colors.primary,
  },
  transferRouteValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  transferRouteMeta: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  transferSwapButton: {
    alignSelf: 'center',
    width: 40,
    height: 40,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
  transferSwapButtonText: {
    color: Colors.primary,
    fontSize: 18,
    fontWeight: '800',
  },
  transferAmountSection: {
    gap: 12,
  },
  txList: {
    gap: 12,
  },
  txItem: {
    gap: 10,
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
    gap: 4,
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
  statusBadgeText: {
    color: Colors.textSecondary,
    fontSize: 11,
    fontWeight: '700',
  },
  txNote: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  txAmountHero: {
    fontSize: 18,
    fontWeight: '900',
    textAlign: 'right',
  },
  txAmount: {
    fontSize: 14,
    fontWeight: '800',
  },
  txTime: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
  },
  errorCard: {
    backgroundColor: Colors.downDim,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,180,171,0.22)',
    padding: 16,
    gap: 6,
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
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(5,6,13,0.7)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  modalCard: {
    width: '100%',
    maxWidth: 520,
    backgroundColor: Colors.surface,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    gap: 18,
    ...Shadows.card,
  },
  withdrawModalCard: {
    maxWidth: 560,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
    alignItems: 'flex-start',
  },
  modalTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
  },
  modalSubtitle: {
    marginTop: 6,
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 19,
  },
  modalClose: {
    width: 34,
    height: 34,
    borderRadius: 17,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceAlt,
  },
  depositInfoCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 6,
  },
  depositInfoLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  depositInfoValue: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
  },
  depositInfoHint: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  withdrawScroll: {
    maxHeight: 560,
  },
  withdrawScrollContent: {
    gap: 16,
    paddingRight: 2,
  },
  withdrawHeroCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 10,
  },
  withdrawHeroTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  withdrawAssetPill: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  withdrawAssetPillText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '800',
  },
  withdrawSection: {
    gap: 12,
  },
  withdrawSectionTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '800',
  },
  withdrawAddressInput: {
    minHeight: 92,
  },
  withdrawAddressHint: {
    color: Colors.textMuted,
    fontSize: 11,
    lineHeight: 17,
    marginTop: 6,
  },
  withdrawAmountHead: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  withdrawMaxBtn: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  withdrawMaxBtnText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '800',
  },
  withdrawAmountCard: {
    minHeight: 64,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 14,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  withdrawAmountInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    paddingVertical: 0,
  },
  withdrawAmountSuffix: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '800',
  },
  withdrawPercentRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  withdrawPercentChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  withdrawPercentChipText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },
  withdrawSummaryCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 12,
  },
  withdrawSummaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  withdrawSummaryRowWrap: {
    alignItems: 'flex-start',
  },
  withdrawSummaryLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
    flexShrink: 0,
  },
  withdrawSummaryValue: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
    textAlign: 'right',
    flexShrink: 1,
  },
  withdrawSummaryPath: {
    color: Colors.primaryLight,
    fontSize: 13,
    fontWeight: '700',
    flex: 1,
    textAlign: 'right',
    lineHeight: 18,
  },
  withdrawRiskCard: {
    backgroundColor: Colors.warning + '12',
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.warning + '33',
    padding: 16,
    gap: 10,
  },
  withdrawRiskTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  withdrawRiskTitle: {
    color: Colors.primaryLight,
    fontSize: 13,
    fontWeight: '800',
  },
  withdrawRiskBody: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },
  depositAddressCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 12,
  },
  depositAddressLoadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  depositAddressDisplayCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 12,
    paddingVertical: 12,
    overflow: 'hidden',
  },
  depositAddressScroll: {
    width: '100%',
  },
  depositAddressScrollContent: {
    minWidth: '100%',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 4,
  },
  depositAddressSingleLine: {
    fontWeight: '800',
    lineHeight: 22,
    letterSpacing: 0.2,
    textAlign: 'center',
  },
  depositAddressHighlight: {
    color: Colors.primary,
    fontWeight: '900',
  },
  depositAddressMuted: {
    color: Colors.textSecondary,
    fontWeight: '700',
  },
  depositMemoText: {
    color: Colors.warning,
    fontSize: 13,
    fontWeight: '600',
  },
  optionWrap: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  selectorCard: {
    gap: 10,
  },
  dropdownTrigger: {
    minHeight: 56,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 14,
    paddingVertical: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  dropdownValueWrap: {
    flex: 1,
    gap: 4,
  },
  dropdownValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  dropdownMeta: {
    color: Colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
  },
  dropdownCaret: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '900',
  },
  dropdownMenu: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    padding: 8,
    gap: 6,
  },
  dropdownItem: {
    minHeight: 44,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  dropdownItemActive: {
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  dropdownItemText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  dropdownItemTextActive: {
    color: Colors.primary,
  },
  networkCard: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    padding: 12,
  },
  optionChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  optionChipActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  optionChipText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
  },
  optionChipTextActive: {
    color: Colors.primary,
  },
  depositQrCard: {
    alignSelf: 'center',
    backgroundColor: '#FFFFFF',
    borderRadius: 30,
    padding: 20,
    marginTop: 2,
    marginBottom: 2,
  },
  depositQrHint: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'center',
  },
  depositHistoryCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 10,
  },
  depositHistoryList: {
    gap: 10,
  },
  depositHistoryItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 12,
  },
  depositHistoryMain: {
    flex: 1,
    gap: 4,
  },
  depositHistorySide: {
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    gap: 6,
  },
  depositHistoryMeta: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '600',
  },
  inputGroup: {
    gap: 8,
  },
  inputLabel: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  input: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.background,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: Colors.textActive,
    fontSize: 15,
  },
  modalActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 10,
    flexWrap: 'wrap',
  },
  realtimeDriversList: {
    maxHeight: 420,
  },
  realtimeDriversListContent: {
    gap: 12,
    paddingBottom: 4,
  },
  realtimeDriverItem: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 12,
  },
  realtimeDriverTop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  realtimeDriverTitleWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexWrap: 'wrap',
    flex: 1,
  },
  realtimeDriverSymbol: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  realtimeDriverSideTag: {
    borderWidth: 1,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 999,
  },
  realtimeDriverSideTagText: {
    fontSize: 11,
    fontWeight: '800',
  },
  realtimeDriverCopyTag: {
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 999,
  },
  realtimeDriverCopyTagText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '800',
  },
  realtimeDriverPnl: {
    fontSize: 16,
    fontWeight: '800',
  },
  realtimeDriverMetrics: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  realtimeDriverMeta: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  realtimeDriversEmpty: {
    paddingVertical: 20,
  },
  modalSecondaryBtn: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 16,
    paddingVertical: 11,
  },
  modalSecondaryBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '800',
  },
  modalPrimaryBtn: {
    borderRadius: 14,
    backgroundColor: Colors.primary,
    borderWidth: 1,
    borderColor: Colors.primary,
    paddingHorizontal: 16,
    paddingVertical: 11,
  },
  modalPrimaryBtnDisabled: {
    opacity: 0.45,
  },
  modalPrimaryBtnText: {
    color: Colors.background,
    fontSize: 13,
    fontWeight: '800',
  },
});
