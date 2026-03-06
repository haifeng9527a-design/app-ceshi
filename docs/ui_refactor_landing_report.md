# UI 改造落地报告

## 已完成目标

1. 建立统一 Design Token 体系（颜色/间距/圆角/字体/阴影）
2. 建立统一 AppTheme（ThemeData + textTheme + component themes）
3. 建立基础组件库（AppCard/AppButton/AppInput/AppChip）
4. 选取 `market_page` 做示范改造（tokens + components + 子组件拆分）
5. 输出落地报告（本文件）

## 本次改动文件

### 新增

- `tongxin-frontend/lib/core/design/app_colors.dart`
- `tongxin-frontend/lib/core/design/app_spacing.dart`
- `tongxin-frontend/lib/core/design/app_radius.dart`
- `tongxin-frontend/lib/core/design/app_typography.dart`
- `tongxin-frontend/lib/core/design/app_shadow.dart`
- `tongxin-frontend/lib/core/design/design_tokens.dart`
- `tongxin-frontend/lib/core/theme/app_theme.dart`
- `tongxin-frontend/lib/ui/components/app_card.dart`
- `tongxin-frontend/lib/ui/components/app_button.dart`
- `tongxin-frontend/lib/ui/components/app_input.dart`
- `tongxin-frontend/lib/ui/components/app_chip.dart`
- `tongxin-frontend/lib/ui/components/components.dart`
- `tongxin-frontend/lib/features/market/widgets/market_header.dart`
- `tongxin-frontend/lib/features/market/widgets/market_section_label.dart`
- `tongxin-frontend/lib/features/market/widgets/market_search_bar.dart`
- `docs/ui_refactor_step0_report.md`

### 修改

- `tongxin-frontend/lib/app.dart`
- `tongxin-frontend/lib/ui/tv_theme.dart`（deprecated 标记）
- `tongxin-frontend/lib/core/pc_dashboard_theme.dart`（deprecated 标记）
- `tongxin-frontend/lib/features/market/market_page.dart`

## 关键落地点

### 1) 全局主题统一

- `MaterialApp.theme` 从内联 `ThemeData` 改为 `AppTheme.dark()`
- `AppTheme` 补全：
  - `textTheme`
  - `iconTheme`
  - `inputDecorationTheme`
  - `elevatedButtonTheme`
  - `snackBarTheme`
  - `dialogTheme`
  - `tabBarTheme`

### 2) Design Tokens 生效

- 颜色语义：`AppColors.primary/surface/textPrimary/positive/negative...`
- 间距语义：`AppSpacing.sm/md/lg/xl/...`（8px 系统）
- 圆角语义：`AppRadius.sm/md/lg`
- 字体语义：`AppTypography.title/subtitle/body/caption/data`

### 3) 组件库生效

- `AppCard`：统一卡片容器样式（背景/边框/阴影/圆角）
- `AppButton`：primary / secondary / text 三态
- `AppInput`：统一输入样式，支持只读点击（用于搜索入口）
- `AppChip`：统一选中/未选中态

### 4) 示范页改造（Market）

- `market_page` 顶部改造：
  - 移动端 header 抽到 `MarketHeader`
  - 区块标题抽到 `MarketSectionLabel`
  - 搜索栏抽到 `MarketSearchBar`
- 将搜索入口从手写 `Material+InkWell+Container` 改为 `MarketSearchBar`（内部使用 `AppInput`）
- 将涨跌榜按钮改为 `AppChip`
- 将 `See all` 改为 `AppButton(variant: text)`
- 将空自选态改为 `AppCard`

### 5) 第二样板页改造（Login）

- `features/auth/login_page.dart` 完成从硬编码到 tokens 的迁移：
  - 移除页面内 `_accent/_bg/_text/_textMuted` 颜色常量
  - 颜色改为 `AppColors.*`
  - 间距改为 `AppSpacing.*`
