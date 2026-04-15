import apiClient from './client';

export interface DeleteAccountCheckResponse {
  can_delete: boolean;
  reasons: string[];
}

export async function changePassword(currentPassword: string, newPassword: string) {
  const { data } = await apiClient.post('/api/auth/change-password', {
    current_password: currentPassword,
    new_password: newPassword,
  });
  return data;
}

export async function changeEmail(newEmail: string, currentPassword: string) {
  const { data } = await apiClient.post('/api/auth/change-email', {
    new_email: newEmail,
    current_password: currentPassword,
  });
  return data;
}

export async function checkDeleteAccount(): Promise<DeleteAccountCheckResponse> {
  const { data } = await apiClient.get('/api/auth/delete-account/check');
  return {
    can_delete: !!data?.can_delete,
    reasons: Array.isArray(data?.reasons) ? data.reasons : [],
  };
}

export async function deleteAccount(currentPassword: string) {
  const { data } = await apiClient.post('/api/auth/delete-account', {
    current_password: currentPassword,
  });
  return data;
}
