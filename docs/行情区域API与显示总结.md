# 行情区域 API 与显示总结

本文档说明当前「行情」页使用的数据源、API 返回字段、在 App 中的显示方式，以及与常见看盘软件的对比与改进建议。

---

## 一、当前行情结构（MOMO 看盘风格 + 模拟数据兜底）

| Tab | 数据源 | 无 API/无数据时 |
|-----|--------|-----------------|
| **概况** | Twelve Data + 本地/DB 缓存 | 使用模拟数据，顶部显示「当前为模拟数据」提示 |
| **美股** | Polygon.io + 缓存/Supabase | 使用模拟领涨/领跌列表，显示「当前为模拟数据」提示 |
| **外汇** | Twelve Data | 使用模拟报价列表，显示模拟数据提示 |
| **加密货币** | Twelve Data | 使用模拟报价列表，显示模拟数据提示 |

- 有 API 且返回数据时：展示真实行情，无模拟提示。  
- 无 API、或接口报错、或返回空：自动回退到模拟数据，并明确标注「模拟数据，仅作界面展示」。

---

## 二、API 数据清单与显示方式

### 2.1 Polygon.io（美股领涨/领跌）

**接口**  
- 领涨：`GET /v2/snapshot/locale/us/markets/stocks/gainers`  
- 领跌：`GET /v2/snapshot/locale/us/markets/stocks/losers`  

**单条 ticker 返回字段（与 App 使用情况）**

| API 字段 | 类型 | 说明 | App 中解析 | 当前显示位置 |
|----------|------|------|------------|--------------|
| `ticker` | string | 股票代码 | ✅ PolygonGainer.ticker | 列表「代码」列 |
| `todaysChangePerc` | number | 当日涨跌幅(%) | ✅ todaysChangePerc | 列表「涨跌幅」列 |
| `todaysChange` | number | 当日涨跌额 | ✅ todaysChange | 列表「涨跌」列 |
| `updated` | number | 最后更新时间戳 | ✅ updated | 未展示 |
| `day.c` | number | 当日收盘/最新价 | ✅ price | 列表「最新」列 |
| `day.v` | number | 当日成交量 | ✅ dayVolume | 列表「成交量」列 |
| `day.o` | number | 当日开盘 | ✅ dayOpen | 已解析，可展示在详情页 |
| `day.h` | number | 当日最高 | ✅ dayHigh | 已解析，可展示在详情页 |
| `day.l` | number | 当日最低 | ✅ dayLow | 已解析，可展示在详情页 |
| `prevDay.c` | number | 昨收 | ✅ prevClose | 已解析，可展示在详情页 |
| `lastTrade.p` | number | 最近成交价 | ✅ 作 price 回退 | 与 day.c 二选一 |
| `min` / `lastQuote` | object | 分钟 bar / 最新报价 | ❌ 未解析 | - |

