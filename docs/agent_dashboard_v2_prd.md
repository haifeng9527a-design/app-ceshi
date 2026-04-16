# 代理后台 Dashboard v2 PRD

更新时间：2026-04-16
适用范围：`tongxin-agent-web`（Next.js 16，端口 3030）+ `tongxin-go`（后端）
关联页面：`/dashboard`、`/data-center/*`、`/team-overview`、`/risk-radar`、`/promotion`、`/commission-records`（已存在）
状态：待评审 → 排期开发

---

## 0. 文档信息

| 字段 | 值 |
|---|---|
| 文档版本 | v1.0 |
| 主要作者 | Product (Arron) + Eng |
| 影响系统 | tongxin-go / tongxin-agent-web / Postgres / 调度器 |
| 竞品参考 | Bitunix Agent Statistic（老/新系统两版对比） |
| MVP 周期 | P0 4 周 + P1 4 周 + P2 弹性 |

---

## 1. 背景

### 1.1 现状痛点

当前 `tongxin-agent-web` 的 `/dashboard` 是 6 张静态卡片堆数字（本月直推、本月级差、本月自返、累计佣金、子代理数、直推数）。问题：

1. **没有时间维度**：只能看「本月」与「累计」，无法横切日 / 周 / 季度
2. **没有图表**：纯数字，无法感知趋势、爆点、衰减
3. **没有团队结构透视**：看不出哪些 sub-agent 真正贡献，哪些只是挂名
4. **没有客户运营 hook**：无法识别高价值用户、流失风险用户
5. **没有招商弹药**：代理对外谈判时拿不出「我能给下级开多少%」的清晰展示
6. **没有 personalization**：所有代理看到的是同一个布局
7. **没有 mobile 适配**：移动端硬塞 desktop 布局

### 1.2 竞品参考（Bitunix）

| 模块 | Bitunix 老系统 | Bitunix 新系统 | 我们打算 |
|---|---|---|---|
| 5 KPI 顶栏 | ❌ 散在卡片里 | ✅ 紧凑横排 | ✅ 抄 |
| 6 张时间序列图 | ✅ 平铺 | ❌ 删掉 | 用「单图多 chip」更优解 |
| 单图多指标 chip 切换 | ❌ | ✅ 12 个 chip | ✅ 抄 + 加多选叠加 |
| 自定义可见 chip | ❌ | ✅ 齿轮配置 | ✅ 抄 |
| 直系/非直系数据切片 | ✅ 双线 | ✅ 双线 + Tab | ✅ 双线 |
| 团队概览（per sub-agent 表） | ❌ | ✅ 含最近活跃时间 | ✅ 抄 |
| 用户排行 | ❌ | ✅ 7 种排序指标 | ✅ 抄 |
| **用户流失预警** | ❌ | ✅ 5 种风险类型 | ✅ 抄 + **加一键触达** |
| 链接漏斗（点击→注册→首充→首交） | ❌ | ✅ 列在邀请链接表 | ✅ 抄 + **加 A/B 实验** |
| 数据中心（团队/直客/链接 三 tab） | ❌ | ✅ | ✅ 抄 |
| 实时事件流 | ❌ | ❌ | ✅ **我们独有**（已上线） |
| 自返佣（self） | ❌ | ✅ | ✅ 我们已支持 |
| 多语言 | ✅ | ✅ | P2 |
| 暗黑模式 | ❌ | ✅ | P1 |

### 1.3 我们的差异化定位

不做"再做一个 Bitunix"。在 Bitunix 新系统能力之上叠加 **5 个超越点**（详见 §3.2），让代理的工作流从"看数字"升级到"看见 → 决策 → 行动 → 复盘"完整闭环。

---

## 2. 目标与北极星指标

### 2.1 业务目标

- **G1**：让代理打开 dashboard 30 秒内回答 5 个核心问题（看见）
- **G2**：让代理可在 dashboard 直接执行 3 类高频运营动作（行动）
- **G3**：让代理留存率（30 天后仍登录后台）从 X% 提升到 1.5X%
- **G4**：让代理人均月度返佣中位数提升 20%（通过更好的运营工具）

### 2.2 北极星指标

`Daily Active Agents (DAA) × Average Actions per DAA`

支撑指标：
- DAU/MAU of agent-web
- 平均会话时长
- 「一键触达」按钮点击率
- 「智能阈值」开启率
- 「周报分享」生成数

### 2.3 5 个核心问题（G1 验收用）

1. 我下面这群人最近 7 天给我赚了多少？
2. 钱主要来自我直接邀请的人，还是我培养的子代理？
3. 我团队里 TOP 10 的客户是谁？
4. 哪些下级用户有流失风险，需要我去激活？
5. 我对外招商时，下级能拿到的费率是多少？

### 2.4 3 类高频动作（G2 验收用）

1. 一键复制 / 分享邀请链接
2. 给风险用户发激活消息 / 送优惠券
3. 给某个 sub-agent 调整费率

---

## 3. 设计原则与创新点

### 3.1 6 大设计原则

| # | 原则 | 解释 |
|---|---|---|
| P1 | **聚焦** | 单屏一个核心信息，多指标共用一张大图（避免视觉过载） |
| P2 | **可对比** | 任意两个指标可叠加同图（自动归一化双 Y 轴） |
| P3 | **可行动** | 每条数据旁边都有「下一步该怎么办」按钮 |
| P4 | **有节奏** | 实时 SSE 推送，新交易触发数字滚动+脉冲动画 |
| P5 | **可分享** | 一键生成可发朋友圈/Telegram 的代理周报长图 |
| P6 | **个性化** | 用户可隐藏不关心的指标 / 自定义阈值 / 收藏报表 |

### 3.2 5 个超越竞品的创新点

#### ★ 创新 1：多指标叠加对比（vs Bitunix 单图单指标）
- chip 默认单选，但有「+ 多选」toggle
- 多选后最多支持 3 条线叠加，自动归一化（左 Y 轴绝对值，右 Y 轴指数）
- 用例：「我想看『新增用户』和『佣金』是否正相关」

