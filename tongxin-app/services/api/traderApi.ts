import apiClient from './client';

// ── Types ──

export interface TraderApplication {
  id: string;
  user_id: string;
  status: 'pending' | 'approved' | 'rejected';
  real_name: string;
  id_number: string;
  phone: string;
  nationality: string;
  address: string;
  experience_years: number;
  markets: string[];
  capital_source: string;
  estimated_volume: string;
  risk_agreed: boolean;
  terms_agreed: boolean;
  reviewed_by: string | null;
  reviewed_at: string | null;
  rejection_reason: string;
  created_at: string;
  updated_at: string;
  // Joined fields
  display_name?: string;
  email?: string;
  avatar_url?: string;
}

export interface SubmitApplicationRequest {
  real_name: string;
  id_number: string;
  phone: string;
  nationality?: string;
  address?: string;
  experience_years: number;
  markets: string[];
  capital_source: string;
  estimated_volume: string;
  risk_agreed: boolean;
  terms_agreed: boolean;
}

export interface TraderStats {
  user_id: string;
  total_trades: number;
  win_trades: number;
  total_pnl: number;
  win_rate: number;
  avg_pnl: number;
  max_drawdown: number;
  followers_count: number;
  updated_at: string;
}

export interface TraderProfile {
  uid: string;
  display_name: string;
  avatar_url: string;
  is_trader: boolean;
  allow_copy_trading: boolean;
  stats: TraderStats | null;
  is_followed: boolean;
}

export interface FollowedTrader {
  uid: string;
  display_name: string;
  avatar_url: string;
  is_trader: boolean;
  allow_copy_trading: boolean;
  stats: TraderStats | null;
  followed_at: string;
  is_copying: boolean;
  copy_status: string; // "" | "active" | "paused"
}

export interface TraderRankingItem {
  uid: string;
  display_name: string;
  avatar_url: string;
  total_trades: number;
  win_rate: number;
  total_pnl: number;
  avg_pnl: number;
  max_drawdown: number;
  followers_count: number;
  allow_copy_trading: boolean;
}

export interface CopyTrading {
  id: string;
  follower_id: string;
  trader_id: string;
  status: 'active' | 'paused' | 'stopped';
  copy_mode: 'fixed' | 'ratio';
  copy_ratio: number;
  fixed_amount?: number;
  max_position?: number;
  max_single_margin?: number;
  follow_symbols: string[];
  leverage_mode: 'trader' | 'custom';
  custom_leverage?: number;
  tp_sl_mode: 'trader' | 'custom';
  custom_tp_ratio?: number;
  custom_sl_ratio?: number;
  follow_direction: 'both' | 'long' | 'short';
  created_at: string;
  updated_at: string;
  trader_name?: string;
  trader_avatar?: string;
}

export interface FollowTraderRequest {
  copy_mode?: 'fixed' | 'ratio';
  copy_ratio?: number;
  fixed_amount?: number;
  max_position?: number;
  max_single_margin?: number;
  follow_symbols?: string[];
  leverage_mode?: 'trader' | 'custom';
  custom_leverage?: number;
  tp_sl_mode?: 'trader' | 'custom';
  custom_tp_ratio?: number;
  custom_sl_ratio?: number;
  follow_direction?: 'both' | 'long' | 'short';
}

export interface CopyTradeLog {
  id: string;
  copy_trading_id: string;
  follower_id: string;
  trader_id: string;
  action: 'open' | 'close' | 'partial_close' | 'skip';
  source_order_id?: string;
  source_position_id?: string;
  follower_order_id?: string;
  follower_position_id?: string;
  symbol: string;
  side: string;
  trader_qty: number;
  follower_qty: number;
  trader_margin: number;
  follower_margin: number;
  follower_leverage: number;
  realized_pnl: number;
  skip_reason?: string;
  created_at: string;
  trader_name?: string;
  trader_avatar?: string;
}

// ── API Functions ──

export async function submitApplication(req: SubmitApplicationRequest): Promise<TraderApplication> {
  const { data } = await apiClient.post('/api/trader/apply', req);
  return data;
}

export async function getMyApplication(): Promise<{ application: TraderApplication | null }> {
  const { data } = await apiClient.get('/api/trader/my-application');
  return data;
}

