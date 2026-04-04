/**
 * App Configuration
 *
 * 说明：真机调试时若只把 API 改成局域网 IP，而 WS 仍写 localhost，
 * 会导致聊天 WebSocket 连不上、好友申请实时通知收不到。下面会在明显冲突时自动用与 API 同主机生成 ws 地址。
 */

const apiBase = process.env.EXPO_PUBLIC_API_URL || 'http://localhost:3001';

function inferWsUrl(base: string, path: string): string {
  try {
    const u = new URL(base);
    const isHttps = u.protocol === 'https:';
    u.protocol = isHttps ? 'wss:' : 'ws:';
    u.pathname = path;
    u.search = '';
    u.hash = '';
    return u.toString();
  } catch {
    return `ws://localhost:3001${path}`;
  }
}

function isLoopbackHost(hostname: string): boolean {
  return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]';
}

/** 显式配置的 WS 若仍是 localhost，而 API 已指向其它主机，则判定为配置错误，改用与 API 同主机。 */
function resolveWsUrl(explicit: string | undefined, api: string, path: string): string {
  if (!explicit?.trim()) {
    return inferWsUrl(api, path);
  }
  try {
    const apiHost = new URL(api).hostname;
    const wsUrl = explicit.trim();
    const wsAsHttp = wsUrl.replace(/^ws/i, 'http');
    const wsHost = new URL(wsAsHttp).hostname;
    if (!isLoopbackHost(apiHost) && isLoopbackHost(wsHost)) {
      return inferWsUrl(api, path);
    }
  } catch {
    // 解析失败则退回显式串
  }
  return explicit.trim();
}

export const Config = {
  API_BASE_URL: apiBase,
  WS_MARKET_URL: resolveWsUrl(process.env.EXPO_PUBLIC_WS_MARKET_URL, apiBase, '/ws/market'),
  /** 须与 API 同主机；Token：tongxin-go 用登录 JWT；tongxin-backend(Node) 的 /ws/chat 仅校验 Firebase ID Token，与邮箱登录 JWT 不一致时无法连接 */
  WS_CHAT_URL: resolveWsUrl(process.env.EXPO_PUBLIC_WS_CHAT_URL, apiBase, '/ws/chat'),
  WS_TRADING_URL: resolveWsUrl(process.env.EXPO_PUBLIC_WS_TRADING_URL, apiBase, '/ws/trading'),
} as const;