#### ★ 创新 2：风险用户一键触达（vs Bitunix 只展示无操作）
- 流失预警表每行右侧 4 个 inline action：
  - 💬 发激活消息（调 IM 客服模板）
  - 🎁 送优惠券（调活动接口）
  - 📞 提醒下级 sub-agent（如果用户不是直系）
  - 🔍 查看详情
- 批量勾选 → 批量触达

#### ★ 创新 3：智能阈值（vs Bitunix 全局固定 50%）
- 「交易量下滑」阈值不是写死 50%
- 算法：基于该用户过去 30 天均值动态计算
  - 日均 $100 用户：掉到 $40 触发（60%）
  - 日均 $10000 用户：掉到 $7000 触发（30%）
- 用户可手动覆盖默认算法（齿轮设置）

#### ★ 创新 4：实时推送 + 脉冲动画（vs Bitunix 定时刷新）
- SSE 通道：后端在 `commission_events` 写入时推送给在线代理
- 前端：对应数字 +N 滚动动画 + 卡片边框脉冲 1 次（绿色=收益，红色=风险）
- 顶部 toast：「下级 7959** 刚交易了 +0.32 USDT」可点击直达事件流

#### ★ 创新 5：一键周报长图分享（Bitunix 无）
- 顶部 CTA：「📊 生成周报」
- 后端 SSR 渲染长图（PNG / 9:16），含本周 KPI、TOP 3 贡献人、个人邀请二维码
- 前端：调起原生分享 / 复制图片到剪贴板
- 用例：代理发朋友圈炫成绩，附带二维码自然引流

---

## 4. 信息架构

### 4.1 整站导航（侧栏）

```
🏠  概览              → /dashboard
📊  数据中心
    ├ 团队统计       → /data-center/team
    ├ 直客统计       → /data-center/direct
    └ 链接统计       → /data-center/links
👥  团队管理
    ├ 团队概览       → /team-overview
    ├ 子代理         → /sub-agents       (已存在)
    └ 风险雷达       → /risk-radar       (★ 创新点 2)
💎  返佣
    ├ 返佣明细       → /commission-records (已存在)
    └ 实时事件       → /commission-records?view=events (已存在)
🚀  推广工具
    ├ 邀请链接       → /invite-links     (已存在)
    ├ 海报中心       → /promotion/posters (P1)
    └ 周报生成       → /promotion/weekly  (★ 创新点 5)
⚙️  个人中心
    ├ 申请记录       → /agent-application (已存在)
    └ 设置           → /settings
```

### 4.2 路由对照（新增 / 改动）

| 路由 | 状态 | 说明 |
|---|---|---|
| `/dashboard` | 重写 | Bitunix 新系统结构 + 5 个创新点 |
| `/data-center/team` | 新增 | per-sub-agent 排名 |
| `/data-center/direct` | 新增 | per-end-user 排名 |
| `/data-center/links` | 新增 | per-link 漏斗 |
| `/team-overview` | 新增 | 团队全景树状图 + 下钻 |
| `/risk-radar` | 新增 | 流失预警 + 一键触达 |
| `/promotion/weekly` | P2 | 周报生成 |
| `/promotion/posters` | P2 | 海报中心 |
| `/business-stats` | 废弃 | 数据迁移到 `/data-center` |

---

## 5. 详细功能模块

### 5.1 Dashboard / Overview 页（M1～M9）

布局（desktop ≥ 1280）：

```
┌── 顶栏 ─────────────────────────────────────────────────┐
│ 👤 你好 Arron · 你的代理 ID: 7959932303 · 当前等级 LV3   │
│         [生成周报] [访问老后台] [🌙] [🌐] [⚙️]          │
└──────────────────────────────────────────────────────────┘

┌── M0: Today's Hit List (★ 创新 0) ──────────────────────┐
│ 💡 今日建议：                                            │
│ 1. jong 团队有 3 名 30 天未登录用户 → [一键提醒]         │
│ 2. 链接 hectorx 上周转化率掉到 2% → [对比] [新建 A/B]    │
│ 3. 你有 4789 USDT 待结算 → 明天 UTC 00:00 到账           │
└──────────────────────────────────────────────────────────┘

┌── M1: 邀请招商卡 ──┐ ┌── M2: 账户概览 ───────────────┐
│ My Invitations    │ │ Team Size  Direct  Sub Partners│
│ ┌──┬──────┬─────┐ │ │   124       54       70        │
│ │  │ 我的%│下级%│ │ ├──────────────────────────────────┤
│ │合│ 80% │ 20% │ │ │ Recently Registered      [更多→]│
│ │现│ 50% │ 30% │ │ │ UID    | 来源   | 时间          │
│ └──┴────┴─────┘   │ │ 4312** | jong   | 2025-12-11   │
│ Referral Link [📋]│ │ 4541** | jong   | 2025-12-10   │
│ Referral Code [📋]│ │ 5899** | direct | 2025-11-20   │
│ [🚀 立即邀请]      │ │ 5756** | direct | 2025-11-19   │
└───────────────────┘ │ 5723** | jong   | 2025-11-17   │
                      └──────────────────────────────────┘

┌── M3: 5-KPI 概览 ────────────────────────────────────────┐
│ 注册   我的佣金   总手续费   首入金人数   首交易人数      │
│ 123    97,478.61  400,514.61      66           62         │
│ ↑12%   ↓3% 7d     ↑8% 7d        ↑15%         ↑20%        │
└───────────────────────────────────────────────────────────┘

┌── M4: 指标表现（核心图）─────────────────────────────────┐
│ [📈] [📊] [🥧]  [+ 多选叠加 OFF]   [⚙️]    [📅 7天 ▾]   │
│ ┌────────────────────────────────────────────────────────┐│
│ │ chip: 我的佣金 · 新增用户 · 总交易量 · 总手续费        ││
│ │       首入金人数 · 首入金额度 · 首交易人数             ││
│ │       入金人数 · 入金额度 · 出金人数 · 出金额度        ││
│ └────────────────────────────────────────────────────────┘│
│  [选中：我的佣金]                                          │
│  ┌──────────────────────────────────────────────────┐     │
│  │   ▁▃▅█▇▅▃▁                                       │     │
│  │   蓝实线：总收益                                  │     │
│  │   绿虚线：直系直客                                │     │
│  │   橙虚线：非直系直客                              │     │
│  └──────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────┘

┌── M5: 团队全景 (★创新3 树状图) ──────────────────────────┐
│ [Treemap：每块 = 一个 sub-agent，面积 = 本月贡献返佣]    │
│ jong (40%) | mary (25%) | tom (15%) | 其他 (20%)        │
│              [点击块 → 跳转 /team-overview?uid=...]      │
└────────────────────────────────────────────────────────────┘

┌── M6: 风险用户雷达 (★创新2 一键触达) ────────────────────┐
│ [未入金 5] [未登录 12] [未交易 8] [净入金<0 3] [掉量 7] │
│ UID    | 上次活跃    | 当前资产 | 操作                 │
│ 9216** | 2025-12-20 | 64.56    | 💬🎁📞🔍              │
│ 5446** | 2025-11-03 | 731.18   | 💬🎁📞🔍              │
│ ...                            [批量勾选 → 批量触达]    │
└────────────────────────────────────────────────────────────┘

┌── M7: 邀请链接漏斗 ──────────────────────────────────────┐
│ 邀请码  | 我的/直客% | 点击 | 注册 | 首充 | 首交 | 交易量│
│ ZTPJ    | 80%/0%     |  -   |  -   |  -   |  -   |   -   │
│ hectorx | 50%/30%    | 1052 | 124  |  66  |  62  | 993M  │
│         转化漏斗：12% → 53% → 94%                         │
└────────────────────────────────────────────────────────────┘

┌── M8: 实时事件流（已有，缩略）─────────────────────────┐
│ 最近 5 条事件     [更多 → /commission-records]            │
└────────────────────────────────────────────────────────────┘

┌── M9: 合规说明 ──────────────────────────────────────────┐
│ ⓘ 交易数据按实时汇率计算；出入金按交易成功时汇率折算     │
│ ⓘ T+1 UTC 00:00 自动结算到账户余额                       │
└────────────────────────────────────────────────────────────┘
```

