# 美股领涨榜/表格显示 — 字段与 API 能力对照

参考你提供的 Moomoo 风格表格，下面按「当前能否拿到」和「数据来源」分类说明。

---

## 一、当前 API 已能拿到的数据（可直接展示）

| 参考列名 | 说明 | 当前数据来源 | 备注 |
|----------|------|--------------|------|
| **序号** | 行号 | 前端生成 | — |
| **代码** | 股票代码 | `PolygonGainer.ticker` | 领涨/领跌接口已有 |
| **名称** | 公司名称 | 搜索接口 `searchTickers` 返回 `name`；领涨榜原始 JSON 无 name | 领涨榜需按代码再查一次搜索或 Ticker Details，或维护代码→名称缓存 |
| **涨跌幅** | 当日涨跌百分比 | `PolygonGainer.todaysChangePerc` | ✅ |
| **最新价** | 当前价 | `PolygonGainer.price`（day.c 或 lastTrade） | ✅ |
| **涨跌额** | 当日涨跌额 | `PolygonGainer.todaysChange` | ✅ |
| **今开** | 今日开盘 | `PolygonGainer.dayOpen`（day.o） | ✅ |
| **昨收** | 昨收 | `PolygonGainer.prevClose`（prevDay.c） | ✅ |
| **最高/最低** | 当日最高/最低 | `PolygonGainer.dayHigh` / `dayLow` | ✅ |
| **成交量** | 当日成交量 | `PolygonGainer.dayVolume`（day.v） | ✅ 可格式化为「万/亿」 |

**指数（道琼斯/纳斯达克/标普）**：当前用 `getQuotes`（Polygon + Twelve Data）已有最新价、涨跌、涨跌幅，可做底部状态栏。

---

## 二、Polygon 有接口、但当前代码未接入的（可扩展）

| 参考列名 | 说明 | Polygon 能力 | 实现建议 |
|----------|------|--------------|----------|
| **所属行业** | 行业/板块 | `GET /v3/reference/tickers/{ticker}` 含 SIC/行业描述 | 新增 Ticker Details 请求（可批量或按需），缓存到本地 |
| **总市值/流通值** | 市值 | 同上，Ticker Details 有 market_cap、outstanding shares | 用收盘价×股本可算；流通值部分交易所数据不一定全，需看 Polygon 文档 |
| **总股本/流通股** | 股本 | 同上，outstanding shares 等 | 同上 |
| **5日/10日/20日/60日/120日/250日涨跌幅** | 多周期涨跌幅 | 已有 `getAggregates(symbol, 1, 'day', from, to)` 日 K | 按需要取 5/10/20/60/120/250 个交易日 bar，用首尾 close 算涨跌幅并展示 |
| **年初至今** | YTD 涨跌幅 | 同上，日 K 从年初取到昨日 | 同上，按日期范围算 |
| **成交额** | 金额 | 日 K 有 volume，成交额 = Σ(量×价) 或用 minute bar 近似 | 若 Polygon 分钟/日 bar 有 vw（成交额）则直接用；否则用 volume * 某均价近似 |

---

## 三、需要更高 Polygon 权限或额外数据源的

| 参考列名 | 说明 | 情况 |
|----------|------|------|
| **委比** | 买卖盘比例 | Polygon 的 `lastQuote`（买一/卖一）需 **Stocks Quote** 权限，当前若只有 Trades 则拿不到 |
| **买入价/卖出价、买量/卖量** | 盘口 | 同上，依赖 Quote 接口 |
| **盘前价/盘前涨跌** | 盘前行情 | Polygon 有盘前 session，需用带 session 的 snapshot 或 minute 接口（如 `include_extended_hours=true` 或指定 pre-market） |
| **换手率/振幅/量比** | 衍生指标 | 换手率 = 成交量/流通股本（需流通股）；振幅 = (最高−最低)/昨收；量比需历史均量，可用日 K 自己算 |

---

## 四、基本面/股息（Polygon 部分支持，需看订阅）

| 参考列名 | 说明 | 情况 |
|----------|------|------|
| **市盈率 TTM/静** | P/E | Polygon 有 Company Financials / Key Metrics 等接口，需对应订阅；否则需接其他数据源（如 FMP、Alpha Vantage） |
| **市净率** | P/B | 同上 |
| **股息率 TTM、近5年平均股息率、派息频率、股息连续增长、股息支付率** | 股息相关 | 同上，多为基本面/分红接口，需看 Polygon 或其它供应商 |

---

## 五、小结与建议

- **能立刻做的**：用现有 `PolygonGainer` + `MarketQuote` 做表格，列：序号、代码、名称（需查一次或缓存）、涨跌幅、最新价、涨跌额、今开、昨收、最高、最低、成交量；底部三大指数用现有 `getQuotes`。红绿配色、万/亿单位格式化即可。
- **短期可扩展**：接 Polygon `GET /v3/reference/tickers/{ticker}` 拿名称、行业、市值、股本；用现有 `getAggregates` 日 K 算 5/10/20/60/120/250 日涨跌幅和年初至今；有 Quote 权限后再加委比、买卖价量。
- **盘前、市盈率、市净率、股息**：依赖 Polygon 的盘前/基本面或 Quote 权限，或引入其他数据源，按产品优先级再排期。

如需，我可以按「先实现现有字段的表格 + 底部指数栏」给出一版 `gainers_losers_page` 或美股 Tab 的表格 UI 与数据绑定示例（列与 `PolygonGainer`/`MarketQuote` 的对应关系）。
