import { create } from 'zustand';
import {
  getAssetsOverview,
  getAssetsPnlCalendar,
  type AssetChangePoint,
  type AssetPnlCalendarResponse,
  type AssetRangeKey,
  type AssetsOverviewResponse,
} from '../api/assetsApi';
import { listPositions, type AccountInfoResponse, type PositionResponse } from '../api/tradingApi';
import { tradingWs } from '../websocket/tradingWs';

type FetchOpts = {
  silent?: boolean;
};

function recomputeTodayPnlRate(totalEquity: number, todayPnl: number) {
  const base = totalEquity - todayPnl;
  return base > 0 ? todayPnl / Math.abs(base) : 0;
}

function patchChangeSeries(points: AssetChangePoint[], totalEquity: number) {
  if (!points.length) return points;
  const next = [...points];
  const last = next[next.length - 1];
  next[next.length - 1] = { ...last, equity: totalEquity };
  return next;
}

function patchOverviewFromAccount(
  overview: AssetsOverviewResponse | null,
  account: AccountInfoResponse,
): AssetsOverviewResponse | null {
  if (!overview) return overview;

  const previousFutures = overview.accounts.find((item) => item.account_type === 'futures');
  const previousEquity = previousFutures?.equity || 0;
  const previousUnrealized = previousFutures?.unrealized_pnl || 0;

  const nextAccounts = overview.accounts.some((item) => item.account_type === 'futures')
    ? overview.accounts.map((item) =>
        item.account_type === 'futures'
          ? {
              ...item,
              equity: account.equity,
              available: account.available,
              frozen: account.frozen,
              unrealized_pnl: account.unrealized_pnl,
              margin_used: account.margin_used,
            }
          : item,
      )
    : [
        ...overview.accounts,
        {
          account_type: 'futures',
          display_name: '合约账户',
          equity: account.equity,
          available: account.available,
          frozen: account.frozen,
          unrealized_pnl: account.unrealized_pnl,
          margin_used: account.margin_used,
        },
      ];

  const totalEquity = overview.total_equity - previousEquity + account.equity;
  return {
    ...overview,
    total_equity: totalEquity,
    today_pnl: overview.today_pnl,
    today_pnl_rate: recomputeTodayPnlRate(totalEquity, overview.today_pnl),
    accounts: nextAccounts,
    change_series: patchChangeSeries(overview.change_series || [], totalEquity),
  };
}

function buildLiveOverview(
  overview: AssetsOverviewResponse | null,
  positions: PositionResponse[],
  positionsHydrated: boolean,
): AssetsOverviewResponse | null {
  if (!overview || !positionsHydrated) {
    return overview;
  }

  const futuresAccount = overview.accounts.find((item) => item.account_type === 'futures');
  if (!futuresAccount) {
    return overview;
  }

  // 合约账户卡片只反映"自交易"（is_copy_trade=false）的浮动盈亏与已用保证金。
  // 跟单仓位的浮亏/保证金独立归入"跟单账户"卡片，绝对不能再叠到合约账户上，
  // 否则会把跟单的亏损算进合约账户，显示出异常的负权益。
  const selfPositions = positions.filter((item) => !item.is_copy_trade);
  const copyPositions = positions.filter((item) => item.is_copy_trade);
  const liveUnrealizedPnl = selfPositions.reduce((sum, item) => sum + (item.unrealized_pnl || 0), 0);
  const liveMarginUsed = selfPositions.reduce((sum, item) => sum + (item.margin_amount || 0), 0);
  const liveCopyUnrealizedPnl = copyPositions.reduce((sum, item) => sum + (item.unrealized_pnl || 0), 0);
  const baseUnrealizedPnl = futuresAccount.unrealized_pnl || 0;
  const baseCopyUnrealizedPnl = overview.copy_summary?.total_unrealized_pnl || 0;
  const unrealizedDelta = liveUnrealizedPnl - baseUnrealizedPnl;
  const copyUnrealizedDelta = liveCopyUnrealizedPnl - baseCopyUnrealizedPnl;
  const liveFuturesEquity = futuresAccount.equity + unrealizedDelta;
  // 总权益 = 原 total_equity + 自交易浮盈变化 + 跟单浮盈变化。
  // 跟单浮亏只通过这一项进入总权益，绝对不从 futures 侧叠加。
  const totalEquity = overview.total_equity + unrealizedDelta + copyUnrealizedDelta;
  const todayPnl = overview.today_pnl + liveUnrealizedPnl + liveCopyUnrealizedPnl;

  return {
    ...overview,
    total_equity: totalEquity,
    today_pnl: todayPnl,
    today_pnl_rate: recomputeTodayPnlRate(totalEquity, todayPnl),
    accounts: overview.accounts.map((item) =>
      item.account_type === 'futures'
        ? {
            ...item,
            equity: liveFuturesEquity,
            unrealized_pnl: liveUnrealizedPnl,
            margin_used: liveMarginUsed,
          }
        : item,
    ),
    copy_summary: overview.copy_summary
      ? { ...overview.copy_summary, total_unrealized_pnl: liveCopyUnrealizedPnl }
      : overview.copy_summary,
    change_series: patchChangeSeries(overview.change_series || [], totalEquity),
  };
}

