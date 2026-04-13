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
  const filename = uri.split('/').pop() || 'photo.jpg';
  const ext = filename.split('.').pop()?.toLowerCase() || 'jpg';
  const mimeType = ext === 'png' ? 'image/png' : ext === 'gif' ? 'image/gif' : 'image/jpeg';

  formData.append('file', {
    uri,
    name: filename,
    type: mimeType,
  } as any);

  const { data } = await apiClient.post('/api/upload', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
  return data.url;
}