#### M0：Today's Hit List（创新 0）

- 后端跑一个轻量推荐引擎，每小时刷新一次
- 规则集（不是 ML，是 if-else，可解释）：
  - 规则 R1：「直系直客中有 N 名 30 天未登录」→ 推荐"一键提醒"
  - 规则 R2：「某邀请链接 7 天 CTR 同比下降 ≥ 30%」→ 推荐"对比 / 新建 A/B"
  - 规则 R3：「待结算金额 ≥ 100 USDT」→ 推荐"查看明细"
  - 规则 R4：「子代理人均贡献低于团队中位数」→ 推荐"查看 sub-agent 详情"
  - 规则 R5：「本月新增 vs 上月 -50%」→ 推荐"投放新海报"
- 至多 3 条；按 score 降序；每条带 [一键执行] 按钮

#### M1：邀请招商卡

- 双费率表：行 = 产品（合约 / 现货），列 = 我的% / 下级默认%
- 邀请链接 + Code：单击复制（toast 反馈），不需要打开新页面
- 「立即邀请」绿色 CTA：调起系统分享（Web Share API）/ 二维码弹窗

#### M2：账户概览

- 三大数字：Team Size / Direct / Sub Partners
  - Team Size = 整棵子树用户数（递归 CTE）
  - Direct = 直接邀请的用户数
  - Sub Partners = 直接邀请的用户中 `is_agent = true` 的数量
- Recently Registered：最近 5 条，复用 `/api/referral/invitees?limit=5`
- 「来源」列：如果 inviter_uid != caller，则展示 sub-agent 的 display_name；否则展示「direct」

#### M3：5-KPI 顶栏

| KPI | 字段 | 同比比较窗口 |
|---|---|---|
| 注册用户 | 当期新增直推+非直推总数 | 上一同周期 |
| 我的佣金 | sum(commission_amount) for inviter_uid=me | 上一同周期 |
| 总手续费 | sum(fee_base) for events 中 inviter_uid=me | 上一同周期 |
| 首入金人数 | distinct user_uid 第一次充值且 user.inviter_uid 在我子树 | 上一同周期 |
| 首交易人数 | 同上但 first trade | 上一同周期 |

每个 KPI 下方一行小字 `↑12%` / `↓3%`（绿/红）。

#### M4：指标表现核心图（创新 1）

- 12 个 chip 横向滚动：我的佣金 / 新增用户 / 总交易量 / 交易人数 / 总手续费 / 首入金用户 / 首入金额度 / 首交易用户 / 入金人数 / 入金额度 / 出金人数 / 出金额度
- 默认单选；toggle ON 后变多选（最多 3）
- 多选时：
  - 自动归一化（每条线归一到 [0, 1] 区间，鼠标 hover 显示原值）
  - 双 Y 轴：左轴 = 第 1 chip 原值，右轴 = 第 2/3 chip 原值
- 图表类型：折线 / 柱状 / 饼图（饼图仅在多选 OFF 且选「占比」类指标时启用）
- 齿轮：用户可隐藏不关心的 chip，配置写入 `users.dashboard_prefs JSONB`
- 日期：默认 7 天；可选 今天 / 昨天 / 7 天 / 30 天 / 全部 / 自定义
- 每条线分 3 系列：总值（实线）/ 直系直客（虚线绿）/ 非直系直客（虚线橙）

#### M5：团队全景树状图（创新 3）

- recharts `<Treemap>` 组件
- 每块 = 一个 sub-agent；颜色深度 = 贡献占比
- 块面积 = 当前日期窗口内该 sub-agent 团队产出的返佣金额
- 鼠标 hover：tooltip 显示 sub-agent 名称、UID、贡献金额、占比
- 单击：跳转 `/team-overview?uid={sub_agent_uid}` 下钻
- 占比 < 5% 的合并到「其他」块
- 空数据态：显示「你还没有 sub-agent，去培养第一个 →」

#### M6：风险用户雷达（创新 2）