function mergePosition(statePositions: PositionResponse[], incoming: PositionResponse) {
  const index = statePositions.findIndex((item) => item.id === incoming.id);
  if (index < 0) {
    return [incoming, ...statePositions];
  }

  const current = statePositions[index];
  const next = [...statePositions];
  next[index] = {
    ...current,
    ...incoming,
    is_copy_trade: current.is_copy_trade ?? incoming.is_copy_trade,
    source_position_id: current.source_position_id ?? incoming.source_position_id,
    source_trader_id: current.source_trader_id ?? incoming.source_trader_id,
    copy_trading_id: current.copy_trading_id ?? incoming.copy_trading_id,
    open_fee: incoming.open_fee ?? current.open_fee,
    close_fee: incoming.close_fee ?? current.close_fee,
    realized_pnl: incoming.realized_pnl ?? current.realized_pnl,
  };
  return next;
}

interface AssetsState {
  overview: AssetsOverviewResponse | null;
  liveOverview: AssetsOverviewResponse | null;
  range: AssetRangeKey;
  calendar: AssetPnlCalendarResponse | null;
  calendarLoading: boolean;
  calendarYear: number;
  calendarMonth: number;
  positions: PositionResponse[];
  positionsHydrated: boolean;
  lastRealtimeAt: number | null;
  wsConnected: boolean;
  loading: boolean;
  refreshing: boolean;
  error: string | null;
  realtimeActive: boolean;
  fetchOverview: (opts?: FetchOpts, rangeOverride?: AssetRangeKey) => Promise<void>;
  setRange: (range: AssetRangeKey) => void;
  fetchCalendar: (year?: number, month?: number) => Promise<void>;
  fetchPositions: (opts?: FetchOpts) => Promise<void>;
  applyPositionUpdate: (position: PositionResponse) => void;
  removePosition: (positionID: string) => void;
  applyAccountUpdate: (account: AccountInfoResponse) => void;
  connectRealtime: () => void;
  disconnectRealtime: () => void;
  reset: () => void;
}

