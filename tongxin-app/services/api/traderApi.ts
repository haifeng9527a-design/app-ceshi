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
  copy_ratio: number;
  max_position: number | null;
  created_at: string;
  updated_at: string;
  trader_name?: string;
  trader_avatar?: string;
}

export interface FollowTraderRequest {
  copy_ratio?: number;
  max_position?: number;
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