5 个 tab：
1. 未入金（注册 ≥ 7 天且 deposit = 0）
2. 未登录（last_login ≥ 30 天）
3. 未交易（注册 ≥ 7 天且无任何成交）
4. 净入金 < 0（累计提现 > 累计入金）
5. 交易量下滑（动态阈值，详见创新 3）

每 tab 表格：UID / 上次活跃 / 当前资产 / 操作（4 个图标按钮）

操作按钮：
- 💬 发激活消息：弹 modal，预填模板（用户名、奖励金额、CTA 链接），可编辑后发送
- 🎁 送优惠券：调 `POST /api/agent/coupons/grant`，需要事先在「活动中心」配置可用券
- 📞 提醒 sub-agent：如果该用户不是 caller 直系，调 IM 给该用户的直接 inviter
- 🔍 查看详情：跳转 `/users/{uid}` 用户详情页

批量：表头复选框 → 批量触达 modal

齿轮：自定义阈值
```
未入金天数：[ 7 ] 天
未登录天数：[30 ] 天
未交易天数：[ 7 ] 天
交易量下滑：[ ] 固定 50%   [✓] 智能（基于用户均值）
```

#### M7：邀请链接漏斗

- 复用现有 `/invite-links` 数据
- 加列：点击数 / 注册数 / 首充数 / 首交数 / 累计交易量 / 双费率
- 「转化漏斗」迷你图：3 段水平条 stacked，颜色梯度
- 行操作：复制 / 分享 / 禁用 / 创建 A/B 变体（P1）

#### M8：实时事件流（缩略）

- 复用 `commission-records?view=events` 接口，limit=5
- 每条带 SSE 推送动画（创新 4）

#### M9：合规说明

固定底部一行小字。

---

### 5.2 数据中心 `/data-center/*`

3 个 sub-tab：

#### 5.2.1 团队统计 `/data-center/team`

- 表格：每行 = 一个直系下级（含 sub-agents 和直客，但通常 sub-agents 为主）
- 列：序号 / 名称-UID / 团队人数 / 新增用户 / 我的收益 / 团队总佣金
- 顶部筛选：UID 搜索 / 时间范围 / 排序指标 / 升降序
- 行操作：查看详情（→ `/team-overview?uid=...`）
- 导出 CSV

#### 5.2.2 直客统计 `/data-center/direct`

- 表格：每行 = 一个 end-user
- 列：UID / 注册时间 / 累计入金 / 累计出金 / 累计交易量 / 累计手续费 / 我从他身上赚的佣金
- 7 种排序指标：交易量 / 手续费 / 我的收益 / 入金额度 / 出金额度 / 净入金 / 当前余额
- 直系/非直系 toggle
- 导出 CSV

#### 5.2.3 链接统计 `/data-center/links`

- 表格：每行 = 一个邀请链接
- 列：链接名 / Code / 点击 / 注册 / 首充 / 首交 / 总交易量 / 转化率 / 状态
- 漏斗 mini-chart 列
- 行操作：详情（按日期看转化曲线）

---

### 5.3 团队概览 `/team-overview`

- 不带 query 参数：展示我的整棵团队 treemap（同 M5）
- 带 `?uid=xxx`：展示该 sub-agent 的详细贡献页

详细贡献页布局：

```
[← 返回] jong (UID 694564164)

┌─ 基本信息 ────────────────────────────────────────────┐
│ 团队人数 34 | 直客 22 | 子合伙人 12                   │
│ 最近加入 2025-12-11 | 最近交易 2026-04-13            │
│ 最近充值 2026-04-13 | 最近提现 2026-04-13            │
└────────────────────────────────────────────────────────┘

[团队筛选: jong ▾]    [日期范围: 2026-04-16 ▾]

┌─ 我的收益 ──────────────┐ ┌─ 新增用户 ─────────────┐
│ 团队总佣金     0 USDT   │ │ 总新增用户          0 │
│ 直系直客佣金   0 USDT   │ │ 当前合伙人贡献      0 │
│ 当前合伙人贡献 0 (0%)   │ │ (0%)                  │
│ [chart 双系列对比]      │ │ [chart 双系列对比]    │
└─────────────────────────┘ └────────────────────────┘

┌─ 交易额 ────────────────┐ ┌─ 手续费 ────────────────┐
│ 团队总交易额            │ │ 团队总手续费            │
│ 当前合伙人贡献 (0%)     │ │ 当前合伙人贡献 (0%)     │
└─────────────────────────┘ └─────────────────────────┘

┌─ 入金 ─────────────────┐ ┌─ 出金 ─────────────────┐
│ 团队总入金              │ │ 团队总出金              │
│ 当前合伙人贡献 (0%)     │ │ 当前合伙人贡献 (0%)     │
└─────────────────────────┘ └─────────────────────────┘
```

---

### 5.4 风险雷达 `/risk-radar`

详细页（M6 是缩略入口，详细页支持高级运营动作）

- 5 tab 同 M6
- 高级筛选：注册时间段、累计入金区间、风险等级（高/中/低，根据综合分数计算）
- 批量动作：除发消息/送券外，新增 [打标签] [加入私域群] [导出名单]
- 历史触达记录：每个用户旁边显示「上次触达时间 / 触达类型」，避免短期重复打扰

---

## 6. 数据契约 (API)

### 6.1 后端新增 endpoints

| 路径 | 方法 | 用途 | 优先级 |
|---|---|---|---|
| `/api/agent/overview/header` | GET | M1+M2 数据（不依赖日期） | P0 |
| `/api/agent/overview/kpi` | GET | M3 5-KPI 数据（含同比） | P0 |
| `/api/agent/overview/timeseries` | GET | M4 时间序列（多 chip） | P0 |
| `/api/agent/overview/treemap` | GET | M5 团队全景 | P0 |
| `/api/agent/risk/users` | GET | M6 风险用户列表 | P0 |
| `/api/agent/risk/threshold` | PUT | 风险阈值配置 | P1 |
| `/api/agent/risk/touch` | POST | 一键触达（创新 2） | P1 |
| `/api/agent/data-center/team` | GET | 5.2.1 团队统计 | P0 |
| `/api/agent/data-center/direct` | GET | 5.2.2 直客统计 | P0 |
| `/api/agent/data-center/links` | GET | 5.2.3 链接统计 | P0 |
| `/api/agent/team-overview/:uid` | GET | 5.3 sub-agent 下钻 | P0 |
| `/api/agent/today/recommendations` | GET | M0 今日建议（创新 0） | P1 |
| `/api/agent/dashboard/prefs` | GET/PUT | 个性化偏好 | P1 |
| `/api/agent/sse/events` | GET (SSE) | 实时推送（创新 4） | P1 |
| `/api/agent/weekly-report/generate` | POST | 周报长图（创新 5） | P2 |

