# tongxin-admin

通心企业管理后台（独立项目）。原管理后台已从 tongxin-frontend 迁移至此。

## 功能

- 总览：交易员状态统计
- 用户管理：限制登录/发消息/加好友/加群/建群，封禁、冻结
- 交易员审核：审核、冻结、封禁、编辑资料、策略/持仓/评论等
- 举报管理：审核用户举报
- 设置：客服配置、群发消息、客服人员管理

## 环境配置

复制 `.env.example` 为 `.env`，配置：

```env
TONGXIN_API_URL=https://your-backend.example.com
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
# 仅首次初始化管理员时需要，用于调用 /api/admin/auth/bootstrap
ADMIN_API_KEY=your-bootstrap-key
```

与 tongxin-frontend 共用同一 Supabase 项目。

管理员日常登录改为账号密码换取会话令牌，不再依赖前端对所有请求统一附带 `x-admin-key`。

## 运行

```bash
# Web
flutter run -d edge
# 或
flutter run -d chrome

# Windows 桌面
flutter run -d windows
```

## 部署

```bash
flutter build web
# 输出在 build/web/
```
