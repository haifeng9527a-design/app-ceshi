import apiClient from './client';

export interface AssetOverviewAccount {
  account_type: string;
  display_name: string;
  equity: number;
  available: number;
  frozen: number;
  unrealized_pnl?: number;
  margin_used?: number;
  is_virtual?: boolean;
}

export interface AssetTransaction {
  id: string;
  type: string;
  direction: 'credit' | 'debit' | 'internal';
  amount: number;
  net_amount: number;
  balance_after: number;
  account_type: string;
  counterparty_account_type?: string;
  status?: string;
  note?: string;
  created_at: string;
}

export interface AssetChangePoint {
  date: string;
  label: string;
  net_change: number;
  equity: number;
}

export type AssetRangeKey = '1d' | '7d' | '30d' | '90d';

export interface AssetPnlCalendarDay {
  date: string;
  day: number;
  net_pnl: number;
  has_data: boolean;
  is_today: boolean;
}

export interface AssetPnlCalendarResponse {
  year: number;
  month: number;
  month_label: string;
  days: AssetPnlCalendarDay[];
  positive_days: number;
  negative_days: number;
  flat_days: number;
  net_pnl: number;
}

export interface AssetPendingWithdrawal {
  id: string;
  network: string;
  address: string;
  amount: number;
  status: string;
  provider_status?: string;
  created_at: string;
}

export interface AssetDepositAddress {
  id: string;
  account_type: string;
  asset_code: string;
  network: string;
  address: string;
  memo?: string;
  provider: string;
  status: string;
  created_at: string;
}

export interface AssetDepositRecord {
  id: string;
  account_type: string;
  asset_code: string;
  network: string;
  address: string;
  memo?: string;
  amount: number;
  confirmations: number;
  status: string;
  tx_hash?: string;
  credited_at?: string;
  created_at: string;
}

export interface CopySummaryItem {
  trader_uid: string;
  trader_name: string;
  trader_avatar?: string;
  status: 'active' | 'paused' | 'stopped';
  allocated_capital: number;
  available_capital: number;
  frozen_capital: number;
  open_position_count: number;
  updated_at: string;
}

export interface CopySummaryResponse {
  total_allocated: number;
  total_available: number;
  total_frozen: number;
  active_trader_count: number;
  open_position_count: number;
  items: CopySummaryItem[];
}

export interface CopyAccountOverviewResponse {
  total_equity: number;
  total_allocated: number;
  total_available: number;
  total_frozen: number;
  active_pool_count: number;
  current_pool_count: number;
  open_position_count: number;
  today_realized_pnl: number;
  today_profit_share: number;
  today_net_pnl: number;
  lifetime_realized_pnl: number;
  lifetime_profit_share: number;
  lifetime_net_pnl: number;
}

export interface CopyAccountPoolItem {
  copy_trading_id: string;
  trader_uid: string;
  trader_name: string;
  trader_avatar?: string;
  status: 'active' | 'paused' | 'stopped';
  allocated_capital: number;
  available_capital: number;
  frozen_capital: number;
  current_equity: number;
  open_position_count: number;
  current_net_pnl: number;
  current_return_rate: number;
  lifetime_realized_pnl: number;
  lifetime_profit_share: number;
  lifetime_net_pnl: number;
  updated_at: string;
}

export interface CopyAccountPoolsResponse {
  items: CopyAccountPoolItem[];
  total_count: number;
  active_count: number;
}

export interface CopyAccountOpenPositionItem {
  position_id: string;
  copy_trading_id: string;
  trader_uid: string;
  trader_name: string;
  trader_avatar?: string;
  symbol: string;
  side: string;
  qty: number;
  entry_price: number;
  current_price: number;
  margin_amount: number;
  unrealized_pnl: number;
  roe: number;
  leverage: number;
  opened_at: string;
}

export interface CopyAccountOpenPositionsResponse {
  items: CopyAccountOpenPositionItem[];
  total_count: number;
}

export interface CopyAccountHistoryItem {
  position_id: string;
  copy_trading_id: string;
  trader_uid: string;
  trader_name: string;
  trader_avatar?: string;
  symbol: string;
  side: string;
  qty: number;
  entry_price: number;
  close_price: number;
  margin_amount: number;
  gross_pnl: number;
  open_fee: number;
  close_fee: number;
  profit_shared: number;
  net_pnl: number;
  result: 'profit' | 'loss' | 'flat';
  opened_at: string;
  closed_at?: string;
}

export interface CopyAccountHistoryResponse {
  items: CopyAccountHistoryItem[];
  total_count: number;
}

export interface AssetsOverviewResponse {
  currency: string;
  total_equity: number;
  today_pnl: number;
  today_pnl_rate: number;
  accounts: AssetOverviewAccount[];
  copy_summary?: CopySummaryResponse;
  pending_withdrawals?: AssetPendingWithdrawal[];
  pending_withdrawal_count?: number;
  pending_withdrawal_amount?: number;
  recent_transactions: AssetTransaction[];
  change_series: AssetChangePoint[];
}

export interface AssetTransferRequest {
  from_account: string;
  to_account: string;
  amount: number;
}

export interface AssetTransferResponse {
  transfer_id: string;
  from_account: string;
  to_account: string;
  amount: number;
  main_available: number;
  futures_available: number;
}

