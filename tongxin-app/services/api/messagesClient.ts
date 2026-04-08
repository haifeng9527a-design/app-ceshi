import axios from 'axios';
import { Config } from '../config';
import { getStoredToken } from './client';

const messagesClient = axios.create({
  baseURL: Config.MESSAGES_API_BASE_URL,
  timeout: 15000,
  headers: {
    'Content-Type': 'application/json',
  },
});

messagesClient.interceptors.request.use(async (config) => {
  try {
    const token = await getStoredToken();
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
  } catch {
    // Non-blocking for public message-related endpoints.
  }
  return config;
});

messagesClient.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error('[Messages API Error]', error.response?.status, error.message);
    return Promise.reject(error);
  }
);

export default messagesClient;
