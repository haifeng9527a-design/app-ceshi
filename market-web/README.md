# 行情首页 (Market Web)

React + TypeScript + TailwindCSS 实现的 PC 端行情首页，深色交易终端风格。

## 技术栈

- React 18 + TypeScript
- Vite
- TailwindCSS
- lucide-react 图标
- 纯 SVG Sparkline（无 echarts）

## 运行

```bash
cd market-web
npm install
npm run dev
```

浏览器打开 `http://localhost:5173`。

## 项目结构

```
market-web/
├── index.html
├── package.json
├── tailwind.config.js
├── postcss.config.js
├── tsconfig.json
├── vite.config.ts
└── src/
    ├── main.tsx
    ├── App.tsx
    ├── index.css
    ├── pages/
    │   └── MarketHome.tsx    # 行情首页入口
    ├── components/
    │   ├── NavBar.tsx        # 顶栏
    │   ├── IndexCard.tsx     # 指数卡片
    │   ├── Sparkline.tsx     # SVG 迷你图
    │   ├── Tabs.tsx          # 分段 Tabs
    │   ├── Panel.tsx         # 卡片面板
    │   ├── DataTable.tsx     # 自选/涨跌榜/市场热度表格
    │   └── Heatmap.tsx       # 热力图网格
    ├── constants/
    │   └── mock.ts           # Mock 数据（便于后续接 API）
    └── utils/
        ├── format.ts         # 价格/涨跌幅格式化
        └── colors.ts         # 涨跌色
```

## 自适应

- `>= 1280px`：主内容上区三列，下区两列
- `< 1280px`：上区两列，下区一列
- `< 900px`：单列

## 接入真实 API

将 `src/constants/mock.ts` 中的数据结构保持不变，在页面或自定义 hook 中请求 API 后映射为同类型（如 `IndexQuote`、`WatchlistRow`、`MoverRow`、`HeatmapItem`、`TrendingRow`），再传入现有组件即可。
