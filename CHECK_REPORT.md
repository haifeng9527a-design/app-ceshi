# 代码与运行检查报告

## 1. 后端 (tongxin-backend)

### 1.1 语法与依赖
- `require('./lib/routes.js')`、`require('./lib/supabaseQuoteCache.js')` 无报错，模块加载正常。
- `.env` 已配置：`PORT`、`POLYGON_API_KEY`、`TWELVE_DATA_API_KEY`、`SUPABASE_URL`、`SUPABASE_ANON_KEY`。

### 1.2 本次改动核对
- **routes.js**
  - 已引入 `supabaseQuoteCache`，常量 `SUPABASE_FALLBACK_MAX_AGE_MS = 24h`。
  - 在 `await runPolygonFetch()` 之后、`res.json(ordered)` 之前：
    - 用 `needFallback` 筛出 `out[s]` 无有效价格（close 为空/≤0 或有 error_reason）的标的。
    - 若 `needFallback.length > 0` 且 `supabaseQuoteCache.isConfigured()`，则调用  
      `supabaseQuoteCache.getBySymbols(needFallback, SUPABASE_FALLBACK_MAX_AGE_MS)`。
    - 对返回结果中 `payload.close > 0` 的项用 `row.payload` 覆盖 `out[s]`。
  - `toQuoteSnapshot`、`fetchOneQuote` 引用正常。

### 1.3 重启后端
```bash
cd /Users/haifeng/Desktop/app---tongxin/tongxin-backend
# 若 3000 已被占用，先结束进程：
lsof -ti:3000 | xargs kill -9
# 启动
npm start
# 或
node server.js
```

---

## 2. 前端 (tongxin-frontend)

### 2.1 Lint
- `market_page.dart`、`intraday_chart.dart`、`backend_market_client.dart`、`stock_chart_page.dart`：**无 linter 报错**。

### 2.2 本次改动核对
- **market_page.dart**
  - `_loadQuotesForVisibleRange`：根据 `validCount`、`reason`、`isPolygonNoData` 设置 `_quoteLoadError` 文案；补拉成功后若有有效数据会清掉错误。
- **stock_chart_page.dart**
  - `_intradayLastDays`：1m→1，2d→2，3d→3，4d→4。
  - `_loadIntraday`：优先 `useBackend` 时 `getCandles(sym, '1min', lastDays: lastDays)`；否则走 Polygon 缓存/聚合；最后 Twelve 兜底带 `lastDays`；结尾 `list.sort((a, b) => a.time.compareTo(b.time))`。
- **backend_market_client.dart**
  - `getCandles` 支持 `lastDays`，会带 `fromMs`/`toMs` 请求；缓存 key 含时间范围。
- **market_repository.dart**
  - 调用后端时传入 `lastDays`。
- **intraday_chart.dart**
  - 多日按天等宽、日边界虚线、时间轴按日刻度等逻辑已按之前需求实现。

### 2.3 重启前端（Flutter）
```bash
cd /Users/haifeng/Desktop/app---tongxin/tongxin-frontend
flutter pub get
flutter run
# 若已打开设备/模拟器，直接 run；热重载可按 r，完整重启按 R
```

---

## 3. 数据流简要核对

| 环节 | 说明 |
|------|------|
| 列表报价 | 前端 → 后端 `/api/quotes?symbols=...` → 内存/Supabase(2min)/SQLite → 缺失则 Polygon → **无有效价格则 Supabase 24h 备份覆盖** → 返回。 |
| 分时多日 | 前端按 1/2/3/4 天传 `lastDays`，后端 `fromMs/toMs` 拉 1min，前端排序后给 IntradayChart，按天等宽+虚线。 |
| Supabase | 后端 `.env` 有 `SUPABASE_URL` + `SUPABASE_ANON_KEY`，`supabaseQuoteCache.isConfigured()` 为 true，休市/无数据时会用 `stock_quote_cache` 24 小时内数据覆盖。 |

---

## 4. 结论与建议

- **代码**：本次涉及的后端/前端文件语法与引用正常，逻辑与需求一致，前端 lint 通过。
- **重启**：需在本地终端按上面命令**手动重启**后端与前端（当前环境无法代为执行 kill/长期起进程）。
- **验证**：后端启动后可用  
  `curl -s "http://localhost:3000/api/quotes?symbols=AAPL"`  
  看返回是否含 `close` 或 Supabase 兜底后的数据；前端打开行情页美股列表，看是否有数据或预期提示条。