export async function getMyStats(): Promise<TraderStats> {
  const { data } = await apiClient.get('/api/trader/my-stats');
  return data;
}

export async function toggleCopyTrading(allow: boolean): Promise<void> {
  await apiClient.put('/api/trader/copy-trading-toggle', { allow });
}

export async function getMyFollowers(): Promise<CopyTrading[]> {
  const { data } = await apiClient.get('/api/trader/my-followers');
  return data;
}

export async function getMyFollowing(): Promise<CopyTrading[]> {
  const { data } = await apiClient.get('/api/trader/my-following');
  return data;
}

export async function getTraderRankings(
  sort?: string,
  limit?: number,
  offset?: number
): Promise<{ traders: TraderRankingItem[]; total: number }> {
  const params: Record<string, string> = {};
  if (sort) params.sort = sort;
  if (limit) params.limit = String(limit);
  if (offset) params.offset = String(offset);
  const { data } = await apiClient.get('/api/trader/rankings', { params });
  return data;
}

export async function getTraderProfile(uid: string): Promise<TraderProfile> {
  const { data } = await apiClient.get(`/api/trader/${uid}/profile`);
  return data;
}

export async function followTrader(uid: string, req?: FollowTraderRequest): Promise<CopyTrading> {
  const { data } = await apiClient.post(`/api/trader/${uid}/follow`, req || {});
  return data;
}

export async function unfollowTrader(uid: string): Promise<void> {
  await apiClient.delete(`/api/trader/${uid}/follow`);
}

export async function updateCopySettings(uid: string, req: FollowTraderRequest): Promise<CopyTrading> {
  const { data } = await apiClient.put(`/api/trader/${uid}/follow/settings`, req);
  return data;
}

export async function pauseCopyTrading(uid: string): Promise<void> {
  await apiClient.post(`/api/trader/${uid}/follow/pause`);
}

export async function resumeCopyTrading(uid: string): Promise<void> {
  await apiClient.post(`/api/trader/${uid}/follow/resume`);
}

export async function getCopyTradeLogs(
  traderUid?: string,
  limit?: number,
  offset?: number
): Promise<{ logs: CopyTradeLog[]; total: number }> {
  const params: Record<string, string> = {};
  if (traderUid) params.trader_id = traderUid;
  if (limit) params.limit = String(limit);
  if (offset) params.offset = String(offset);
  const { data } = await apiClient.get('/api/trader/copy-trade-logs', { params });
  return data;
}

export interface TraderPosition {
  id: string;
  symbol: string;
  side: string;
  qty: number;
  entry_price: number;
  leverage: number;
  status: string;
  realized_pnl: number;
  close_price: number;
  unrealized_pnl: number;
  current_price: number;
  roe: number;
  created_at: string;
  closed_at?: string;
}

export async function getTraderPositions(uid: string): Promise<TraderPosition[]> {
  const { data } = await apiClient.get(`/api/trader/${uid}/positions`);
  return data || [];
}

export async function getTraderTrades(uid: string, limit = 10): Promise<TraderPosition[]> {
  const { data } = await apiClient.get(`/api/trader/${uid}/trades?limit=${limit}`);
  return data || [];
}

// ── Watch (Follow) API ──

export async function watchTrader(uid: string): Promise<void> {
  await apiClient.post(`/api/trader/${uid}/watch`);
}

export async function unwatchTrader(uid: string): Promise<void> {
  await apiClient.delete(`/api/trader/${uid}/watch`);
}

export async function getMyWatchedTraders(): Promise<FollowedTrader[]> {
  const { data } = await apiClient.get('/api/trader/my-watched');
  return data;
}

// ── Admin API ──

export async function adminListApplications(
  status?: string,
  limit?: number,
  offset?: number
): Promise<{ applications: TraderApplication[]; total: number }> {
  const params: Record<string, string> = {};
  if (status) params.status = status;
  if (limit) params.limit = String(limit);
  if (offset) params.offset = String(offset);
  const { data } = await apiClient.get('/api/admin/trader-applications', { params });
  return data;
}

export async function adminApproveApplication(id: string): Promise<void> {
  await apiClient.post(`/api/admin/trader-applications/${id}/approve`);
}

export async function adminRejectApplication(id: string, reason?: string): Promise<void> {
  await apiClient.post(`/api/admin/trader-applications/${id}/reject`, { reason });
}
