# 关注交易员 IA / API / 开发拆分

更新时间：2026-04-16  
关联文档：[followed_traders_prd.md](/Users/arronlee/Documents/app-ceshi/docs/followed_traders_prd.md)

## 1. 文档目的

这份文档用于把 `关注交易员` 从产品方向继续细化到实现层，解决 3 件事：

- 页面到底怎么分区
- 现有接口哪些能直接用，哪些值得聚合
- 开发上怎么拆，避免关注页、交易员详情、跟单设置互相打架

## 2. 页面信息架构

## 2.1 页面层级

`关注交易员` 页建议拆成 5 层：

1. 页面头部总览
2. 搜索 / 筛选 / 排序工具栏
3. 关注交易员主列表
4. 交易员详情抽屉
5. 跟单操作弹层

## 2.2 顶部总览

建议放 4 个概览卡：

- 已关注交易员
- 正在跟单
- 今日活跃交易员
- 近 7 天正收益交易员

### 目标

- 让用户先判断关注池是不是“值得看”
- 给筛选和排序一个上下文

### 字段定义

- `watched_count`
- `copying_count`
- `active_today_count`
- `positive_7d_count`

## 2.3 工具栏

工具栏建议分成左右两组。

### 左侧

- 关系筛选
  - 全部
  - 仅关注未跟单
  - 正在跟单
  - 已暂停

### 右侧

- 最近活跃筛选
  - 全部
  - 7 天内有动作
  - 7 天内无动作
- 排序
  - 最近活跃
  - 总收益
  - 胜率
  - 近 7 天收益
  - 跟随者数
- 搜索
  - 昵称 / UID

## 2.4 关注交易员列表

列表建议桌面端双列卡片，移动端单列卡片。

每张卡片拆成 4 块：

### A. 身份头部

- 头像
- 昵称
- 交易员认证标签
- 是否允许跟单
- 关注日期
- 最近活跃时间
- 关系状态标签
  - 仅关注
  - 跟单中
  - 跟单暂停

### B. 表现指标

- 累计收益
- 胜率
- 最大回撤
- 跟随者数

### C. 近期状态

- 近 7 天收益
- 当前持仓数
- 最近一笔交易对
- 最近开/平仓时间

### D. 动作区

- 查看详情
- 立即跟单 / 继续跟单
- 取消关注

## 2.5 详情抽屉

桌面端建议用右侧抽屉，不要直接跳整页。  
移动端可以继续跳详情页。

抽屉结构建议：

1. 交易员头部
2. 核心表现
3. 当前仓位
4. 最近历史
5. 策略摘要
6. 底部动作区

### 当前仓位区

只展示当前还开的仓位：

- 交易对
- 多/空
- 数量
- 开仓价
- 当前价
- 未实现盈亏
- ROE

### 最近历史区

只展示最近 5 到 10 笔平仓：

- 交易对
- 开/平时间
- 已实现收益
- 收益率

## 2.6 跟单弹层

不在关注页直接内嵌大量设置项。  
点击 `立即跟单 / 继续跟单` 后，继续复用现有 `CopySettingsModal`。

## 3. 数据模型与字段口径

## 3.1 当前可直接复用

### `FollowedTrader`

来源：`getMyWatchedTraders`

可直接提供：

- `uid`
- `display_name`
- `avatar_url`
- `is_trader`
- `allow_copy_trading`
- `followed_at`
- `is_copying`
- `copy_status`
- `stats`

### `TraderStats`

可直接提供：

- `total_trades`
- `win_rate`
- `total_pnl`
- `avg_pnl`
- `max_drawdown`
- `followers_count`

### `CopyTrading`

来源：`getMyFollowing`

可直接提供：

- 跟单状态
- 已分配本金
- 可用本金
- 冻结本金
- 跟单分润比例
- 高水位

### `TraderPosition`

来源：`getTraderPositions`

可直接提供：

- `symbol`
- `side`
- `qty`
- `entry_price`
- `current_price`
- `unrealized_pnl`
- `roe`
- `created_at`

## 3.2 建议新增的聚合字段

当前关注页要做工作台，建议后端补这些字段：

- `recent_active_at`
- `recent_7d_pnl`
- `open_positions_count`
- `last_trade_symbol`
- `last_trade_side`
- `last_trade_at`
- `is_recently_active`

这些字段都不是新业务能力，本质上是聚合已有数据。

## 4. 接口设计

## 4.1 V1 推荐新增聚合接口

### 关注页工作台接口

`GET /api/trader/my-watched/dashboard`

#### 查询参数

- `relation`
  - `all`
  - `watch_only`
  - `copying`
  - `paused`
- `activity`
  - `all`
  - `active_7d`
  - `inactive_7d`
- `sort`
  - `recent_active`
  - `total_pnl`
  - `win_rate`
  - `followers`
  - `pnl_7d`
