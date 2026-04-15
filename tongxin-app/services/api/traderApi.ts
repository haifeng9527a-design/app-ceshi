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
  // 跟单分润：trader 当前默认抽成比例（0~0.2），新跟单者会 snapshot 这个值
  default_profit_share_rate?: number;
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
  // 跟单分配本金（虚拟子账户）
  allocated_capital: number;
  available_capital: number;
  frozen_capital: number;
  // 跟单分润 snapshot（建立跟单时锁定，trader 改默认比例不影响存量行）
  profit_share_rate?: number;
  cumulative_profit_shared?: number;
  high_water_mark?: number;
  cumulative_net_deposit?: number;
  created_at: string;
  updated_at: string;
  trader_name?: string;
  trader_avatar?: string;
}

export interface FollowTraderRequest {
  allocated_capital: number; // 必填，跟单分配本金（USDT）
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

// 取消跟单。force=true 时后端会自动按市价平掉所有该交易员的跟单仓位，
// 然后把池子余额退回钱包并停止订阅。前端调用 force 之前必须先和用户确认。
export async function unfollowTrader(
  uid: string,
  force = false,
): Promise<{ status: string; closed_positions?: number }> {
  const url = force
    ? `/api/trader/${uid}/follow?force=true`
    : `/api/trader/${uid}/follow`;
  const { data } = await apiClient.delete(url);
  return data ?? { status: 'unfollowed' };
}

export async function updateCopySettings(uid: string, req: FollowTraderRequest): Promise<CopyTrading> {
  const { data } = await apiClient.put(`/api/trader/${uid}/follow/settings`, req);
  return data;
}

// 追加 / 赎回跟单本金。delta>0 追加（钱包→池子），<0 赎回（池子→钱包）
export async function adjustAllocatedCapital(uid: string, delta: number): Promise<CopyTrading> {
  const { data } = await apiClient.patch(`/api/trader/${uid}/follow/capital`, { delta });
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

// ── Equity Curve ──

export interface EquityPoint {
  date: string;
  daily_pnl: number;
  cumulative_pnl: number;
}

export async function getTraderEquity(uid: string, period: '7d' | '30d' | 'all' = '30d'): Promise<EquityPoint[]> {
  const { data } = await apiClient.get(`/api/trader/${uid}/equity`, { params: { period } });
  return data || [];
}

// ── Profit Share (跟单分润) ──

export interface ProfitShareSummary {
  // 与 internal/model/trader.go ProfitShareSummary JSON 字段一一对齐
  lifetime: number;            // 累计已收分润
  this_month: number;          // 本月已收分润
  active_followers: number;    // 活跃跟随者人数
  default_share_rate: number;  // 当前默认分润比例（0~0.2）
}

export interface ProfitShareRecord {
  id: string;
  created_at: string;
  copy_trading_id: string;
  follower_user_id: string;
  trader_user_id: string;
  position_id: string;
  gross_pnl: number;
  close_fee: number;
  net_pnl: number;
  equity_before: number;
  equity_after: number;
  hwm_before: number;
  hwm_after: number;
  rate_applied: number;
  share_amount: number;
  status: 'settled' | 'skipped_below_hwm' | 'skipped_loss' | 'skipped_zero_rate';
  // 后端 dashboard 接口 JOIN 进来的显示字段
  follower_name?: string;
  position_info?: string; // e.g. "BTCUSDT close"
}

export async function getProfitShareSummary(): Promise<ProfitShareSummary> {
  const { data } = await apiClient.get('/api/trader/profit-share/summary');
  return data;
}

export async function getProfitShareRecords(
  limit = 20,
  offset = 0,
): Promise<{ records: ProfitShareRecord[]; total: number }> {
  const { data } = await apiClient.get('/api/trader/profit-share/records', {
    params: { limit: String(limit), offset: String(offset) },
  });
  return {
    records: data?.records ?? [],
    total: data?.total ?? 0,
  };
}

// trader 修改默认分润比例。rate ∈ [0, 0.2]，越界后端返 400。
// 修改不会影响存量 follower（snapshot 锁定）。
export async function updateDefaultShareRate(rate: number): Promise<{ default_profit_share_rate: number }> {
  const { data } = await apiClient.put('/api/trader/profile/share-rate', { rate });
  return data;
}
