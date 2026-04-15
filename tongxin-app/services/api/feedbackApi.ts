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
  const rawName = uri.split('/').pop()?.split('?')[0] || '';
  // 如果 URI 里本来就带扩展名（原生端常见），直接用；否则等下用 MIME 推断。
  const hasExt = /\.[a-z0-9]+$/i.test(rawName);

  if (Platform.OS === 'web') {
    // 浏览器的 FormData 不认 { uri, name, type }（会被序列化成 "[object Object]"），必须用 Blob。
    // 而且 ImagePicker 在 web 返回的常是 blob:xxx/<uuid>（无扩展名），
    // 必须根据 blob.type 回推扩展名，后端 /api/upload 按扩展名白名单做校验。
    const res = await fetch(uri);
    const blob = await res.blob();
    const mimeToExt: Record<string, string> = {
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
    };
    const ext = hasExt
      ? rawName.split('.').pop()!.toLowerCase()
      : (mimeToExt[blob.type] || 'jpg');
    const filename = hasExt ? rawName : `photo.${ext}`;
    formData.append('file', blob, filename);
  } else {
    const filename = rawName || 'photo.jpg';
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