- 替换页面私有组件为统一组件：
  - `_TabChip` -> `AppChip`
  - `_Input` -> `AppInput`
  - 主操作按钮 -> `AppButton(primary)`
  - 第三方登录按钮 -> `AppButton(secondary)`
  - 空提示卡片 -> `AppCard`
- `_showMessage` 改为走全局 `SnackBarTheme`（移除局部 hardcode）

### 6) 第三样板页改造（Profile，已完成）

- `features/profile/profile_page.dart` 本轮已完成首批迁移：
  - 引入 `design_tokens.dart` 与 `components.dart`
  - 页面 `ListView` 外层间距改为 `AppSpacing.allMd`
  - Firebase 未配置提示块从手写 `Container` 改为 `AppCard`
  - 用户等级标签 `_buildLevelTag` 改为 token（颜色/圆角/字体）
- 新增页面复用方法 `_buildMenuItemCard(...)`，统一“我的”页菜单卡片：
  - 交易员朋友圈 / 帮助 / 隐私政策 / 举报 / 退出登录 / 账号注销 / 语言设置
  - 底部菜单从 `Card + ListTile` 批量迁移为 `AppCard + ListTile`
- 退出登录与语言设置的 BottomSheet：
  - 背景色与圆角改为 token（`AppColors.surface` + `AppRadius.lg`）
  - 按钮改为 `AppButton`（secondary / primary）
- 本轮补充完成：
  - 顶部“账号状态提示条/通知权限提示条”迁移为 `AppCard + AppTypography + AppColors`
  - 顶部用户信息卡从 `Card` 迁移为 `AppCard`
  - 头像区域与签名区硬编码颜色迁移到 tokens（`AppColors.surface/primary/textTertiary`）
  - 教师中心与客服工作台入口卡片迁移为 `AppCard`
  - `_editSignature` / `_showPrivacyPolicy` / `_showAccountDeletion` 的 `AlertDialog` 操作按钮迁移为 `AppButton`
  - 隐私政策正文文本样式迁移到 `AppTypography`
  - 帮助弹层中的通知权限二级 `AlertDialog` 按钮迁移为 `AppButton`
  - 通知权限二级弹窗说明文本样式迁移到 `AppTypography`
  - 通知权限提示条右侧“去开启”按钮迁移为 `AppButton(variant: text)`
  - 签名编辑输入框从 `TextField` 迁移到 `AppInput`
  - 语言选择弹层的选项项统一为 `AppCard + ListTile + token` 图标/箭头色
  - 帮助弹层主要入口项统一为 `AppCard + ListTile`，提升与全页卡片风格一致性

### 7) 第四样板页改造（FeaturedTeacher，已完成）

- `features/home/featured_teacher_page.dart` 已完成核心区统一迁移：
  - 引入 `design_tokens.dart` 与 `components.dart`
  - 加载态/异常态接入 `AppColors/AppTypography/AppButton/AppSpacing`
  - 主页面区块间距统一到 `AppSpacing`（Sliver padding/段落间距/轮播间距）
  - “查看全部策略”按钮从默认 `TextButton` 迁移到 `AppButton(variant: text)`
- 顶部头图与策略主卡完成第一批 token 化：
  - 主色/边框/阴影/渐变主色统一为 `AppColors.primary/surface*`
  - `withOpacity` 替换为 `withValues(alpha: ...)`
  - 评论区/转发弹层/评论输入区接入 `AppCard` 与 tokens
- 本轮自检结果：
  - `flutter analyze lib/features/home/featured_teacher_page.dart`
  - No issues found
- 本轮补充细化：
  - 持仓卡区域（`_PositionCardStyle`）语义色统一到 `AppColors.positive/negative/text*`
  - 月度盈亏卡与空态提示卡的背景/边框统一到 token（`AppColors.surface/primary`）
  - 持仓明细文案主次色统一到 `AppColors.textPrimary/textTertiary`

### 8) 第五样板页改造（TeacherList，已完成）

