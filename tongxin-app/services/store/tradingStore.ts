import { create } from 'zustand';
import {
  placeOrder as apiPlaceOrder,
  listOrders,
  cancelOrder as apiCancelOrder,
  listPositions,
  listPositionHistory,
  closePosition as apiClosePosition,
  getAccount,
  deposit as apiDeposit,
  getWallet,
  type PlaceOrderRequest,
  type OrderResponse,
  type PositionResponse,
  type AccountInfoResponse,
  type WalletResponse,
} from '../api/tradingApi';
import { tradingWs } from '../websocket/tradingWs';

interface TradingState {
  positions: PositionResponse[];
  positionHistory: PositionResponse[];
  pendingOrders: OrderResponse[];
  orderHistory: OrderResponse[];
  account: AccountInfoResponse | null;
  wallet: WalletResponse | null;
  loading: boolean;
  wsConnected: boolean;

  // Actions
  fetchPositions: () => Promise<void>;
  fetchPositionHistory: () => Promise<void>;
  fetchPendingOrders: () => Promise<void>;
  fetchOrderHistory: () => Promise<void>;
  fetchAccount: () => Promise<void>;
  fetchWallet: () => Promise<void>;
  placeOrder: (req: PlaceOrderRequest) => Promise<OrderResponse>;
  cancelOrder: (id: string) => Promise<void>;
  closePosition: (id: string) => Promise<void>;
  deposit: (amount: number) => Promise<void>;
  connectWs: () => void;
  disconnectWs: () => void;
}

export const useTradingStore = create<TradingState>((set, get) => ({
  positions: [],
  positionHistory: [],
  pendingOrders: [],
  orderHistory: [],
  account: null,
  wallet: null,
  loading: false,
  wsConnected: false,

  fetchPositions: async () => {
    try {
      const positions = await listPositions();
      set({ positions });
    } catch (e) {
      console.warn('[TradingStore] fetchPositions error:', e);
    }
  },

  fetchPositionHistory: async () => {
    try {
      const positionHistory = await listPositionHistory();
      set({ positionHistory });
    } catch (e) {
      console.warn('[TradingStore] fetchPositionHistory error:', e);
    }
  },

  fetchPendingOrders: async () => {
    try {
      const orders = await listOrders('pending');
      set({ pendingOrders: orders });
    } catch (e) {
      console.warn('[TradingStore] fetchPendingOrders error:', e);
    }
  },

  fetchOrderHistory: async () => {
    try {
      const orders = await listOrders('all');
      set({ orderHistory: orders.filter((o) => o.status !== 'pending') });
    } catch (e) {
      console.warn('[TradingStore] fetchOrderHistory error:', e);
    }
  },

  fetchAccount: async () => {
    try {
      const account = await getAccount();
      set({ account });
    } catch (e) {
      console.warn('[TradingStore] fetchAccount error:', e);
    }
  },

  fetchWallet: async () => {
    try {
      const wallet = await getWallet();
      set({ wallet });
    } catch (e) {
      console.warn('[TradingStore] fetchWallet error:', e);
    }
  },

  placeOrder: async (req: PlaceOrderRequest) => {
    const order = await apiPlaceOrder(req);
    // Refresh data after placing order
    get().fetchPositions();
    get().fetchPendingOrders();
    get().fetchAccount();
    return order;
  },

  cancelOrder: async (id: string) => {
    await apiCancelOrder(id);
    get().fetchPendingOrders();
    get().fetchAccount();
  },

  closePosition: async (id: string) => {
    try {
      await apiClosePosition(id);
    } catch (e: any) {
      // Position may already be closed (e.g. by copy-trade auto-close or TP/SL)
      console.warn('[closePosition] error:', e?.response?.data || e.message);
    }
    get().fetchPositions();
    get().fetchPositionHistory();
    get().fetchAccount();
  },

  deposit: async (amount: number) => {
    await apiDeposit(amount);
    get().fetchWallet();
    get().fetchAccount();
  },

  connectWs: () => {
    // Register WebSocket event handlers
    tradingWs.on('order_filled', (data: OrderResponse) => {
      get().fetchPositions();
      get().fetchPendingOrders();
    });

    tradingWs.on('order_created', (data: OrderResponse) => {
      set((state) => ({
        pendingOrders: [data, ...state.pendingOrders],
      }));
    });

    tradingWs.on('order_cancelled', (data: OrderResponse) => {
      set((state) => ({
        pendingOrders: state.pendingOrders.filter((o) => o.id !== data.id),
      }));
    });

    tradingWs.on('position_update', (data: PositionResponse) => {
      set((state) => {
        const idx = state.positions.findIndex((p) => p.id === data.id);
        let positions: PositionResponse[];
        if (idx >= 0) {
          positions = [...state.positions];
          const existing = state.positions[idx];
          // Merge: update dynamic fields from push, preserve immutable fields from API
          positions[idx] = {
            ...existing,
            ...data,
            // Always preserve copy-trade lineage (these never change after creation)
            is_copy_trade: existing.is_copy_trade,
            source_position_id: existing.source_position_id,
            source_trader_id: existing.source_trader_id,
            copy_trading_id: existing.copy_trading_id,
          };
        } else {
          positions = [data, ...state.positions];
        }
        // Recalculate account unrealized PnL and equity from all positions
        const totalUnrealizedPnl = positions.reduce((sum, p) => sum + (p.unrealized_pnl || 0), 0);
        const totalMargin = positions.reduce((sum, p) => sum + (p.margin_amount || 0), 0);
        const account = state.account
          ? {
              ...state.account,
              unrealized_pnl: totalUnrealizedPnl,
              margin_used: totalMargin,
              equity: state.account.balance + state.account.frozen + totalUnrealizedPnl,
            }
          : null;
        return { positions, account };
      });
    });

    tradingWs.on('position_closed', (data: PositionResponse) => {
      set((state) => ({
        positions: state.positions.filter((p) => p.id !== data.id),
        positionHistory: [data, ...state.positionHistory],
      }));
    });

    tradingWs.on('position_liquidated', (data: PositionResponse) => {
      set((state) => ({
        positions: state.positions.filter((p) => p.id !== data.id),
        positionHistory: [data, ...state.positionHistory],
      }));
    });

    tradingWs.on('balance_update', (data: { balance: number; frozen: number }) => {
      set((state) => ({
        account: state.account
          ? { ...state.account, balance: data.balance, frozen: data.frozen, available: data.balance }
          : null,
        wallet: state.wallet
          ? { ...state.wallet, balance: data.balance, frozen: data.frozen }
          : null,
      }));
    });

    tradingWs.on('account_update', (data: AccountInfoResponse) => {
      set({ account: data });
    });

    tradingWs.connect();
    set({ wsConnected: true });
  },

  disconnectWs: () => {
    tradingWs.disconnect();
    set({ wsConnected: false });
  },
}));
