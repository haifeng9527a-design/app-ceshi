# Step 0: 现状结构摘要 + 问题定位

## 一、App 入口与路由

| 文件 | 路径 | 作用 |
|------|------|------|
| main.dart | `lib/main.dart` | 入口，初始化 dotenv/Firebase/Supabase/LocaleProvider，runApp(TeacherHubApp) |
| app.dart | `lib/app.dart` | TeacherHubApp，MaterialApp 配置 theme/home/builder |

## 二、现有主题系统（三套并存）

| 主题类 | 路径 | 使用场景 | 问题 |
|--------|------|----------|------|
| **ThemeData** | `lib/app.dart` L66-79 | 全局 | 仅 colorScheme/appBarTheme，无 textTheme/inputTheme 等 |
| **TvTheme** | `lib/ui/tv_theme.dart` | 行情页、PC 端 | 独立颜色/间距/字体，与 app ThemeData 脱节 |
| **PcDashboardTheme** | `lib/core/pc_dashboard_theme.dart` | PC 壳、侧栏、顶栏 | 另一套 surface/border/accent |
| **ChartTheme** | `lib/features/market/chart/chart_theme.dart` | K 线/分时图 | 第四套颜色（background/cardBackground/up/down） |

## 三、UI 目录结构

```
lib/
├── app.dart                    # MaterialApp 入口
├── main.dart                   # 启动入口
├── core/
│   ├── finance_background.dart # 粒子背景（颜色硬编码）
│   ├── pc_dashboard_theme.dart # PC 主题
│   ├── pc_shell.dart           # PC 壳
│   ├── pc_sidebar.dart
│   ├── pc_topbar.dart
│   └── splash_screen.dart      # 旧版 Splash（冗余）
├── ui/
│   ├── tv_theme.dart           # 行情主题
│   ├── splash/
│   │   ├── tv_orbit_splash.dart
│   │   └── orbit_painter.dart
│   └── widgets/
│       ├── index_card.dart     # 指数卡片
│       ├── quote_table.dart    # 行情表
│       └── segmented_tabs.dart # 分段 Tab
└── features/
    ├── home/
    │   ├── home_page.dart      # 首页（含底部导航）
    │   └── featured_teacher_page.dart  # 约 2754 行
    ├── market/
    │   ├── market_page.dart   # 约 4888 行
    │   ├── market_colors.dart # 涨跌色
    │   ├── gainers_losers_page.dart
    │   ├── watchlist_page.dart
    │   └── chart/
    │       └── chart_theme.dart
    ├── messages/
    │   └── chat_detail_page.dart  # 约 4488 行
    ├── auth/
    │   └── login_page.dart
    └── profile/
        └── profile_page.dart
```

## 四、问题定位到文件路径

| 问题 | 涉及文件 |
|------|----------|
| 主题割裂 | app.dart, tv_theme.dart, pc_dashboard_theme.dart, chart_theme.dart |
| 颜色硬编码 | market_page.dart, login_page.dart, profile_page.dart, finance_background.dart, 等 40+ 文件 |
| 间距魔法数字 | market_page.dart (EdgeInsets 4/6/8/12/14/16/20/24/28/40/52), login_page.dart, chat_detail_page.dart |
| 无 textTheme | app.dart ThemeData |
| 巨型页面 | market_page.dart (4888 行), featured_teacher_page.dart (2754 行), chat_detail_page.dart (4488 行) |
| 通用组件少 | lib/ui/widgets/ 仅 3 个，大量 _xxx 私有组件在页面内 |

## 五、下一步执行计划

1. **Step 1**：在 `lib/core/design/` 下建立 design_tokens（colors/spacing/radius/typography/shadow）
2. **Step 2**：在 `lib/core/theme/app_theme.dart` 建立统一 AppTheme，替换 app.dart 的 theme
3. **Step 3**：在 `lib/ui/components/` 下建立 AppCard/AppButton/AppInput/AppChip
4. **Step 4**：示范改造 market_page 的 header + Tab 区域（替换硬编码 + 使用新组件）
5. **Step 5**：输出 UI 改造落地报告
