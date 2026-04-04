/**
 * App Configuration
 */

export const Config = {
  // Backend API (Go backend)
  API_BASE_URL: process.env.EXPO_PUBLIC_API_URL || 'http://localhost:3001',
  WS_MARKET_URL: process.env.EXPO_PUBLIC_WS_MARKET_URL || 'ws://localhost:3001/ws/market',
  WS_CHAT_URL: process.env.EXPO_PUBLIC_WS_CHAT_URL || 'ws://localhost:3001/ws/chat',
  WS_TRADING_URL: process.env.EXPO_PUBLIC_WS_TRADING_URL || 'ws://localhost:3001/ws/trading',
} as const;
