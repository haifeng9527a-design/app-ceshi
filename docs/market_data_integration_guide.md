# 行情数据全量接入指南（实时价、成交量、分时图、K 线图）

本文说明如何在项目内接入并展示：**实时行情**、**成交量**、**分时图**、**K 线图** 等，全部基于 Polygon API。

---

## 一、项目内已有能力一览

| 能力 | 接口/类 | 说明 | 已用位置 |
|------|---------|------|----------|
| **最新价（REST）** | `PolygonRepository.getLastTrade(symbol)` | 返回 price、size、timestamp | 股票详情页顶部价格、交易 Tab |
| **前收价** | `PolygonRepository.getPreviousClose(symbol)` | 用于计算涨跌幅 | 详情页涨跌幅、列表 Chg% |
| **领涨/领跌榜** | `getTopGainers()` / `getTopLosers()` | 当日涨跌幅排行，含 price、todaysChange、todaysChangePerc | 行情 → 美股 Tab |
| **K 线/分时 bars** | `PolygonRepository.getAggregates(symbol, multiplier, timespan, fromMs, toMs)` | 返回 o/h/l/c/**volume**，支持 minute/day | 分时图、K 线图 |
| **实时成交流（WebSocket）** | `PolygonRealtime(symbol)` / `PolygonRealtimeMulti(symbols)` | 有成交即推送 price、size、timestamp | 交易页已用，行情可复用 |
**结论**：实时价、成交量、分时、K 线在现有代码里都有对应接口，只需在 UI 层按需调用并展示。

---

## 二、按需求接入方式

### 1. 实时行情（逐笔/最新价）

- **REST 轮询**（已有）  
  - 调用 `getLastTrade(symbol)`，建议间隔 ≥ 1 秒（你方已有 1s 缓存）。  
  - 用在：列表里「最新价」、详情页顶部「当前价」。

- **WebSocket 推送**（已有，推荐）  
  - 进入某只股票详情时：`final realtime = polygon.openRealtime(symbol); realtime.connect();`  
  - 监听 `realtime.stream`，收到 `PolygonTradeUpdate` 后更新 UI 的 price（及可选累加 size 做成交量）。  
  - 多标的列表页：用 `openRealtimeMulti(symbols)` 一次订阅多只，按 `update.symbol` 更新对应行。

**在股票详情页接实时价示例**（`stock_chart_page.dart`）：

- `initState` 里：`_realtime = _polygon.openRealtime(widget.symbol); _realtime?.connect();`  
- 订阅 `_realtime?.stream`，在 `setState` 里把 `update.price` 赋给 `_currentPrice`（并可累加 `update.size` 到当日成交量）。  
- `dispose` 里：`_realtime?.dispose();`

---

### 2. 成交量

- **单根 K 线/分时 bar 的成交量**  
  - Polygon 的 `getAggregates` 返回的每根 bar 里带 **`volume`**（`PolygonBar.volume`）。  
  - 分时图：用 `multiplier: 1, timespan: 'minute'` 的 bars，把每根 bar 的 `volume` 画在副图或表格。  
  - K 线图：用 `timespan: 'day'` 的 bars，同样有 `volume`，可放在 K 线下方柱状图。

- **当日累计成交量**  
  - **方式 A**：Polygon Snapshot 的 `day.v`（若你解析 gainers/losers 的 `day` 对象，可把 `v` 写入模型并在列表展示）。  
  - **方式 B**：WebSocket 成交流里对 `PolygonTradeUpdate.size` 按 symbol 累加，得到「实时累计成交量」。  
  - **方式 C**：用当日分钟 bar 加总：请求当日 `getAggregates(..., timespan: 'minute')`，对返回的 `PolygonBar.volume` 求和。

**在列表展示「成交量」**：  
- 若用 Snapshot：在 `PolygonGainer.fromJson` 里读 `day.v`，加到模型字段（如 `dayVolume`），在美股表格加一列 Volume。  
- 若用 WebSocket：在详情页对 `size` 累加即可；列表页可用 Snapshot 的 `day.v` 或暂不展示。

---

### 3. 分时图

- **数据源**：  
  - **Polygon**：`getAggregates(symbol, multiplier: 1, timespan: 'minute', fromMs, toMs)`，例如 `fromMs = 当日 9:30 对应毫秒`，`toMs = now`，得到当日分钟 bar。

- **已有用法**：  
  - `stock_chart_page.dart` 的 Intraday 已用 `getAggregates(..., timespan: 'minute')`（近 6 小时）。  
  - 每根 bar 含 o/h/l/c，一般用 **close** 连成折线即可；如需带量，用 `PolygonBar.volume` 画副图。

- **可选增强**：  
  - 副图显示「成交量」柱状图（每根分钟 bar 对应一根柱）。  
  - 末端接 WebSocket 最新价（你在交易页已有类似逻辑），分时线末端随成交实时延伸。

---

### 4. K 线图

- **数据源**：  
  - **Polygon**：`getAggregates(symbol, multiplier: 1, timespan: 'day', fromMs, toMs)`，例如最近 30 天。

- **已有用法**：  
  - `stock_chart_page.dart` 的 K-Line 已用 Polygon 日 K，并画蜡烛图（开高低收）。

- **可选增强**：  
  - K 线下方画 **成交量柱状图**（每根日 bar 的 `volume`）。  
  - 周期切换：5 日/30 日/90 日通过调整 `fromMs` 实现。

---

## 三、推荐接入顺序（在现有代码上做最小改动）

1. **股票详情页（StockChartPage）**  
   - 接 **WebSocket 实时价**：进入页时 `openRealtime(symbol)`，stream 更新 `_currentPrice`（及可选累加成交量）。  
   - 分时图末端用该实时价延伸（与现有 `_buildLineChart` 中接 `_currentPrice` 一致）。  
   - 可选：分时图下方加「成交量」副图（用 `getAggregates` 返回的 `PolygonBar.volume`）。

2. **美股列表**  
   - 可选：在 `PolygonGainer` 中解析 Snapshot 的 `day.v`，在表格加一列 **Volume**（当日量）。  
   - 若不做 Snapshot 解析，列表可暂不展示成交量，仅保留 Code / Latest / Change / Chg%。

3. **K 线图下方成交量**  
   - 使用现有 `getAggregates(..., timespan: 'day')` 的 `PolygonBar.volume`，在蜡烛图下方用柱状图绘制。

4. **限频与缓存**  
   - 保持现有策略：REST 按接口已有缓存（如 last trade 1s、aggregates 5min）；WebSocket 不占 REST 限频。  
   - 免费 Polygon 注意每分钟请求次数，避免对同一 symbol 高频轮询。

---

## 四、.env 配置（必须）

```env
# 美股行情、实时、K 线、分时、涨跌榜
POLYGON_API_KEY=你的 Polygon Key
```

---

## 五、代码位置速查

| 需求 | 数据从哪来 | 在哪个文件接 / 展示 |
|------|------------|----------------------|
| 实时价（列表/详情） | `getLastTrade` 或 WebSocket | `market_page.dart`（列表）、`stock_chart_page.dart`（详情） |
| 实时价（WebSocket） | `PolygonRealtime` / `PolygonRealtimeMulti` | `polygon_realtime.dart`，在详情页 initState 里 connect、stream 监听 |
| 涨跌幅 | `getPreviousClose` + last trade | 已用于详情页、列表 Chg% |
| 分时图 | `getAggregates(1, 'minute')` | `stock_chart_page.dart` → Intraday |
| K 线图 | `getAggregates(1, 'day')` | `stock_chart_page.dart` → K-Line |
| 单 bar 成交量 | `PolygonBar.volume` | 在画分时/K 线时同批数据，可画副图 |
| 当日累计量 | Snapshot `day.v` 或 WebSocket 累加 | 可选：`PolygonGainer` 扩展、详情页 WebSocket 累加 |

按上述顺序在现有页面对应位置接入即可实现「实时行情、成交量、分时图、K 线图」全量展示；需要我按某一步写出具体补丁（例如详情页 WebSocket + 成交量副图）可以指定文件和页面。