export interface AssetDepositResponse {
  account_type: string;
  amount: number;
  spot_available: number;
  spot_frozen: number;
}

export interface AssetDepositAddressRequest {
  asset_code: string;
  network: string;
}

export interface AssetDepositNetworkOption {
  value: string;
  label: string;
}

export interface AssetDepositAssetOption {
  asset_code: string;
  label: string;
  networks: AssetDepositNetworkOption[];
}

export interface AssetWithdrawRequest {
  amount: number;
  address: string;
  network: string;
}

export interface AssetWithdrawResponse {
  withdrawal_id: string;
  account_type: string;
  amount: number;
  address: string;
  network: string;
  spot_available: number;
  spot_frozen: number;
  status: string;
}

export interface SpotHoldingItem {
  key: string;
  category: 'crypto' | 'stock';
  asset_code: string;
  asset_name: string;
  icon_url?: string;
  balance_total: number;
  balance_available: number;
  balance_frozen: number;
  price: number;
  avg_cost: number;
  cost_estimated: boolean;
  valuation: number;
  daily_change_rate: number;
  unrealized_pnl: number;
  unrealized_pnl_rate: number;
  today_realized_pnl: number;
  lifetime_realized_pnl: number;
  current_total_pnl: number;
  is_dust: boolean;
  can_deposit: boolean;
  can_withdraw: boolean;
  can_transfer: boolean;
}

export interface SpotHoldingsResponse {
  items: SpotHoldingItem[];
  total_count: number;
  visible_count: number;
  owned_count: number;
}

export async function getAssetsOverview(range: AssetRangeKey = '7d'): Promise<AssetsOverviewResponse> {
  const { data } = await apiClient.get('/api/assets/overview', { params: { range } });
  return data;
}

export async function getAssetsPnlCalendar(year: number, month: number): Promise<AssetPnlCalendarResponse> {
  const { data } = await apiClient.get('/api/assets/pnl-calendar', { params: { year, month } });
  return data;
}

export async function getSpotHoldings(
  category = 'all',
  ownedOnly = true,
  hideDust = false,
  query = '',
): Promise<SpotHoldingsResponse> {
  const { data } = await apiClient.get('/api/assets/spot-holdings', {
    params: {
      category,
      owned_only: ownedOnly,
      hide_dust: hideDust,
      query,
    },
  });
  return data;
}

export async function getDepositAddresses(assetCode = '', network = ''): Promise<AssetDepositAddress[]> {
  const { data } = await apiClient.get('/api/assets/deposit-addresses', {
    params: { asset_code: assetCode, network },
  });
  return data;
}

export async function getDepositOptions(): Promise<AssetDepositAssetOption[]> {
  const { data } = await apiClient.get('/api/assets/deposit-options');
  return data;
}

export async function createDepositAddress(payload: AssetDepositAddressRequest): Promise<AssetDepositAddress> {
  const { data } = await apiClient.post('/api/assets/deposit-addresses', payload);
  return data;
}

export async function getDepositRecords(assetCode = '', limit = 10, offset = 0): Promise<AssetDepositRecord[]> {
  const { data } = await apiClient.get('/api/assets/deposits', {
    params: { asset_code: assetCode, limit, offset },
  });
  return data;
}

export async function getCopySummary(): Promise<CopySummaryResponse> {
  const { data } = await apiClient.get('/api/assets/copy-summary');
  return data;
}

export async function getCopyAccountOverview(): Promise<CopyAccountOverviewResponse> {
  const { data } = await apiClient.get('/api/assets/copy-account/overview');
  return data;
}

export async function getCopyAccountPools(status = 'current'): Promise<CopyAccountPoolsResponse> {
  const { data } = await apiClient.get('/api/assets/copy-account/pools', { params: { status } });
  return data;
}

export async function getCopyAccountOpenPositions(traderUID = ''): Promise<CopyAccountOpenPositionsResponse> {
  const { data } = await apiClient.get('/api/assets/copy-account/open-positions', {
    params: { trader_uid: traderUID },
  });
  return data;
}

export async function getCopyAccountHistory(
  traderUID = '',
  limit = 20,
  offset = 0,
): Promise<CopyAccountHistoryResponse> {
  const { data } = await apiClient.get('/api/assets/copy-account/history', {
    params: { trader_uid: traderUID, limit, offset },
  });
  return data;
}

export async function depositToSpotAccount(amount: number): Promise<AssetDepositResponse> {
  const { data } = await apiClient.post('/api/assets/deposit', { amount });
  return data;
}

export async function withdrawFromSpotAccount(payload: AssetWithdrawRequest): Promise<AssetWithdrawResponse> {
  const { data } = await apiClient.post('/api/assets/withdraw', payload);
  return data;
}

export async function getAssetTransactions(limit = 50, offset = 0, status = ''): Promise<AssetTransaction[]> {
  const { data } = await apiClient.get('/api/assets/transactions', { params: { limit, offset, status } });
  return data;
}

export async function transferAssets(payload: AssetTransferRequest): Promise<AssetTransferResponse> {
  const { data } = await apiClient.post('/api/assets/transfer', payload);
  return data;
}