- `keyword`
- `limit`
- `offset`

#### 返回结构

```json
{
  "summary": {
    "watched_count": 12,
    "copying_count": 3,
    "active_today_count": 5,
    "positive_7d_count": 4
  },
  "items": [
    {
      "uid": "7959932303",
      "display_name": "arron",
      "avatar_url": "/uploads/...",
      "is_trader": true,
      "allow_copy_trading": true,
      "followed_at": "2026-04-13T12:00:00Z",
      "relation_status": "copying",
      "copy_status": "active",
      "stats": {
        "total_pnl": 319975.90,
        "win_rate": 48.3,
        "max_drawdown": 22.4,
        "followers_count": 2,
        "total_trades": 241
      },
      "recent_active_at": "2026-04-16T06:50:00Z",
      "recent_7d_pnl": 14320.44,
      "open_positions_count": 1,
      "last_trade_symbol": "BTC/USD",
      "last_trade_side": "long",
      "last_trade_at": "2026-04-16T06:50:00Z"
    }
  ],
  "total": 12
}
```

## 4.2 详情抽屉接口方案

V1 可以直接并发复用现有接口，不急着造新接口：

- `GET /api/trader/:uid/profile`
- `GET /api/trader/:uid/positions`
- `GET /api/trader/:uid/trades`
- `GET /api/trader/:uid/strategies`
- `GET /api/trader/my-following`

### V2 可考虑新增

`GET /api/trader/:uid/detail-dashboard`

聚合：

- profile
- stats
- current positions summary
- recent trade summary
- strategy summary
- my relation summary

## 4.3 对比接口

V2 建议：

`GET /api/trader/compare?uids=uid1,uid2,...`

先不做。

## 5. 前端组件拆分建议

## 5.1 页面级

- `FollowingOverviewHeader`
- `FollowingToolbar`
- `FollowingTraderGrid`
- `FollowingTraderCard`
- `TraderWatchDetailDrawer`

## 5.2 卡片级

- `TraderRelationshipBadge`
- `TraderPerformanceStats`
- `TraderRecentActivityBlock`
- `TraderActionBar`

## 5.3 抽屉级

- `TraderCurrentPositionsTable`
- `TraderRecentTradesList`
- `TraderStrategySummary`

## 6. 状态管理建议

## 6.1 页面状态

关注页建议维护这些状态：

- `relationFilter`
- `activityFilter`
- `sortBy`
- `keyword`
- `selectedTraderUid`
- `drawerOpen`
- `refreshing`

## 6.2 数据请求策略

### 关注列表

- 首屏直接打聚合接口
- 筛选变化重新拉取
- 搜索使用 250ms 防抖

### 抽屉

- 点击后并发拉详情相关接口
- 同一个 trader 打开第二次时可走短时缓存

## 7. 交互状态设计

## 7.1 卡片状态

### 仅关注

- 显示 `立即跟单`

### 正在跟单

- 显示 `查看跟单`
- 或 `继续跟单设置`

### 已暂停

- 显示 `恢复跟单`

## 7.2 取消关注提示

如果只是关注未跟单：

- 正常确认弹窗

如果已在跟单：

- 弹窗必须明确说明：
  - 取消关注不会自动取消跟单

## 8. 开发任务拆分

## Phase 1：聚合接口

### 后端

1. 新增 `my-watched/dashboard` handler
2. 聚合 watched traders、stats、copy relation、recent activity
3. 返回 summary + items + total

### 预估风险

- 近期活跃时间计算需要查 positions/trades
- 需要注意分页和排序性能

## Phase 2：前端工作台首页

### 前端

1. 重构 [following.tsx](/Users/arronlee/Documents/app-ceshi/tongxin-app/app/(tabs)/following.tsx)
2. 新增顶部总览
3. 新增工具栏
4. 新增增强卡片
5. 加详情抽屉入口

## Phase 3：详情抽屉

### 前端

1. 详情抽屉骨架
2. 并发拉 profile / positions / trades / strategies
3. 接入现有 `CopySettingsModal`

## Phase 4：体验增强

### 可选增强

1. 关注页最近动态
2. 风格标签
3. 风险评分
4. 多交易员对比

## 9. 建议的实现顺序

建议按这个顺序走：

1. 先补聚合接口
2. 再重构关注页主列表
3. 再做详情抽屉
4. 最后补动态和对比

原因很简单：

- 关注页现在最大问题是“信息太少”
- 先把工作台首页做起来，用户价值最大

## 10. 最终建议

关注交易员这条线不要再继续做成“列表 + 取消关注按钮”的轻页面。

更合适的方向是：

- 它是交易员观察工作台
- 它和跟单账户不是重复关系
- 它负责把“感兴趣”转化成“值得投入”

所以实现上也应该优先投资：

- 聚合信息
- 近期状态
- 快速转化路径

而不是继续只给几列静态数字。
