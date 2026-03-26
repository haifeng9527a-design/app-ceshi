# 前端数据操作迁移：Supabase → tongxin-backend

## 目标

tongxin-frontend 中所有数据操作不再直接连接 Supabase，统一通过 tongxin-backend 接口代理，避免数据库暴露。

## 已完成迁移

### 1. 行情相关（Phase 1）

| 模块 | 原方式 | 现方式 |
|------|--------|--------|
| **stock_quote_cache** | 前端直连 Supabase | 后端 `/api/tickers-from-cache`、`/api/quotes` |
| **market_snapshots** | 前端直连 Supabase | 后端 `/api/market/snapshots` GET/PUT |
| **MarketRepository.getQuotes** | 部分走 Supabase 缓存 | 统一走后端 `/api/quotes` |
| **MarketRepository.getTickersFromStockQuoteCache** | Supabase | 后端 `getTickersFromCache()` |
| **MarketSnapshotRepository** | Supabase | 后端 `ApiClient` |

### 2. 新增组件

- **`lib/core/api_client.dart`**：统一 HTTP 客户端，自动附加 Firebase Token，供后续所有 API 调用使用
- **`lib/supabaseClient.js`**：后端通用 Supabase 客户端（Service Role）
- **`/api/market/snapshots`**：行情快照读写接口

### 3. 用户同步（Phase 2）

| 模块 | 原方式 | 现方式 |
|------|--------|--------|
| **supabase_user_sync** | 前端直连 Supabase | 后端 `/api/auth/profile/sync`、`/api/auth/profile/short-id` |
| **AuthApi** | - | `lib/api/auth_api.dart` 封装用户同步接口 |

后端需配置 `GOOGLE_APPLICATION_CREDENTIALS`（Firebase 服务账号 JSON 路径）以启用鉴权。

## 待迁移模块（按优先级）

| 优先级 | 模块 | 表/能力 | 说明 |
|--------|------|---------|------|
| P0 | profile_page | user_profiles, avatars | 头像、签名、short_id |
| P0 | profile_page | user_profiles, avatars | 头像、签名、short_id |
| P0 | user_restrictions | user_profiles | 限制状态 |
| P0 | notification_service | device_tokens | 推送 token |
| P0 | friends_repository | friends, friend_requests 等 | 好友、申请、备注 |
| P0 | messages_repository | chat_* | 会话、消息、媒体 |
| P1 | teacher_repository | teacher_*, trade_* | 交易员、策略、评论、持仓 |
| P1 | customer_service_* | 客服相关 | 客服配置、分配、群发 |
| P1 | call_invitation_repository | call_invitations | 通话邀请 |
| P2 | report_repository | user_reports | 举报 |
| P2 | rankings_page | teacher_profiles | 排行榜 |

## 配置要求

### 前端 `.env`

```env
# 必须配置：后端地址，否则行情快照、股票缓存等无法使用
TONGXIN_API_URL=http://localhost:3000
# 真机测试用本机 IP：http://192.168.1.x:3000
```

### 后端 `.env`

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

## 后续迁移步骤

1. 后端添加 Firebase Admin SDK 鉴权中间件
2. 按 P0 → P1 → P2 顺序实现 `/api/users/*`、`/api/friends/*`、`/api/conversations/*` 等
3. 前端各 Repository 改为调用 `ApiClient` 对应接口
4. Storage 上传改为 `/api/upload/*`，由后端用 Service Role 写 Supabase Storage
5. Realtime 订阅：可保留 Supabase Realtime（需评估安全），或由后端提供 WebSocket