### 6.2 关键 endpoint 详细 schema

#### 6.2.1 `GET /api/agent/overview/header`

无参数。

返回：
```json
{
  "uid": "7959932303",
  "agent_level": "LV3",
  "rates": {
    "futures": {"my": 0.80, "default_invitee": 0.20},
    "spot":    {"my": 0.50, "default_invitee": 0.30}
  },
  "team": {
    "team_size": 124,
    "direct_referrals": 54,
    "sub_partners_count": 70
  },
  "recently_registered": [
    {
      "uid": "431283167",
      "inviter_uid": "694564164",
      "inviter_display_name": "jong",
      "is_direct": false,
      "registered_at": "2025-12-11T08:47:51Z"
    }
  ],
  "invitation": {
    "default_link": "https://tongxin.com/register?code=hectorx",
    "default_code": "hectorx"
  }
}
```

#### 6.2.2 `GET /api/agent/overview/kpi?from=2026-04-09&to=2026-04-16`

返回：
```json
{
  "from": "2026-04-09",
  "to": "2026-04-16",
  "compare_from": "2026-04-02",
  "compare_to": "2026-04-09",
  "kpis": {
    "registered_users":   {"value": 123,       "delta_pct": 0.12},
    "my_commission":      {"value": 97478.61,  "delta_pct": -0.03},
    "total_fee":          {"value": 400514.61, "delta_pct": 0.08},
    "first_deposit_users":{"value": 66,        "delta_pct": 0.15},
    "first_trade_users":  {"value": 62,        "delta_pct": 0.20}
  }
}
```

#### 6.2.3 `GET /api/agent/overview/timeseries?from=&to=&metrics=my_commission,new_users&split=referral_source`

`metrics`：逗号分隔，最多 3 个，可选值：
`my_commission` / `new_users` / `total_volume` / `trade_users` / `total_fee` / `first_deposit_users` / `first_deposit_amount` / `first_trade_users` / `deposit_users` / `deposit_amount` / `withdraw_users` / `withdraw_amount`

`split`：可选 `referral_source`（按 直系 / 非直系 拆）/ `none`

返回：
```json
{
  "from": "2026-04-09",
  "to": "2026-04-16",
  "tz": "UTC",
  "granularity": "day",
  "series": [
    {
      "metric": "my_commission",
      "unit": "USDT",
      "total": 97478.61,
      "split_total": {
        "from_direct": 90597.15,
        "from_indirect": 6881.46
      },
      "points": [
        {"date": "2026-04-09", "total": 12.5, "from_direct": 10, "from_indirect": 2.5},
        {"date": "2026-04-10", "total": 0,    "from_direct": 0,  "from_indirect": 0}
      ]
    }
  ]
}
```

#### 6.2.4 `GET /api/agent/overview/treemap?from=&to=`

返回：
```json
{
  "from": "...",
  "to": "...",
  "items": [
    {
      "sub_agent_uid": "694564164",
      "sub_agent_name": "jong",
      "team_size": 34,
      "contribution_commission": 281.36,
      "contribution_pct": 0.40
    }
  ],
  "others": {"contribution_commission": 50.5, "contribution_pct": 0.07}
}
```

#### 6.2.5 `GET /api/agent/risk/users?type=no_login&limit=50&offset=0`

`type`：`no_deposit` / `no_login` / `no_trade` / `negative_net_flow` / `volume_drop`

返回：
```json
{
  "type": "no_login",
  "threshold_days": 30,
  "threshold_mode": "fixed",
  "users": [
    {
      "uid": "921638111",
      "display_name": "user***",
      "is_direct": true,
      "inviter_uid": "7959932303",
      "last_login_at": "2025-12-20T05:42:29Z",
      "current_assets_usd": 64.56,
      "deposit_total": 1000,
      "withdraw_total": 800,
      "trade_volume_30d": 0,
      "last_touched_at": null,
      "last_touch_kind": null
    }
  ],
  "total": 12
}
```

#### 6.2.6 `POST /api/agent/risk/touch`

请求：
```json
{
  "user_uids": ["921638111", "544661184"],
  "kind": "message",      // message | coupon | notify_sub
  "template": "reactivation_v1",
  "params": {
    "coupon_id": "WELCOME_BACK_10",
    "custom_text": "好久不见，回来送你 10 USDT 体验金"
  }
}
```

返回：
```json
{
  "success": ["921638111"],
  "failed": [
    {"uid": "544661184", "reason": "user opted out of marketing"}
  ]
}
```

#### 6.2.7 `GET /api/agent/dashboard/prefs` & `PUT`

GET 返回：
```json
{
  "visible_metrics": ["my_commission", "new_users", "total_volume", "total_fee"],
  "default_date_range": "7d",
  "risk_thresholds": {
    "no_deposit_days": 7,
    "no_login_days": 30,
    "no_trade_days": 7,
    "volume_drop_mode": "smart"
  },
  "show_today_hit_list": true,
  "default_chart_type": "line"
}
```

PUT body：同上结构（部分字段可省略）。

#### 6.2.8 `GET /api/agent/sse/events`

SSE stream，`Content-Type: text/event-stream`

事件类型：
```
event: commission
data: {"event_id":"...","kind":"direct","commission_amount":0.32,"invitee_uid":"...","ts":"2026-04-16T08:00:00Z"}

event: new_user
data: {"uid":"...","inviter_uid":"...","ts":"..."}

event: deposit
data: {"uid":"...","amount":1000,"ts":"..."}
```

