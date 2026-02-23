# 行情 API 检查说明

## 当前使用的接口（均为 Polygon.io）

| 功能 | 接口 | 说明 |
|------|------|------|
| 涨幅前10 | `GET /v2/snapshot/locale/us/markets/stocks/gainers` | 美股涨幅榜，最少 1 万成交量，每日 4:00 AM EST 更新 |
| 当前价 / 最后成交 | `GET /v2/last/trade/{ticker}` | 单标的最后成交价、成交量、时间 |
| 前收（涨跌幅） | `GET /v2/aggs/ticker/{ticker}/prev` | 前一交易日 OHLC，用于计算涨跌幅 |
| 分时图 | `GET /v2/aggs/ticker/{ticker}/range/1/minute/{from}/{to}` | 1 分钟 K 线，from/to 毫秒时间戳 |
| K线图 | `GET /v2/aggs/ticker/{ticker}/range/1/day/{from}/{to}` | 日 K，from/to 毫秒 |
| 实时价格/成交量 | WebSocket `wss://socket.polygon.io/stocks` | 订阅 `T.{ticker}` 成交流，有成交即推送价格与手数 |

## 如何自测

1. **涨幅前10**  
   打开 App → 行情与交易 → 顶部「涨幅前10」区块应拉取并展示 10 只股票（需配置 `POLYGON_API_KEY`）。

2. **TNXP 分时 / K 线 / 实时价 / 成交量**  
   - 在搜索框输入 `TNXP` 并搜索。  
   - **实时价格与成交量**：选中 TNXP 后会自动连接 Polygon WebSocket；有成交时「当前价」和「成交量」会持续更新（美股交易时段有推送，非交易时段可能无新成交）。  
   - **分时图**：选「分时」→ 使用 Polygon 近 6 小时 1 分钟 K 线。每 1 分钟自动刷新。  
   - **K 线图**：选「K 线」→ 使用 Polygon 近 30 日日 K。每 5 分钟自动刷新。

3. **确认不是「取一次就不动」**  
   - 当前价/成交量：由 WebSocket 实时推送更新。  
   - 整体行情列表：每 20 秒 REST 刷新一次。  
   - 分时/K 线：分时每 1 分钟、K 线每 5 分钟自动重新拉取并刷新图表。

## 环境要求

- `.env` 中配置 `POLYGON_API_KEY`（必选，用于 REST + WebSocket）。  
- Polygon WebSocket 需账户具备相应权限（部分套餐为 15 分钟延迟，高级为实时）。