- `features/teachers/teacher_list_page.dart` 已完成 token + 组件接入：
  - 引入 `design_tokens.dart` 与 `components.dart`
  - 顶部操作按钮从 `TextButton` 迁移为 `AppButton(variant: text)`
  - 列表卡片从 `Card` 迁移为 `AppCard`
  - 标签从 `Chip` 迁移为 `AppChip`
  - 列表间距、头像配色、空态文本样式迁移为 tokens
- 自检结果：
  - `flutter analyze lib/features/teachers/teacher_list_page.dart`
  - No issues found

### 9) 第六样板页改造（ChatDetail，已完成）

- `features/messages/chat_detail_page.dart` 已完成首批高影响迁移：
  - 引入 `design_tokens.dart` 与 `components.dart`
  - 输入区（语音按钮/文本输入/发送按钮）主样式迁移到 tokens
  - 回复预览条、群公告条改为 token 风格（颜色/圆角/间距/字体）
  - 空态与加载态主色统一为 `AppColors.primary`，文本统一到 `AppTypography`
  - 相册/拍摄/通话类型弹层背景与圆角统一到 tokens
  - 头像预览弹层与导航栏头像主色统一为 tokens
  - 多处 `withOpacity` 替换为 `withValues(alpha: ...)`
  - @提及浮层样式统一到 `AppColors.surfaceElevated/border/text*`
  - 消息气泡与引用块高频硬编码色值迁移到 `AppColors.primary/surface/text*`
  - 通话记录卡与更多动作面板颜色统一到 token（含图标、边框、文案）
  - 分享名片、视频卡片、链接文本与语音播放条进一步替换为 token 语义色
- 质量收敛：
  - `flutter analyze lib/features/messages/chat_detail_page.dart`
  - No issues found
- 本轮细化（边角一致性收敛）：
  - 头部身份分隔符、等级徽标、最后在线文案等零散硬编码颜色统一到 `AppColors.textTertiary/primarySubtle/primary`
  - 消息气泡内“我的消息”正文与引用底色改为 token 语义色（去除 `Colors.black` 直接硬编码）
  - 视频占位、图片加载失败、文件消息图标/文案等媒体区域颜色统一到 `AppColors.textSecondary/textPrimary`
  - 二次自检：`flutter analyze lib/features/messages/chat_detail_page.dart`、`flutter analyze lib/features/profile/profile_page.dart`
  - 结果：No issues found

### 10) 第七样板页改造（TeacherPublic，已完成）

- `features/teachers/teacher_public_page.dart` 已完成 token + 组件接入与收敛：
  - 引入 `design_tokens.dart` 与 `components.dart`
  - 页面主背景、信息卡片、边框透明度统一到 `AppColors` + `withValues(alpha: ...)`
  - 底部操作区从默认 `FilledButton` 迁移为 `AppButton`
  - 清理未使用私有逻辑与无用 import，去掉历史死代码
- 自检结果：
  - `flutter analyze lib/features/teachers/teacher_public_page.dart`
  - No issues found
- 本轮细化（视觉一致性收敛）：
  - 策略卡片与交易记录卡片统一迁移到 `AppCard`
  - 子模块颜色常量统一到 `AppColors`（去除页面内硬编码色值）
  - 列表与段落间距统一到 `AppSpacing` 语义间距

### 11) 第八样板页改造（MessagesPage，已完成）

- `features/messages/messages_page.dart` 已完成一轮结构收口与组件迁移：
  - 引入 `design_tokens.dart` 与 `components.dart`
  - 底部弹层、确认弹窗的操作按钮统一为 `AppButton`
  - 页面背景与部分容器色值迁移到 `AppColors` 语义色
  - 清理未使用旧代码（旧搜索块、未使用鉴权函数、未使用旧卡片/分段组件）
  - 修复 `use_build_context_synchronously` 与 `prefer_is_empty` 等质量项
  - 搜索输入框从手写 `TextField` 迁移到 `AppInput`
  - 配置提示卡与好友请求卡迁移到 `AppCard`
  - 好友请求操作按钮迁移到 `AppButton`（primary/secondary）
  - 好友卡/会话卡高频色值统一迁移到 `AppColors`（昵称、状态点、群标记、未读徽标、时间文案）
  - 草稿/状态文案语义色统一（`warning`/`success`/`textTertiary`）