**列表展示**：排名(#)、代码、最新、涨跌、涨跌幅、成交量。表格支持横向滚动，避免小屏溢出。

**其他 Polygon 能力（行情相关）**

| 能力 | 接口/方法 | 显示位置 |
|------|-----------|----------|
| 最后成交价 | `getLastTrade(symbol)` | 股票详情页当前价、涨跌幅 |
| 前收 | `getPreviousClose(symbol)` | 详情页涨跌幅计算 |
| K 线/分时 | `getAggregates(...)` | 详情页分时图、K 线图 |
| 实时成交流 | WebSocket `PolygonRealtime` | 详情页实时价与成交量更新 |

---

### 2.2 Twelve Data（概况 / 外汇 / 加密货币）

**接口**  
- 报价：`GET /quote?symbol=...`（单 symbol 或批量逗号分隔）

**返回字段（与 App 使用情况）**

| API 字段 | 说明 | App 中解析 | 显示位置 |
|----------|------|------------|----------|
| `close` | 最新价 | ✅ TwelveDataQuote.close | 概况卡片、外汇/加密货币 Tab |
| `change` | 涨跌额 | ✅ change | 卡片 |
| `percent_change` | 涨跌幅(%) | ✅ percentChange | 卡片 |
| `open` / `high` / `low` | 开盘/最高/最低 | ✅ 已解析 | 可选展示 |
| `volume` | 成交量 | ✅ volume | 部分标的支持 |

**显示方式**：概况为网格卡片（名称、最新价、涨跌幅）；外汇/加密货币为列表或卡片，点击进入 `GenericChartPage` 看 K 线/分时。

---

### 2.3 本地缓存与 Supabase

- **TradingCache**：领涨/领跌列表、Polygon last trade、前收、Twelve Data quote、K 线/分时 bars，用于首屏秒出与限流。
- **MarketSnapshotRepository（Supabase）**：存储领涨/领跌 payload 与指数/外汇/加密货币快照，休市或新用户无本地缓存时从远端读取。

---

## 三、与常见看盘软件的对比

| 项目 | 常见看盘软件 | 本 App 当前 | 说明 |
|------|--------------|------------|------|
| **列表数据** | 代码、最新、涨跌、涨跌幅、成交量、开盘/最高/最低/昨收 | 有代码、最新、涨跌、涨跌幅、成交量；开盘/最高/最低/昨收已解析未在列表展示 | 列表可保持精简；开盘/最高/最低/昨收已在详情页或可加在详情页 |
| **K 线 / 分时** | 有 | 有（股票详情页） | Polygon getAggregates + 图表 |
| **实时价** | 有 | 有（详情页 WebSocket） | Polygon 实时成交流 |
| **搜索** | 有 | 仅图标，未实现跳转 | 建议接搜索页或自选 |
| **自选/关注** | 有 | 有「关注」Tab | 与行情并列 |
| **行情表布局** | 多可横向滚动或固定列 | 已改为横向滚动，避免溢出 | 已修复小屏黄色 overflow 问题 |
| **市盈率/市值/换手率** | 部分有 | 无 | Polygon snapshot 不提供，需另接参考数据接口 |

---

## 四、已完成的修复与建议

### 4.1 已完成

1. **表格溢出**：美股列表表头与数据行放入横向 `SingleChildScrollView`，最小宽度 560，避免小屏出现「overflow by X pixels」黄色调试文字。
2. **文本溢出**：列表行中代码、最新、涨跌、涨跌幅、成交量均加 `maxLines: 1` 与 `overflow: TextOverflow.ellipsis`。
3. **数据模型**：`PolygonGainer` 已增加 `dayOpen`、`dayHigh`、`dayLow`、`prevClose`，便于在股票详情页展示「开盘/最高/最低/昨收」。

### 4.2 建议后续

1. **股票详情页**：在 `StockChartPage` 或详情头部展示当日开盘、最高、最低、昨收（数据可从 Polygon snapshot 或 getPreviousClose + getAggregates 当日 bar 取得）。
2. **搜索**：实现行情页搜索图标跳转（搜索标的并进入详情或加入关注）。
3. **通知**：实现铃铛入口（涨跌提醒、系统通知等）。
4. **市盈率/市值**：若需与看盘软件对齐，需接入 Polygon Ticker Details 或其它参考数据 API，再在详情页展示。

---

## 五、如何自测 API 与显示

1. **环境**：`.env` 配置 `POLYGON_API_KEY`、`TWELVE_DATA_API_KEY`（概况/外汇/加密货币需要）。
2. **美股列表**：打开「行情 → 美股」，切换领涨/领跌，应看到约 20 条，含代码、最新、涨跌、涨跌幅、成交量；小屏下表格可横向滑动，无黄色溢出文字。
3. **概况**：切换「概况」，应看到指数/外汇/加密货币卡片与涨跌幅。
4. **详情**：点击任一股进入详情，应有分时/K 线、当前价、涨跌幅、实时更新（交易时段）。
5. **休市**：美股休市时领涨/领跌可能为空，此时会显示最近一次缓存或 Supabase 快照（若已配置并写入过快照）。

---

**文档版本**：基于当前 `market_page.dart`、`polygon_repository.dart`、`twelve_data_repository.dart`、`market_snapshot_repository.dart` 实现整理。