前端用原生 `EventSource`，重连退避 1s → 30s。

---

## 7. 数据库变更

### 7.1 新增表

```sql
-- migration 040_user_dashboard_prefs.sql
CREATE TABLE user_dashboard_prefs (
    uid          TEXT PRIMARY KEY REFERENCES users(uid) ON DELETE CASCADE,
    prefs        JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- migration 041_agent_touch_history.sql
CREATE TABLE agent_touch_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_uid       TEXT NOT NULL REFERENCES users(uid),
    target_uid      TEXT NOT NULL REFERENCES users(uid),
    kind            TEXT NOT NULL CHECK (kind IN ('message','coupon','notify_sub')),
    template        TEXT,
    params          JSONB,
    delivered       BOOLEAN NOT NULL DEFAULT FALSE,
    error_reason    TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_touch_agent_target ON agent_touch_history(agent_uid, target_uid, created_at DESC);

-- migration 042_user_activity_aggregate.sql
-- 加速风险用户查询；每小时批跑一次
CREATE MATERIALIZED VIEW user_activity_agg AS
SELECT
    u.uid,
    u.inviter_uid,
    u.created_at AS registered_at,
    u.last_login_at,
    COALESCE(d.total, 0) AS deposit_total,
    COALESCE(w.total, 0) AS withdraw_total,
    COALESCE(t.vol_30d, 0) AS trade_volume_30d,
    COALESCE(t.vol_60d_prev_30d, 0) AS trade_volume_60d_prev_30d,
    COALESCE(b.balance, 0) AS current_assets_usd,
    COALESCE(t.last_trade_at, NULL) AS last_trade_at
FROM users u
LEFT JOIN (
    SELECT user_uid, SUM(amount_usd) AS total
    FROM wallet_transactions WHERE type = 'deposit' GROUP BY user_uid
) d ON d.user_uid = u.uid
LEFT JOIN (
    SELECT user_uid, SUM(amount_usd) AS total
    FROM wallet_transactions WHERE type = 'withdraw' GROUP BY user_uid
) w ON w.user_uid = u.uid
LEFT JOIN (
    SELECT
        user_uid,
        SUM(volume_usd) FILTER (WHERE created_at > NOW() - INTERVAL '30 day') AS vol_30d,
        SUM(volume_usd) FILTER (WHERE created_at BETWEEN NOW() - INTERVAL '60 day' AND NOW() - INTERVAL '30 day') AS vol_60d_prev_30d,
        MAX(created_at) AS last_trade_at
    FROM trades GROUP BY user_uid
) t ON t.user_uid = u.uid
LEFT JOIN (
    SELECT user_uid, SUM(balance_usd) AS balance FROM wallet_balances GROUP BY user_uid
) b ON b.user_uid = u.uid;

CREATE UNIQUE INDEX idx_uaa_uid ON user_activity_agg(uid);
CREATE INDEX idx_uaa_inviter ON user_activity_agg(inviter_uid);
```

### 7.2 修改现有表

```sql
-- migration 043_users_per_product_rate.sql
ALTER TABLE users
  ADD COLUMN rebate_rate_futures NUMERIC(4,4),
  ADD COLUMN rebate_rate_spot    NUMERIC(4,4);

-- 数据迁移：把 my_rebate_rate 复制到两个新字段
UPDATE users SET
  rebate_rate_futures = COALESCE(my_rebate_rate, 0),
  rebate_rate_spot    = COALESCE(my_rebate_rate, 0)
WHERE is_agent = TRUE;

-- 后续 commission_events 需要按 product_type 选用对应费率
-- （事务代码改动详见 §8）
```

### 7.3 调度器改动

- 新增 cron：每小时刷新 `user_activity_agg`（`REFRESH MATERIALIZED VIEW CONCURRENTLY`）
- 新增 cron：每小时计算 Today's Hit List 推荐（写入 Redis cache）

---

## 8. 前端组件分解

### 8.1 新增组件树

```
src/app/(agent)/dashboard/page.tsx                ★ 重写
  ├ components/dashboard/HitList.tsx              ★ M0
  ├ components/dashboard/InvitationCard.tsx       ★ M1
  ├ components/dashboard/AccountOverview.tsx      ★ M2
  ├ components/dashboard/KpiBar.tsx               ★ M3
  ├ components/dashboard/MetricChart.tsx          ★ M4 (核心)
  │   ├ ChipSelector.tsx
  │   ├ MultiSelectToggle.tsx
  │   ├ ChartTypeSwitch.tsx
  │   └ DateRangePicker.tsx (全局复用)
  ├ components/dashboard/TeamTreemap.tsx          ★ M5
  ├ components/dashboard/RiskRadarMini.tsx        ★ M6 (缩略版)
  ├ components/dashboard/InviteFunnel.tsx         ★ M7
  └ components/dashboard/RecentEvents.tsx          M8 (复用现有)

src/app/(agent)/data-center/
  ├ team/page.tsx
  ├ direct/page.tsx
  └ links/page.tsx

src/app/(agent)/team-overview/page.tsx            ★ 5.3
src/app/(agent)/risk-radar/page.tsx               ★ 5.4

src/components/charts/
  ├ NormalizedLineChart.tsx                       ★ 创新 1 多线归一化
  ├ DualAxisChart.tsx                             ★ 创新 1 双 Y 轴
  └ Treemap.tsx                                   ★ 创新 3

src/components/touch/
  ├ TouchActionBar.tsx                            ★ 创新 2 一键触达
  └ BatchTouchModal.tsx                           ★ 创新 2

src/components/realtime/
  └ SseProvider.tsx                               ★ 创新 4 SSE 全局 Provider

src/lib/
  ├ api.ts                       (扩展 +15 函数)
  ├ sse.ts                       ★ 创新 4
  └ touch-templates.ts           ★ 创新 2 文案模板
```

### 8.2 关键技术选型