- 自检结果：
  - `flutter analyze lib/features/messages/messages_page.dart`
  - No issues found

### 12) 第九样板页改造（TeacherDetail，已完成）

- `features/teachers/teacher_detail_page.dart` 已完成基础 token + 组件接入：
  - 引入 `design_tokens.dart` 与 `components.dart`
  - 间距改为 `AppSpacing` 语义常量
  - 主操作按钮从 `FilledButton` 迁移到 `AppButton`
  - 标签从 `Chip` 迁移到 `AppChip`
  - 统计卡片容器从手写 `Container` 迁移到 `AppCard`
- 自检结果：
  - `flutter analyze lib/features/teachers/teacher_detail_page.dart`
  - No issues found

### 13) 第十样板页改造（SystemNotifications，已完成）

- `features/messages/system_notifications_page.dart` 已完成从旧主题到 tokens 的迁移：
  - 移除对 `PcDashboardTheme` 的依赖，改用 `design_tokens.dart`
  - 页面与卡片风格统一为 `AppColors` + `AppTypography` + `AppSpacing`
  - 列表项容器从手写装饰迁移到 `AppCard`
  - 操作按钮从 `TextButton/FilledButton` 迁移到 `AppButton`
- 自检结果：
  - `flutter analyze lib/features/messages/system_notifications_page.dart`
  - No issues found

### 14) 第十一样板页改造（TeacherCenter，已完成）

- `features/teachers/teacher_center_page.dart` 已完成质量收敛与兼容更新：
  - 修复 `DialogTheme` 旧字段用法，迁移为 `DialogThemeData.backgroundColor`
  - 清理 `withOpacity` 旧写法，统一改为 `withValues(alpha: ...)`
  - 修复 `DropdownButtonFormField.value` 废弃用法，改为 `initialValue`
  - 清理未使用旧函数（记录页旧入口）以降低维护成本
  - 本轮继续将页面卡片/按钮统一接入 `AppCard` 与 `AppButton`
  - 状态条与空态文案颜色统一到 `AppColors` 语义色
- 自检结果：
  - `flutter analyze lib/features/teachers/teacher_center_page.dart`
  - No issues found

## 为什么这样改

- 先建立 token/theme/component 三层，才能避免继续引入硬编码并形成可复用体系。
- 先做单页示范改造，验证迁移方式和组件抽象是否可行，再推广到全项目。
- 对旧主题先做 deprecated 而非直接删除，降低一次性改动风险。

## 下一步推进建议

1. 按模块迁移（推荐顺序）：
   - `features/home/home_page.dart`（已完成细化）
   - `features/teachers/teacher_public_page.dart`
   - `features/profile/profile_page.dart`（继续细节 token 化）
2. 每个模块按同一策略推进：
   - 替换硬编码色值/间距为 tokens
   - 替换默认组件为 AppCard/AppButton/AppInput/AppChip
   - 抽离页面私有组件到 `lib/ui/components` 或 `features/**/widgets`
3. 最后删除旧主题直接依赖（TvTheme/PcDashboardTheme），只保留桥接常量或完全下线。

## 风险与解决方案

- 风险：旧代码大量依赖 `TvTheme/PcDashboardTheme`，一次性替换风险高  
  方案：分阶段迁移，先 deprecated + bridge，按页面逐步替换

- 风险：视觉回归（颜色/间距变化）  
  方案：每次迁移后做截图比对，关键页建立 golden test

- 风险：大文件迁移冲突频繁（如 market/chat_detail）  
  方案：先拆分子组件文件，再迁移样式 token，减少冲突面

