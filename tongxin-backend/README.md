# tongxin-backend

通心应用后端：行情代理与缓存（Polygon / Twelve Data），可单独部署。

## 环境变量

- `PORT`：服务端口，默认 3000
- `POLYGON_API_KEY`：Polygon.io API Key（美股、指数、涨跌榜、搜索）
- `TWELVE_DATA_API_KEY`：Twelve Data API Key（外汇、加密货币、部分指数）
- `SUPABASE_URL`：Supabase 项目 URL（可选，用于股票报价缓存表）
- `SUPABASE_ANON_KEY` 或 `SUPABASE_SERVICE_ROLE_KEY`：Supabase 密钥（与上面同时配置后，报价会先读/写 Supabase 表 `stock_quote_cache`）

## 接口

- `GET /health` — 健康检查
- `GET /api/quotes?symbols=AAPL,SPX,EUR/USD` — 批量报价（与前端 MarketQuote 格式一致）
- `GET /api/candles?symbol=AAPL&interval=1day|5min|1min|1h` — K 线/分时
- `GET /api/gainers?limit=20` — 美股领涨榜
- `GET /api/losers?limit=20` — 美股领跌榜
- `GET /api/search?q=apple` — 标的搜索
- `GET /api/ratios?symbol=AAPL` — 财务比率（市盈率、市净率、股息率等）
- `GET /api/dividends?symbol=AAPL` — 分红历史
- `GET /api/splits?symbol=AAPL` — 拆股历史

后端使用**按 symbol 的缓存**（内存 → Supabase → SQLite）：
- **Supabase**（可选）：配置 `SUPABASE_URL` + `SUPABASE_ANON_KEY` 后，会在 Supabase 中读写表 `stock_quote_cache`，作为跨实例的报价缓存。需在 Supabase Dashboard → SQL Editor 中执行 `supabase/stock_quote_cache.sql` 建表。
- **内存 + SQLite**：`quote_snapshot` + `meta_symbol` 表，与 Supabase 并存；未配 Supabase 时行为与之前一致。
- **列表 `/api/quotes`**：批量查缓存（内存 → Supabase → SQLite），只对缺失/过期的 symbol 补拉 API；拉到的结果会写入内存、SQLite 和 Supabase。缺额较多时先快返已有数据并带 `partial: true`、`missingSymbols`、`serverTimeMs`，后台继续补拉写库。
- **SingleFlight**：同一 symbol 并发请求只打一次 Polygon，避免羊群。
- **后台刷新**：定时从 `meta_symbol` 按优先级取到期 symbol，在预算内拉取并写回，失败做指数退避。
- 其余接口（涨跌榜、K 线、搜索等）仍用通用 key-value 缓存。

## 运行

```bash
npm install
npm start
```

## 前端配置

在前端项目 `.env` 中配置后端地址后，前端将自动走后端代理（不再直连 Polygon/Twelve Data）：

```env
TONGXIN_API_URL=http://localhost:3000
```

或使用 `BACKEND_URL`。不配置时前端仍直连 Polygon/Twelve Data（需在 .env 配置对应 API Key）。