| 需求 | 选型 | 理由 |
|---|---|---|
| 图表 | recharts ^2.x | React 19 兼容；SSR 友好；Treemap/ComposedChart 内置 |
| 日期选择 | react-day-picker | 与 base-ui 互不冲突；移动端 OK |
| SSE 客户端 | 原生 EventSource | 无依赖；React 19 自带 hydration 不冲突 |
| 状态管理 | React Server Components + URL state | 不引 zustand；URL = 单一可分享状态 |
| 复制到剪贴板 | Clipboard API | 浏览器原生 |
| 长图生成 | 后端 puppeteer-core + chromium | 一致性 > 体积 |

---

## 9. 设计规范

### 9.1 色板（基于现有 shadcn 主题扩展）

```
--success:    #22c55e   (收益、上涨)
--warning:    #f59e0b   (风险中、阈值临界)
--danger:     #ef4444   (流失、亏损)
--info:       #3b82f6   (中性、链接)
--accent:     #c8fa5f   (CTA、品牌色，致敬 Bitunix 但更克制)

--chart-1: #c8fa5f   (我的总收益)
--chart-2: #22c55e   (直系直客)
--chart-3: #f59e0b   (非直系直客)
--chart-4: #3b82f6   (对比指标 1)
--chart-5: #a855f7   (对比指标 2)
```

### 9.2 排版

- 数字字体：`SF Mono` / `JetBrains Mono` fallback
- 货币显示：4 位小数（USDT），千分位分隔
- 时间：UTC+0，格式 `YYYY-MM-DD HH:mm:ss`
- 移动端 < 768：所有字号 ×0.875

### 9.3 间距 / 容器

- Card padding: 24px desktop / 16px mobile
- Card 间距: 16px
- 内容最大宽度: 1440px
- 侧栏宽度: 240px desktop / drawer mobile

### 9.4 移动端断点策略

| 断点 | 行为 |
|---|---|
| ≥ 1280 | 完整 Dashboard 布局，2 列 |
| 768 - 1280 | 单列堆叠，但卡片全宽 |
| < 768 | 极简模式：仅 M0 + M3 + M4 + M6 + sticky CTA「立即邀请」 |

---

## 10. 非功能需求

### 10.1 性能

- 首屏 LCP < 2.5s（4G 模拟）
- API 响应：header < 200ms / kpi < 500ms / timeseries < 1s
- 图表渲染：60fps 切换 chip
- SSE 延迟：commission_event 写入到推送 < 3s

### 10.2 i18n

- P0：仅中文
- P1：英文
- P2：繁中、日、韩、越、印尼、阿拉伯（与 主 app 保持一致）
- 所有文案进 `src/i18n/{lang}.json`，禁止硬编码

### 10.3 可访问性

- 所有 chip 支持键盘导航（Tab / Enter / Space）
- 颜色对比 ≥ 4.5:1
- 屏幕阅读器：图表带 `aria-label` 数据摘要

### 10.4 安全

- 所有 endpoint 复用现有 `authMw.Authenticate` + 服务层 `is_agent` 校验
- 一键触达接口加速率限制：单代理每小时 200 次，单目标用户每天 1 次
- 周报长图生成：单代理每天 10 次

### 10.5 数据时效

- KPI / timeseries / treemap：实时查（不缓存）
- 风险用户：缓存 1 小时（依赖 materialized view 刷新）
- Today's Hit List：缓存 1 小时

---

## 11. 验收标准（GWT 用例）

### AC-1 G1 用户故事 1
**Given** 一个有 124 团队规模的代理登录后
**When** 打开 `/dashboard`
**Then** 30 秒内能看到「我下面这群人最近 7 天给我赚了多少」的具体数字（M3 我的佣金 + M4 默认 7 天图表）

### AC-2 G1 用户故事 2
**Given** 代理在 dashboard 页
**When** 看 M4 「我的佣金」chip
**Then** 图表必有 3 条线：总值（蓝实线）、直系直客（绿虚线）、非直系直客（橙虚线），每条线 hover 显示原值

### AC-3 G1 用户故事 3
**Given** 代理点 [数据中心 → 直客统计]
**When** 选「按交易量倒序」
**Then** 表格按交易量降序展示，TOP 10 一目了然

### AC-4 G1 用户故事 4
**Given** 代理在 M6 风险用户雷达
**When** 切到 [未登录] tab
**Then** 显示所有 30 天未登录的下级，每行右侧有 4 个操作按钮

### AC-5 G2 高频动作 1
**Given** 代理在 M1 邀请招商卡
**When** 单击 [📋] 复制邀请链接
**Then** 链接复制到剪贴板 + toast「已复制」 + 2s 后消失

### AC-6 G2 高频动作 2
**Given** 代理在 M6 选中 5 名未登录用户
**When** 点 [批量发激活消息]
**Then** 弹出预填模板的 modal，确认后调 `POST /api/agent/risk/touch`，返回结果中 success 用户的"上次触达时间"立即更新

### AC-7 创新 1
**Given** 代理在 M4
**When** toggle [+ 多选叠加 ON]，先点「我的佣金」再点「新增用户」
**Then** 同图叠加 2 条线，左 Y 轴 USDT，右 Y 轴 人数；hover 显示双值

### AC-8 创新 2
**Given** 代理已在过去 24 小时内对 user X 触达过一次
**When** 再次尝试触达 user X
**Then** 操作按钮置灰且 tooltip「24 小时内已触达过」，无法再次执行

### AC-9 创新 3
**Given** 风险阈值「智能模式」开启
**When** user X 30 天日均交易量 $100 / 当前 7 天日均 $35
**Then** user X 出现在「掉量」tab；徽章显示「-65% (智能阈值 60%)」

### AC-10 创新 4
**Given** 代理在 dashboard 浏览
**When** 后端写入一条新的 commission_event for 该代理
**Then** 顶部 toast「下级 7959** 刚交易了 +0.32 USDT」3 秒内出现，M3 的「我的佣金」数字滚动 +0.32

### AC-11 移动端
**Given** iPhone 12 (390×844) 打开 `/dashboard`
**When** 滚动浏览
**Then** 仅展示 M0 / M3 / M4 / M6 卡片，CTA「立即邀请」sticky 底部；所有内容无横向滚动条

