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
const { startRefreshScheduler } = require('./lib/refreshScheduler');
const { startRotationScheduler } = require('./lib/rotationScheduler');

const app = express();
const PORT = process.env.PORT || 3000;
const polygonKey = process.env.POLYGON_API_KEY?.trim() || null;
const twelveKey = process.env.TWELVE_DATA_API_KEY?.trim() || null;

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'tongxin-backend' });
});

registerRoutes(app, polygonKey, twelveKey);
if (polygonKey) {
  startRefreshScheduler(polygonKey);
  startRotationScheduler(polygonKey);
}

app.listen(PORT, '0.0.0.0', () => {
  console.log(`tongxin-backend listening on http://localhost:${PORT} (0.0.0.0:${PORT})`);
});
