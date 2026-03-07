/**
 * Tongxin Backend
 * - 健康检查
 * - 行情代理（Polygon / Twelve Data）与缓存
 * 环境变量：POLYGON_API_KEY、TWELVE_DATA_API_KEY（可选），可从 .env 加载
 */
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { registerRoutes } = require('./lib/routes');
const { registerUserRoutes } = require('./lib/apiUsers');
const { registerFriendRoutes } = require('./lib/apiFriends');
const { registerMessageRoutes } = require('./lib/apiMessages');
const { registerTeacherRoutes } = require('./lib/apiTeachers');
const { registerUploadRoutes } = require('./lib/apiUpload');
const { registerMiscRoutes } = require('./lib/apiMisc');
const { registerWatchlistRoutes } = require('./lib/apiWatchlist');
const { registerTradingRoutes, startTradingMatchScheduler } = require('./lib/apiTrading');
const { registerAdminAuthRoutes } = require('./lib/apiAdminAuth');
const { registerAdminConfigRoutes } = require('./lib/apiAdminConfig');
const { requireAuth, optionalAuth } = require('./lib/authMiddleware');
const { startRefreshScheduler } = require('./lib/refreshScheduler');
const { startRotationScheduler } = require('./lib/rotationScheduler');
const { createChatWsServer } = require('./lib/chatWebSocket');
const { startForexScheduler } = require('./lib/forexScheduler');
const { startStockRealtimeIngestor } = require('./lib/stockRealtimeIngestor');
const { startForexRealtimeIngestor } = require('./lib/forexRealtimeIngestor');
const { startCryptoScheduler } = require('./lib/cryptoScheduler');
const { startCryptoRealtimeIngestor } = require('./lib/cryptoRealtimeIngestor');

const app = express();
const PORT = process.env.PORT || 3000;
const polygonKey = process.env.POLYGON_API_KEY?.trim() || null;
const twelveKey = process.env.TWELVE_DATA_API_KEY?.trim() || null;

app.use(cors());
// 举报截图走 base64 上传，默认 100kb 会触发 PayloadTooLargeError
app.use(express.json({ limit: '30mb' }));
app.use(express.urlencoded({ extended: true, limit: '30mb' }));

function createBasicRateLimiter({ windowMs, max, keyFn }) {
  const store = new Map();
  return (req, res, next) => {
    const key = keyFn(req);
    const now = Date.now();
    const hit = store.get(key);
    if (!hit || now - hit.start >= windowMs) {
      store.set(key, { start: now, count: 1 });
      return next();
    }
    hit.count += 1;
    if (hit.count > max) {
      return res.status(429).json({ error: '请求过于频繁，请稍后再试' });
    }
    return next();
  };
}

const apiLimiter = createBasicRateLimiter({
  windowMs: 60 * 1000,
  max: parseInt(process.env.API_RATE_LIMIT_PER_MIN || '240', 10),
  keyFn: (req) => `ip:${req.ip || req.socket?.remoteAddress || 'unknown'}`,
});
app.use('/api', apiLimiter);

const uploadLimiter = createBasicRateLimiter({
  windowMs: 60 * 1000,
  max: parseInt(process.env.UPLOAD_RATE_LIMIT_PER_MIN || '40', 10),
  keyFn: (req) => `upload:${req.ip || req.socket?.remoteAddress || 'unknown'}`,
});
app.use('/api/upload', uploadLimiter);

// 请求日志：每次请求输出 method path [status] duration
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - start;
    const status = res.statusCode;
    const uid = req.firebaseUid ? ` uid=${String(req.firebaseUid).slice(0, 12)}` : '';
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl || req.url} ${status} ${ms}ms${uid}`);
  });
  next();
});

app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'tongxin-backend' });
});

registerRoutes(app, polygonKey, twelveKey, requireAuth);
registerUserRoutes(app, requireAuth);
registerFriendRoutes(app, requireAuth);
registerMessageRoutes(app, requireAuth);
registerTeacherRoutes(app, requireAuth, optionalAuth);
registerUploadRoutes(app, requireAuth);
registerMiscRoutes(app, requireAuth);
registerWatchlistRoutes(app, requireAuth);
registerTradingRoutes(app, requireAuth);
registerAdminAuthRoutes(app);
registerAdminConfigRoutes(app);
startTradingMatchScheduler();
if (polygonKey) {
  startRefreshScheduler(polygonKey);
  startRotationScheduler(polygonKey);
  startStockRealtimeIngestor(polygonKey);
}
if (twelveKey) {
  startForexScheduler(twelveKey);
  startForexRealtimeIngestor(twelveKey);
  startCryptoScheduler(twelveKey);
  startCryptoRealtimeIngestor(twelveKey);
}

const httpServer = app.listen(PORT, '0.0.0.0', () => {
  console.log(`tongxin-backend listening on http://localhost:${PORT} (0.0.0.0:${PORT})`);
  createChatWsServer(httpServer);
  const { isAuthConfigured } = require('./lib/authMiddleware');
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  const fs = require('fs');
  const path = require('path');
  if (!isAuthConfigured()) {
    const hasJson = !!process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
    const absPath = credPath ? path.resolve(process.cwd(), credPath) : null;
    const exists = absPath && fs.existsSync(absPath);
    console.warn('');
    console.warn('*** 鉴权未就绪：聊天/好友等接口将返回 503 ***');
    if (hasJson) {
      console.warn('  FIREBASE_SERVICE_ACCOUNT_JSON 已配置但解析失败，请检查 JSON 格式');
    } else if (credPath && !exists) {
      console.warn(`  serviceAccountKey.json 不存在，路径: ${absPath}`);
      console.warn('  本地开发：下载 JSON 保存为 serviceAccountKey.json');
      console.warn('  云部署：将 JSON 内容设为环境变量 FIREBASE_SERVICE_ACCOUNT_JSON');
    } else if (!credPath) {
      console.warn('  本地：GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json');
      console.warn('  云部署：FIREBASE_SERVICE_ACCOUNT_JSON=<完整 JSON 字符串>');
    }
    console.warn('');
  }
});