export const useAssetsStore = create<AssetsState>((set, get) => ({
  overview: null,
  liveOverview: null,
  range: '7d',
  calendar: null,
  calendarLoading: false,
  calendarYear: new Date().getFullYear(),
  calendarMonth: new Date().getMonth() + 1,
  positions: [],
  positionsHydrated: false,
  lastRealtimeAt: null,
  wsConnected: false,
  loading: false,
  refreshing: false,
  error: null,
  realtimeActive: false,

  fetchOverview: async (opts, rangeOverride) => {
    const silent = !!opts?.silent;
    set((state) => ({
      loading: silent ? state.loading : !state.overview,
      refreshing: silent ? true : !!state.overview,
      error: null,
    }));

    try {
      const nextRange = rangeOverride || get().range;
      const overview = await getAssetsOverview(nextRange);
      set((state) => ({
        range: nextRange,
        overview,
        liveOverview: buildLiveOverview(overview, state.positions, state.positionsHydrated),
        lastRealtimeAt: Date.now(),
        loading: false,
        refreshing: false,
        error: null,
      }));
    } catch (e: any) {
      set({
        loading: false,
        refreshing: false,
        error: e?.response?.data?.error || e?.message || 'Failed to load assets overview',
      });
    }
  },

  setRange: (range) => {
    set({ range });
  },

  fetchCalendar: async (year, month) => {
    const now = new Date();
    const targetYear = year || get().calendarYear || now.getFullYear();
    const targetMonth = month || get().calendarMonth || now.getMonth() + 1;
    set({ calendarLoading: true, calendarYear: targetYear, calendarMonth: targetMonth });
    try {
      const calendar = await getAssetsPnlCalendar(targetYear, targetMonth);
      set({ calendar, calendarLoading: false, calendarYear: targetYear, calendarMonth: targetMonth });
    } catch (e: any) {
      set({
        calendarLoading: false,
        error: e?.response?.data?.error || e?.message || 'Failed to load pnl calendar',
      });
    }
  },

  fetchPositions: async (_opts) => {
    try {
      const positions = await listPositions();
      set((state) => ({
        positions,
        positionsHydrated: true,
        lastRealtimeAt: Date.now(),
        liveOverview: buildLiveOverview(state.overview, positions, true),
      }));
    } catch (e) {
      console.warn('[AssetsStore] fetchPositions error:', e);
    }
  },

  applyPositionUpdate: (position) => {
    let inserted = false;
    set((state) => {
      const exists = state.positions.some((item) => item.id === position.id);
      inserted = !exists;
      const positions = mergePosition(state.positions, position);
      return {
        positions,
        positionsHydrated: true,
        lastRealtimeAt: Date.now(),
        liveOverview: buildLiveOverview(state.overview, positions, true),
      };
    });
    if (inserted) {
      scheduleAssetsRealtimeSync({ includePositions: false });
    }
  },

  removePosition: (positionID) => {
    set((state) => {
      const positions = state.positions.filter((item) => item.id !== positionID);
      return {
        positions,
        positionsHydrated: true,
        lastRealtimeAt: Date.now(),
        liveOverview: buildLiveOverview(state.overview, positions, true),
      };
    });
  },

  applyAccountUpdate: (account) => {
    set((state) => {
      const overview = patchOverviewFromAccount(state.overview, account);
      return {
        overview,
        lastRealtimeAt: Date.now(),
        liveOverview: buildLiveOverview(overview, state.positions, state.positionsHydrated),
      };
    });
  },

  connectRealtime: () => {
    assetsRealtimeSubscribers += 1;
    bindAssetsRealtime();
    tradingWs.connect();
    set({ realtimeActive: true, wsConnected: tradingWs.connected });
    void get().fetchPositions({ silent: true });
    void get().fetchOverview({ silent: true });
  },

  disconnectRealtime: () => {
    assetsRealtimeSubscribers = Math.max(0, assetsRealtimeSubscribers - 1);
    if (assetsRealtimeSubscribers === 0) {
      unbindAssetsRealtime();
      clearAssetsRealtimeTimers();
    }
    set({ realtimeActive: assetsRealtimeSubscribers > 0, wsConnected: assetsRealtimeSubscribers > 0 && tradingWs.connected });
  },

  reset: () => {
    set({
      overview: null,
      liveOverview: null,
      range: '7d',
      calendar: null,
      calendarLoading: false,
      calendarYear: new Date().getFullYear(),
      calendarMonth: new Date().getMonth() + 1,
      positions: [],
      positionsHydrated: false,
      lastRealtimeAt: null,
      wsConnected: false,
      loading: false,
      refreshing: false,
      error: null,
      realtimeActive: false,
    });
  },
}));

let assetsRealtimeSubscribers = 0;
let assetsRealtimeBound = false;
let overviewRefreshTimer: ReturnType<typeof setTimeout> | null = null;
let positionsRefreshTimer: ReturnType<typeof setTimeout> | null = null;

let positionUpdateHandler: ((data: PositionResponse) => void) | null = null;
let positionClosedHandler: ((data: PositionResponse) => void) | null = null;
let positionLiquidatedHandler: ((data: PositionResponse) => void) | null = null;
let balanceUpdateHandler: ((data: { balance: number; frozen: number }) => void) | null = null;
let accountUpdateHandler: ((data: AccountInfoResponse) => void) | null = null;
let orderFilledHandler: (() => void) | null = null;
let copyTradeOpenedHandler: (() => void) | null = null;
let copyTradeClosedHandler: (() => void) | null = null;
let reconnectHandler: (() => void) | null = null;

function clearAssetsRealtimeTimers() {
  if (overviewRefreshTimer) {
    clearTimeout(overviewRefreshTimer);
    overviewRefreshTimer = null;
  }
  if (positionsRefreshTimer) {
    clearTimeout(positionsRefreshTimer);
    positionsRefreshTimer = null;
  }
}

