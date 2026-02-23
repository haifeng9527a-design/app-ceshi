# 行情页数据源对接说明

行情页（`lib/features/market/market_page.dart`）当前使用 **Mock 数据** 展示。要接入真实行情，可按下面方式对接。

---

## 1. 项目内已有能力

- **Polygon.io**（`lib/features/trading/polygon_repository.dart`）
  - 需 `.env` 配置 `POLYGON_API_KEY`
  - 已支持：最后成交 `getLastTrade`、前收 `getPreviousClose`、**领涨榜** `getTopGainers`、K 线聚合 `getAggregates`
  - 可直接用于「美股」Tab 的领涨/盘前榜，以及个股/指数当前价、涨跌幅、迷你 K 线

---

## 2. 行情页各模块建议数据源

| 模块       | 数据内容           | 建议对接方式 |
|------------|--------------------|--------------|
| 环球指数   | 道琼斯、纳斯达克、标普、恒生、日经等 | Polygon 指数 ticker（如 `I:DJI`）；或 Twelve Data / Alpha Vantage 全球指数接口 |
| 外汇       | 美元/新元、美元指数、黄金 | 专门外汇 API：Twelve Data、Alpha Vantage、OANDA；或 Polygon 外汇（若有订阅） |
| 债券       | 美国 2/5/10 年期国债收益率 | Polygon 债券、或 Treasury 官方/第三方债券 API |
| 加密货币   | BTC、ETH、SOL 等   | CoinGecko / CoinMarketCap / CryptoCompare API；或 Binance 等交易所公开行情 |
| 特色榜单   | 美股领涨/盘前/热议 | **Polygon 已支持** `getTopGainers`（领涨）、可扩展盘前等 |

---

## 3. 推荐 API 一览（按用途）

- **股票/指数（美股为主）**  
  - **Polygon.io**：已集成，有实时/前收/涨跌榜/K 线，作为唯一行情数据源。  
  - **Alpha Vantage**：免费额度有限，有全球指数与外汇。  
  - **Twelve Data**：股票、指数、外汇、加密货币都有，免费档可做开发测试。

- **外汇 / 贵金属**  
  - Twelve Data、Alpha Vantage、Polygon（若订阅外汇）。

- **加密货币**  
  - **CoinGecko API**（免费）：列表、价格、涨跌幅、sparkline。  
  - CoinMarketCap、CryptoCompare、交易所 REST（如 Binance）均可。

- **债券**  
  - Polygon 债券、或专注美债的第三方 API。

---

## 4. 对接步骤建议

1. **统一封装「行情」数据层**  
   - 新建 `lib/features/market/market_repository.dart`（或沿用/扩展 trading 下的 repository）。  
   - 对外提供：`Stream<List<MarketQuote>>` 或 `Future<List<MarketQuote>>` 按模块（指数/外汇/债券/加密货币）拉取。  
   - 内部按模块分别调用 Polygon、CoinGecko 等；未配置的 key 可回退到 Mock。

2. **迷你 K 线（sparkline）**  
   - Polygon：`getAggregates(symbol, multiplier: 1, timespan: 'hour', ...)` 或日 K，取 `c`（close）列表。  
   - 转成 `MarketQuote.sparkline`（`List<double>`）供 `_MiniChart` 使用。

3. **领涨榜**  
   - 已可用 `PolygonRepository().getTopGainers(limit: 10)`。  
   - 在 `_UsStocksTab` 中改为从 repository 取数，映射为 `List<MarketGainer>`，并处理加载中/错误态。

4. **公告条（如休市提醒）**  
   - 可从后端 CMS 或配置接口拉取一条「当前公告」；暂无则继续用本地占位或空。

5. **配置与风控**  
   - 所有 API Key 放在 `.env`，不提交仓库。  
   - 对免费版做限频（如 1 分钟 N 次）、缓存（如 1 分钟）避免超限。

---

## 5. 参考链接（开发时查阅）

- [Polygon.io API](https://polygon.io/docs)  
- [Twelve Data](https://twelvedata.com/docs)  
- [Alpha Vantage](https://www.alphavantage.co/documentation/)  
- [CoinGecko API](https://www.coingecko.com/en/api/documentation)  

当前 UI 与数据模型（`MarketQuote`、`MarketGainer`）已就绪，接入时只需在 repository 中返回同结构数据即可替换 Mock。
