import { Platform } from 'react-native';
import apiClient from './client';

export interface Feedback {
  id: string;
  user_id: string;
  content: string;
  image_urls: string[];
  category: string;
  status: string;
  admin_reply: string;
  replied_by?: string;
  replied_at?: string;
  user_unread: boolean;
  created_at: string;
  updated_at: string;
}

export interface CreateFeedbackRequest {
  content: string;
  image_urls: string[];
  category: string;
}

/**
 * 提交投诉建议
 */
export async function submitFeedback(req: CreateFeedbackRequest): Promise<void> {
  await apiClient.post('/api/feedbacks', req);
}

/**
 * 查看我的投诉建议列表
 */
export async function listMyFeedbacks(limit = 20, offset = 0): Promise<{ feedbacks: Feedback[]; total: number }> {
  const { data } = await apiClient.get('/api/feedbacks', {
    params: { limit, offset },
  });
  return data;
}

/**
 * 上传图片（使用现有上传接口）
 */
export async function uploadImage(uri: string): Promise<string> {
  const formData = new FormData();
  const filename = uri.split('/').pop()?.split('?')[0] || 'photo.jpg';

  if (Platform.OS === 'web') {
    // 浏览器的 FormData 不认 { uri, name, type }（会被序列化成 "[object Object]"），必须用 Blob。
    const res = await fetch(uri);
    const blob = await res.blob();
    formData.append('file', blob, filename);
  } else {
    const ext = filename.split('.').pop()?.toLowerCase() || 'jpg';
    const mimeType = ext === 'png' ? 'image/png' : ext === 'gif' ? 'image/gif' : 'image/jpeg';
    formData.append('file', {
      uri,
      name: filename,
      type: mimeType,
    } as any);
  }

  const { data } = await apiClient.post('/api/upload', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
  return data.url;
}

/**
 * 获取单条反馈详情（仅限本人）
 */
export async function getMyFeedback(id: string): Promise<Feedback> {
  const { data } = await apiClient.get(`/api/feedbacks/${id}`);
  return data;
}

/**
 * 标记反馈已读（消除未读红点）
 */
export async function markFeedbackRead(id: string): Promise<void> {
  await apiClient.post(`/api/feedbacks/${id}/read`);
}

/**
 * 获取未读回复数
 */
export async function getFeedbackUnreadCount(): Promise<number> {
  const { data } = await apiClient.get('/api/feedbacks/unread-count');
  return data?.count ?? 0;
}