function scheduleAssetsRealtimeSync(opts?: { includePositions?: boolean }) {
  if (!overviewRefreshTimer) {
    overviewRefreshTimer = setTimeout(() => {
      overviewRefreshTimer = null;
      void useAssetsStore.getState().fetchOverview({ silent: true });
    }, 180);
  }

  if (opts?.includePositions && !positionsRefreshTimer) {
    positionsRefreshTimer = setTimeout(() => {
      positionsRefreshTimer = null;
      void useAssetsStore.getState().fetchPositions({ silent: true });
    }, 180);
  }
}

function bindAssetsRealtime() {
  if (assetsRealtimeBound) return;

  positionUpdateHandler = (data) => {
    useAssetsStore.setState({ wsConnected: true });
    useAssetsStore.getState().applyPositionUpdate(data);
  };

  positionClosedHandler = (data) => {
    useAssetsStore.setState({ wsConnected: true, lastRealtimeAt: Date.now() });
    useAssetsStore.getState().removePosition(data.id);
    scheduleAssetsRealtimeSync();
  };

  positionLiquidatedHandler = (data) => {
    useAssetsStore.setState({ wsConnected: true, lastRealtimeAt: Date.now() });
    useAssetsStore.getState().removePosition(data.id);
    scheduleAssetsRealtimeSync();
  };

  balanceUpdateHandler = () => {
    useAssetsStore.setState({ wsConnected: true, lastRealtimeAt: Date.now() });
    scheduleAssetsRealtimeSync();
  };

  accountUpdateHandler = (data) => {
    useAssetsStore.setState({ wsConnected: true });
    useAssetsStore.getState().applyAccountUpdate(data);
  };

  orderFilledHandler = () => {
    useAssetsStore.setState({ wsConnected: true, lastRealtimeAt: Date.now() });
    scheduleAssetsRealtimeSync({ includePositions: true });
  };

  copyTradeOpenedHandler = () => {
    useAssetsStore.setState({ wsConnected: true, lastRealtimeAt: Date.now() });
    scheduleAssetsRealtimeSync({ includePositions: true });
  };

  copyTradeClosedHandler = () => {
    useAssetsStore.setState({ wsConnected: true, lastRealtimeAt: Date.now() });
    scheduleAssetsRealtimeSync({ includePositions: true });
  };

  reconnectHandler = () => {
    useAssetsStore.setState({ wsConnected: true, lastRealtimeAt: Date.now() });
    scheduleAssetsRealtimeSync({ includePositions: true });
  };

  tradingWs.on('position_update', positionUpdateHandler);
  tradingWs.on('position_closed', positionClosedHandler);
  tradingWs.on('position_liquidated', positionLiquidatedHandler);
  tradingWs.on('balance_update', balanceUpdateHandler);
  tradingWs.on('account_update', accountUpdateHandler);
  tradingWs.on('order_filled', orderFilledHandler);
  tradingWs.on('copy_trade_opened', copyTradeOpenedHandler);
  tradingWs.on('copy_trade_closed', copyTradeClosedHandler);
  tradingWs.onReconnect(reconnectHandler);

  useAssetsStore.setState({ wsConnected: tradingWs.connected });
  assetsRealtimeBound = true;
}

function unbindAssetsRealtime() {
  if (!assetsRealtimeBound) return;

  if (positionUpdateHandler) tradingWs.off('position_update', positionUpdateHandler);
  if (positionClosedHandler) tradingWs.off('position_closed', positionClosedHandler);
  if (positionLiquidatedHandler) tradingWs.off('position_liquidated', positionLiquidatedHandler);
  if (balanceUpdateHandler) tradingWs.off('balance_update', balanceUpdateHandler);
  if (accountUpdateHandler) tradingWs.off('account_update', accountUpdateHandler);
  if (orderFilledHandler) tradingWs.off('order_filled', orderFilledHandler);
  if (copyTradeOpenedHandler) tradingWs.off('copy_trade_opened', copyTradeOpenedHandler);
  if (copyTradeClosedHandler) tradingWs.off('copy_trade_closed', copyTradeClosedHandler);
  if (reconnectHandler) tradingWs.offReconnect(reconnectHandler);

  positionUpdateHandler = null;
  positionClosedHandler = null;
  positionLiquidatedHandler = null;
  balanceUpdateHandler = null;
  accountUpdateHandler = null;
  orderFilledHandler = null;
  copyTradeOpenedHandler = null;
  copyTradeClosedHandler = null;
  reconnectHandler = null;
  useAssetsStore.setState({ wsConnected: false });
  assetsRealtimeBound = false;
}
