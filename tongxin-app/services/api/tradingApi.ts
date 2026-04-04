import apiClient from './client';

export interface PlaceOrderRequest {
  symbol: string;
  side: 'long' | 'short';
  type: 'market' | 'limit';
  qty: number;
  price?: number;
  leverage: number;
  margin_mode: 'cross' | 'isolated';
  tp_price?: number;
  sl_price?: number;
}

export interface OrderResponse {
  id: string;
  user_id: string;
  symbol: string;
  side: string;
  order_type: string;
  qty: number;
  price?: number;
  filled_price?: number;
  leverage: number;
  margin_mode: string;
  margin_amount: number;
  status: string;
  created_at: string;
  filled_at?: string;
  cancelled_at?: string;
}

export interface PositionResponse {
  id: string;
  user_id: string;
  symbol: string;
  side: string;
  qty: number;
  entry_price: number;
  leverage: number;
  margin_mode: string;
  margin_amount: number;
  liq_price?: number;
  tp_price?: number;
  sl_price?: number;
  unrealized_pnl: number;
  current_price: number;
  roe: number;
  status: string;
  realized_pnl: number;
  close_price?: number;
  created_at: string;
  closed_at?: string;
}

export interface AccountInfoResponse {
  balance: number;
  frozen: number;
  equity: number;
  margin_used: number;
  available: number;
  unrealized_pnl: number;
}

export interface WalletResponse {
  user_id: string;
  balance: number;
  frozen: number;
  total_deposit: number;
}

export interface WalletTransaction {
  id: string;
  user_id: string;
  type: string;
  amount: number;
  balance_after: number;
  ref_id?: string;
  note?: string;
  created_at: string;
}

export async function placeOrder(req: PlaceOrderRequest): Promise<OrderResponse> {
  const { data } = await apiClient.post('/api/trading/orders', req);
  return data;
}

export async function listOrders(status = 'all'): Promise<OrderResponse[]> {
  const { data } = await apiClient.get('/api/trading/orders', { params: { status } });
  return data;
}

export async function cancelOrder(id: string): Promise<OrderResponse> {
  const { data } = await apiClient.delete(`/api/trading/orders/${id}`);
  return data;
}

export async function listPositions(): Promise<PositionResponse[]> {
  const { data } = await apiClient.get('/api/trading/positions');
  return data;
}

export async function closePosition(id: string): Promise<PositionResponse> {
  const { data } = await apiClient.delete(`/api/trading/positions/${id}`);
  return data;
}

export async function updateTPSL(id: string, tp_price?: number, sl_price?: number): Promise<PositionResponse> {
  const { data } = await apiClient.put(`/api/trading/positions/${id}/tp-sl`, { tp_price, sl_price });
  return data;
}

export async function partialClosePosition(id: string, qty: number): Promise<PositionResponse> {
  const { data } = await apiClient.post(`/api/trading/positions/${id}/partial-close`, { qty });
  return data;
}

export async function listPositionHistory(limit = 50): Promise<PositionResponse[]> {
  const { data } = await apiClient.get('/api/trading/positions/history', { params: { limit } });
  return data;
}

export async function getAccount(): Promise<AccountInfoResponse> {
  const { data } = await apiClient.get('/api/trading/account');
  return data;
}

export async function deposit(amount: number): Promise<WalletResponse> {
  const { data } = await apiClient.post('/api/wallet/deposit', { amount });
  return data;
}

export async function getWallet(): Promise<WalletResponse> {
  const { data } = await apiClient.get('/api/wallet');
  return data;
}

export async function getTransactions(limit = 50, offset = 0): Promise<WalletTransaction[]> {
  const { data } = await apiClient.get('/api/wallet/transactions', { params: { limit, offset } });
  return data;
}