### AC-12 个性化
**Given** 代理在 M4 齿轮里隐藏「出金人数」chip
**When** 刷新页面
**Then** chip 列表不再显示「出金人数」；后台 `dashboard_prefs` 持久化

### AC-13 安全
**Given** 一个普通用户（is_agent=false）持有合法 JWT
**When** 调 `GET /api/agent/overview/header`
**Then** 返回 403 + `{"error": "agent access required"}`

---

## 12. 排期与里程碑

### P0：4 周（基础体验追平 Bitunix 新系统）

| 周 | 后端 | 前端 | 验收 |
|---|---|---|---|
| W1 | overview/header + overview/kpi + treemap endpoints；user_activity_agg materialized view + 调度器 | Dashboard 框架；M1 + M2 + M3 卡片 | AC-1, AC-5 |
| W2 | overview/timeseries（含 split=referral_source）；data-center/team + direct + links | M4 单选 chip 切换 + recharts 集成；DateRangePicker | AC-2 |
| W3 | risk/users + materialized view 索引调优；team-overview/:uid | M5 Treemap；M6 RiskRadarMini；M7 InviteFunnel；M8 实时事件流 | AC-3, AC-4 |
| W4 | 测试 / 性能调优 / 文档 | 移动端响应式；i18n；空态 / 错误态 | AC-11, AC-13 |

### P1：4 周（5 大创新点上线）

| 周 | 内容 |
|---|---|
| W5 | 创新 2：risk/touch endpoint + agent_touch_history 表 + 触达 UI |
| W6 | 创新 1：M4 多选叠加 + 双 Y 轴归一化图表 |
| W7 | 创新 3：智能阈值算法 + 阈值配置 UI |
| W8 | 创新 4：SSE 通道 + 前端 SseProvider + 数字滚动动画 + toast |

### P2：弹性

- 创新 0：Today's Hit List（规则引擎）
- 创新 5：周报长图生成（puppeteer 服务）
- Per-product 费率审批工作流
- Treemap 变体：桑基图 / 网络图
- 多语言英文版

---

## 13. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| user_activity_agg materialized view 数据量大刷新慢 | 风险用户列表加载延迟 | CONCURRENTLY 刷新 + 分区表（按 inviter_uid hash） |
| SSE 连接数过多压垮服务 | 实时推送不稳定 | 单连接 idle 5 分钟自动断；前端只在 dashboard 页保持连接 |
| 一键触达被代理用作骚扰工具 | 用户投诉、合规风险 | 每用户 24h 限频 1 次；增加用户「免打扰」开关；触达内容预审模板池 |
| 智能阈值算法误判（小样本用户） | 漏报或误报 | 注册 < 14 天的用户回退固定阈值；展示「样本不足」标记 |
| recharts 包体积大（~150KB gzipped） | 首屏加载慢 | 动态 import；M4 之外的图表懒加载 |
| 周报长图生成耗 CPU | 后端瓶颈 | 限频每代理 10/天；用 worker pool；准生成（每周一凌晨预渲染） |
| 个性化 prefs 与多端不同步 | 体验割裂 | prefs 存后端不存 localStorage；变更立即推送 |

---

## 14. 不在本期范围

- ❌ 代理之间的协作 / 团队空间
- ❌ 跨代理的对比榜单
- ❌ 主动 push notification（短信 / 邮件 / Telegram bot）
- ❌ ML 推荐引擎（M0 仅规则引擎）
- ❌ 二次开发 SDK / 开放 API 给第三方
- ❌ 全链路反洗钱风控（依赖现有平台风控）

---

## 附录 A：术语表

| 术语 | 含义 |
|---|---|
| 直系直客 | inviter_uid = 我，且 is_agent = false（end user） |
| 直系合伙人 / sub-agent | inviter_uid = 我，且 is_agent = true |
| 非直系直客 | 我子树中，inviter_uid != 我 的 end user |
| Team Size | 我的整棵子树用户数（递归 CTE） |
| 自返 / self | kind='self'，代理本人交易也按比例返还 |
| Override / 级差 | 上级代理从下级代理产出的返佣中抽差额比例 |
| First Deposit User | 首次完成入金的用户（生命周期一次） |
| Touch（触达） | 代理对下级用户主动发起一次运营动作（消息/券/通知） |

---

## 附录 B：竞品功能对照表

| 功能 | Bitunix 老 | Bitunix 新 | 我们 P0 | 我们 P1 | 我们 P2 |
|---|---|---|---|---|---|
| 5-KPI 顶栏 | ❌ | ✅ | ✅ | | |
| 6 张时间序列图 | ✅ | ❌ | | | |
| 单图多 chip | ❌ | ✅ | ✅ | | |
| **多 chip 叠加对比** | ❌ | ❌ | | ✅ | |
| 自定义可见 chip | ❌ | ✅ | | ✅ | |
| 直系/非直系切片 | ✅ | ✅ | ✅ | | |
| 团队 treemap | ❌ | ❌ | | | ✅ |
| 团队列表 + 下钻 | ❌ | ✅ | ✅ | | |
| 用户排行（7 排序） | ❌ | ✅ | ✅ | | |
| **风险用户雷达** | ❌ | ✅ | ✅ | | |
| **一键触达（消息/券）** | ❌ | ❌ | | ✅ | |
| **智能阈值** | ❌ | ❌ | | ✅ | |
| 链接漏斗 | ❌ | ✅ | ✅ | | |
| 双费率（合约 / 现货） | ✅ | ✅ | ✅ | | |
| **实时 SSE 推送** | ❌ | ❌ | | ✅ | |
| **Today's Hit List** | ❌ | ❌ | | | ✅ |
| **周报长图分享** | ❌ | ❌ | | | ✅ |
| 实时事件流 | ❌ | ❌ | ✅ (已上线) | | |
| 自返佣 (self) | ❌ | ✅ | ✅ (已上线) | | |
| 暗黑模式 | ❌ | ✅ | | ✅ | |

---

## 文档变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-04-16 | 初稿 | Product (Arron) |
