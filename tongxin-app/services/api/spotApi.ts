import apiClient from './client';

// ── Enums ──
export type SpotSide = 'buy' | 'sell';
export type SpotOrderType = 'market' | 'limit';
export type SpotOrderStatus = 'pending' | 'filled' | 'cancelled' | 'rejected';
export type SpotCategory = 'crypto' | 'stocks';

// ── Types ──
export interface SpotSupportedSymbol {
  symbol: string;
  base_asset: string;
  quote_asset: string;
  category: SpotCategory;
  display_name: string;
  min_qty: number;
  qty_precision: number;
  price_precision: number;
  is_active: boolean;
  sort_order: number;
}

export interface SpotFeeTier {
  vip_level: number;
  maker_fee: number;
  taker_fee: number;
  updated_at: string;
}

export interface SpotOrder {
  id: string;
  user_id: string;
  symbol: string;
  base_asset: string;
  quote_asset: string;
  side: SpotSide;
  order_type: SpotOrderType;
  qty: number;
  price?: number;
  filled_price?: number;
  filled_qty: number;
  quote_qty: number;
  frozen_amount: number;
  status: SpotOrderStatus;
  fee: number;
  fee_asset: string;
  fee_rate: number;
  is_maker: boolean;
  reject_reason?: string;
  client_order_id?: string;
  created_at: string;
  filled_at?: string;
  cancelled_at?: string;
}

export interface SpotPlaceOrderRequest {
  symbol: string;
  side: SpotSide;
  order_type: SpotOrderType;
  qty?: number;        // Buy/Sell by base asset quantity
  quote_qty?: number;  // Buy by quote amount (market only)
  price?: number;      // Required for limit orders
  client_order_id?: string;
}

export interface SpotAccountHolding {
  asset: string;
  available: number;
  frozen: number;
  valuation_usdt: number;
  avg_buy_price?: number;
  unrealized_pnl?: number;
  unrealized_pnl_pct?: number;
}

export interface SpotAccountInfo {
  user_id: string;
  total_valuation_usdt: number;
  holdings: SpotAccountHolding[];
}

export interface SpotOrderListResponse {
  orders: SpotOrder[];
  total: number;
  limit: number;
  offset: number;
}

export interface ListSymbolsResponse {
  symbols: SpotSupportedSymbol[];
  count: number;
}

export interface FeeScheduleResponse {
  tiers: SpotFeeTier[];
}

// ── API ──
export const spotApi = {
  listSymbols: (category?: SpotCategory) =>
    apiClient
      .get<ListSymbolsResponse>('/api/spot/symbols', {
        params: category ? { category } : undefined,
      })
      .then(r => r.data),

  getFeeSchedule: () =>
    apiClient.get<FeeScheduleResponse>('/api/spot/fee-schedule').then(r => r.data),

  placeOrder: (req: SpotPlaceOrderRequest) =>
    apiClient.post<SpotOrder>('/api/spot/orders', req).then(r => r.data),

  cancelOrder: (orderId: string) =>
    apiClient.delete<{ ok: boolean }>(`/api/spot/orders/${orderId}`).then(r => r.data),

  listOrders: (params?: {
    status?: SpotOrderStatus;
    symbol?: string;
    limit?: number;
    offset?: number;
  }) =>
    apiClient
      .get<SpotOrderListResponse>('/api/spot/orders', { params })
      .then(r => r.data),

  orderHistory: (params?: { symbol?: string; limit?: number; offset?: number }) =>
    apiClient
      .get<SpotOrderListResponse>('/api/spot/orders/history', { params })
      .then(r => r.data),

  getAccount: () =>
    apiClient.get<SpotAccountInfo>('/api/spot/account').then(r => r.data),
};
