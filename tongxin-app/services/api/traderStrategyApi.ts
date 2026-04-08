import apiClient from './client';

// ── Types ──

export interface TraderStrategy {
  id: string;
  author_id: string;
  title: string;
  summary: string;
  content_html: string;
  cover_image: string;
  category: string;
  tags: string[];
  status: 'draft' | 'published' | 'archived';
  views: number;
  likes: number;
  created_at: string;
  updated_at: string;
  author_name?: string;
  author_avatar?: string;
  is_trader?: boolean;
}

export interface CreateStrategyRequest {
  title: string;
  summary: string;
  content_html: string;
  cover_image?: string;
  category?: string;
  tags?: string[];
  status?: 'draft' | 'published';
}

export interface UpdateStrategyRequest {
  title?: string;
  summary?: string;
  content_html?: string;
  cover_image?: string;
  category?: string;
  tags?: string[];
  status?: string;
}

// ── API Functions ──

export async function createStrategy(req: CreateStrategyRequest): Promise<TraderStrategy> {
  const { data } = await apiClient.post('/api/strategies', req);
  return data;
}

export async function updateStrategy(id: string, req: UpdateStrategyRequest): Promise<TraderStrategy> {
  const { data } = await apiClient.put(`/api/strategies/${id}`, req);
  return data;
}

export async function deleteStrategy(id: string): Promise<void> {
  await apiClient.delete(`/api/strategies/${id}`);
}

export async function getStrategy(id: string): Promise<{ strategy: TraderStrategy; liked: boolean }> {
  const { data } = await apiClient.get(`/api/strategies/${id}`);
  return data;
}

export async function getMyStrategies(
  status?: string,
  limit?: number,
  offset?: number
): Promise<{ strategies: TraderStrategy[]; total: number }> {
  const params: Record<string, string> = {};
  if (status) params.status = status;
  if (limit) params.limit = String(limit);
  if (offset) params.offset = String(offset);
  const { data } = await apiClient.get('/api/strategies/my', { params });
  return data;
}

export async function getStrategyFeed(
  category?: string,
  limit?: number,
  offset?: number
): Promise<{ strategies: TraderStrategy[]; total: number }> {
  const params: Record<string, string> = {};
  if (category) params.category = category;
  if (limit) params.limit = String(limit);
  if (offset) params.offset = String(offset);
  const { data } = await apiClient.get('/api/strategies/feed', { params });
  return data;
}

export async function getTraderStrategies(
  uid: string,
  limit?: number,
  offset?: number
): Promise<{ strategies: TraderStrategy[]; total: number }> {
  const params: Record<string, string> = {};
  if (limit) params.limit = String(limit);
  if (offset) params.offset = String(offset);
  const { data } = await apiClient.get(`/api/strategies/author/${uid}`, { params });
  return data;
}

export async function likeStrategy(id: string): Promise<{ liked: boolean }> {
  const { data } = await apiClient.post(`/api/strategies/${id}/like`);
  return data;
}
