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
const { requireAuth, optionalAuth } = require('./lib/authMiddleware');
const { startRefreshScheduler } = require('./lib/refreshScheduler');
const { startRotationScheduler } = require('./lib/rotationScheduler');
const { createQuotesWsServer } = require('./lib/wsQuotes');

const app = express();
const PORT = process.env.PORT || 3000;
const polygonKey = process.env.POLYGON_API_KEY?.trim() || null;
const twelveKey = process.env.TWELVE_DATA_API_KEY?.trim() || null;

app.use(cors());
app.use(express.json());

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

registerRoutes(app, polygonKey, twelveKey);
registerUserRoutes(app, requireAuth);
registerFriendRoutes(app, requireAuth);
registerMessageRoutes(app, requireAuth);
registerTeacherRoutes(app, requireAuth, optionalAuth);
registerUploadRoutes(app, requireAuth);
registerMiscRoutes(app, requireAuth);
registerWatchlistRoutes(app, requireAuth);
if (polygonKey) {
  startRefreshScheduler(polygonKey);
  startRotationScheduler(polygonKey);
}

const httpServer = app.listen(PORT, '0.0.0.0', () => {
  console.log(`tongxin-backend listening on http://localhost:${PORT} (0.0.0.0:${PORT})`);
  createQuotesWsServer(httpServer, polygonKey);
  const { isAuthConfigured } = require('./lib/authMiddleware');
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  const fs = require('fs');
  const path = require('path');
  if (!isAuthConfigured()) {
    const absPath = credPath ? path.resolve(process.cwd(), credPath) : null;
    const exists = absPath && fs.existsSync(absPath);
    console.warn('');
    console.warn('*** 鉴权未就绪：聊天/好友等接口将返回 503 ***');
    if (credPath && !exists) {
      console.warn(`  serviceAccountKey.json 不存在，路径: ${absPath}`);
      console.warn('  请从 Firebase 控制台 (项目 cesium-29c23) -> 项目设置 -> 服务账号 -> 生成新私钥');
      console.warn('  下载 JSON 保存为: tongxin-backend/serviceAccountKey.json');
    } else if (!credPath) {
      console.warn('  请在 .env 中配置 GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json');
    }
    console.warn('');
  }
});
