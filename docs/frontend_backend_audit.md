
# 前端数据操作审计报告

> 检查目标：确认前端是否全部通过后端接口操作数据库，安装后无问题
> 
> **更新**：已实现后端 API 与前端调用，配置 TONGXIN_API_URL 后主要功能走后端。

## 一、当前配置状态

### 前端 `.env`
- `SUPABASE_URL`、`SUPABASE_ANON_KEY`：**已注释** → `SupabaseBootstrap.clientOrNull` 恒为 `null`
- `TONGXIN_API_URL`：已配置 `http://192.168.1.105:3000`

### 后端 `.env`
- `SUPABASE_URL`、`SUPABASE_ANON_KEY`：已配置（后端直连 Supabase）
- `PORT`、`POLYGON_API_KEY` 等：已配置

---

## 二、后端已实现的 API（前端可调用）

### 用户/Profile
| 接口 | 用途 | 前端调用方 |
|------|------|------------|
| `POST /api/auth/profile/sync` | 同步用户资料 | SupabaseUserSync |
| `POST /api/auth/profile/short-id` | 生成 short_id | SupabaseUserSync |
| `GET /api/users/me` | 当前用户 profile | - |
| `PATCH /api/users/me` | 更新当前用户 | - |
| `GET /api/users/:userId/profile` | 指定用户 profile | FriendsRepository, add_friend_page |
| `GET /api/users/me/restrictions` | 用户限制状态 | UserRestrictions |
| `PATCH /api/users/me/last-online` | 最后上线时间 | LastOnlineService |
| `POST /api/device-tokens` | 推送 token | NotificationService |
| `GET /api/user-profiles/batch` | 批量用户展示名/头像 | CustomerServiceWorkbenchPage |
| `GET /api/user-profiles/:userId/display-name` | 用户展示名 | FeaturedTeacherPage |

### 好友
| 接口 | 用途 | 前端调用方 |
|------|------|------------|
| `GET /api/friends` | 好友列表 | FriendsRepository |
| `GET /api/friends/remarks` | 好友备注 | FriendsRepository |
| `PUT /api/friends/remarks` | 保存备注 | FriendsRepository |
| `GET /api/friends/requests/incoming` | 收到的好友申请 | FriendsRepository |
| `POST /api/friends/requests` | 发送好友申请 | FriendsRepository |
| `POST /api/friends/requests/:id/accept` | 接受申请 | FriendsRepository |
| `POST /api/friends/requests/:id/reject` | 拒绝申请 | FriendsRepository |
| `DELETE /api/friends/:friendId` | 删除好友 | FriendsRepository |
| `GET /api/friends/search` | 按 email/short_id 查找 | FriendsRepository |
| `GET /api/friends/check/:friendId` | 是否已是好友 | FriendsRepository |
| `POST /api/friends/ensure-customer-service` | 确保已添加客服 | FriendsRepository |

### 消息/会话
| 接口 | 用途 | 前端调用方 |
|------|------|------------|
| `GET /api/conversations` | 会话列表 | MessagesApi |
| `GET /api/conversations/:id` | 单个会话 | MessagesApi |
| `GET /api/conversations/:id/messages` | 消息列表 | MessagesApi |
| `POST /api/messages` | 发送消息 | MessagesApi |
| `PATCH /api/conversations/:id/read` | 标记已读 | MessagesApi |
| `GET /api/chat-members/:conversationId` | 获取 peer_id | ChatDetailPage |

### 交易员
| 接口 | 用途 | 前端调用方 |
|------|------|------------|
| `GET /api/teachers` | 交易员列表 | - |
| `GET /api/teachers/rankings` | 排行榜 | - |
| `GET /api/teachers/:userId` | 单个交易员 | - |
| `GET /api/teachers/:userId/strategies` | 策略列表 | - |
| `GET /api/teachers/:userId/comments` | 评论列表 | - |
| `POST /api/teachers/:userId/comments` | 发表评论 | - |
| `GET /api/teachers/:userId/follow-status` | 是否已关注 | - |
| `POST /api/teachers/:userId/follow` | 关注 | - |
| `DELETE /api/teachers/:userId/follow` | 取消关注 | - |

### 行情
| 接口 | 用途 | 前端调用方 |
|------|------|------------|
| `GET /api/quotes` | 股票报价 | MarketRepository |
| `GET /api/tickers-from-cache` | 股票列表缓存 | StockQuoteCacheRepository |
| `GET/PUT /api/market/snapshots` | 行情快照 | MarketSnapshotRepository |
| `GET /api/candles` | K 线数据 | BackendMarketClient |

---

## 三、仍直接使用 Supabase 的模块（未走后端）

当 `clientOrNull == null` 时，这些模块会**安全降级**（返回空数据、不崩溃），但**没有后端 API 可替代**。

### 3.1 好友与消息（P0）

| 模块 | 表/能力 | 当前行为 |
|------|---------|----------|
| **FriendsRepository** | friends, friend_requests, friend_remarks, user_profiles, teacher_profiles | `!_hasClient` 时返回 `[]` / `null` |
| **MessagesRepository** | chat_members, chat_conversations, chat_messages, storage | `!_hasClient` 时返回空流/空列表 |
| **chat_detail_page** | chat_members（解析 peer_id） | `client == null` 时跳过 |
| **add_friend_page** | user_profiles（short_id） | `client == null` 时返回 null |

### 3.2 用户与个人页（P0）

| 模块 | 表/能力 | 当前行为 |
|------|---------|----------|
| **profile_page** | user_profiles, teacher_profiles, avatars storage | `client == null` 时用缓存或默认值 |
| **user_restrictions** | user_profiles（限制状态） | `client == null` 时返回 null |
| **last_online_service** | user_profiles（last_online_at） | `client == null` 时跳过 |
| **notification_service** | device_tokens | `client == null` 时跳过保存 |
| **supabase_user_sync** | user_profiles | 优先走后端；后端不可用时回退 Supabase（此时 client 为 null 则跳过） |

### 3.3 交易员与排行榜（P1）

| 模块 | 表/能力 | 当前行为 |
|------|---------|----------|
| **TeacherRepository** | teacher_profiles, user_profiles, trade_strategies, teacher_comments, teacher_strategy_likes, teacher_follows, teacher_positions, trade_records, storage | `!_hasClient` 时返回空 |
| **rankings_page** | teacher_profiles | `client == null` 时返回空流 |
| **featured_teacher_page** | user_profiles（display_name） | `client == null` 时用默认名 |
| **customer_service_workbench_page** | user_profiles（客服列表展示名） | `client == null` 时跳过加载 |

### 3.4 客服、通话、举报（P1/P2）

| 模块 | 表/能力 | 当前行为 |
|------|---------|----------|
| **CustomerServiceRepository** | app_config, user_profiles, customer_service_assignments, chat_members, chat_conversations, chat_messages, rpc | `!_hasClient` 时返回 null/[] |
| **CallInvitationRepository** | call_invitations, Edge Functions | `!_hasClient` 时抛错或返回空 |
| **ReportRepository** | user_reports, avatars storage | `!_hasClient` 时返回 []/跳过 |

---

## 四、安装后实际表现

### 4.1 当前配置（前端无 Supabase KEY）

| 功能 | 表现 |
|------|------|
| 行情（报价、K 线、涨跌榜） | ✅ 正常，走后端 |
| 用户登录、Firebase 同步 | ✅ 正常，走后端 sync/short-id |
| 好友列表、消息、会话 | ❌ 空（无后端 API） |
| 个人页头像、签名、short_id | ⚠️ 仅本地缓存或默认值，无法从服务端拉取 |
| 交易员中心、排行榜、关注 | ❌ 空（无后端 API） |
| 客服工作台、通话、举报 | ❌ 不可用（无后端 API） |
| 推送 token 保存 | ❌ 不保存（无后端 API） |
| 用户限制校验 | ⚠️ 返回 null，视为无限制 |

### 4.2 若恢复前端 Supabase KEY

上述模块会**重新直连 Supabase**，不再走后端，与「全部通过后端操作数据库」的目标不符。

---

## 五、结论与建议

### 5.1 结论

**前端并未全部通过后端接口操作数据库。**

- ✅ 已走后端：行情、用户 profile 同步、short_id
- ❌ 仍依赖 Supabase 直连（或空数据）：好友、消息、交易员、客服、通话、举报、推送、用户限制等

### 5.2 建议

1. **短期**：保持前端 Supabase KEY 注释，确保不直连；但好友、消息、交易员等会显示为空。
2. **中期**：按 `docs/supabase_to_backend_migration.md` 的 P0→P1→P2 顺序，在后端实现：
   - `/api/friends/*`、`/api/friend-requests/*`
   - `/api/conversations/*`、`/api/messages/*`、`/api/upload/*`（媒体）
   - `/api/teachers/*`、`/api/rankings/*`
   - `/api/customer-service/*`、`/api/call-invitations/*`、`/api/reports/*`
   - `/api/device-tokens`、`/api/users/me/restrictions`
3. **前端改造**：每个 Repository 在「后端 API 可用时」优先调用 ApiClient，仅在不可用时才考虑 Supabase 降级（或直接要求必须配置后端）。

---

## 六、文件级检查清单

| 文件 | 是否走后端 | 说明 |
|------|------------|------|
| `stock_quote_cache_repository.dart` | ✅ | 调用 `/api/tickers-from-cache`、`/api/quotes` |
| `market_snapshot_repository.dart` | ✅ | 调用 `/api/market/snapshots` |
| `market_repository.dart` | ✅ | 使用 backend quotes |
| `supabase_user_sync.dart` | ✅ 优先 | ApiClient 可用时走后端，否则回退 Supabase |
| `auth_api.dart` | ✅ | 仅封装后端调用 |
| `friends_repository.dart` | ❌ | 直连 Supabase |
| `messages_repository.dart` | ❌ | 直连 Supabase |
| `teacher_repository.dart` | ❌ | 直连 Supabase |
| `customer_service_repository.dart` | ❌ | 直连 Supabase |
| `call_invitation_repository.dart` | ❌ | 直连 Supabase |
| `report_repository.dart` | ❌ | 直连 Supabase |
| `profile_page.dart` | ❌ | 直连 Supabase |
| `user_restrictions.dart` | ❌ | 直连 Supabase |
| `last_online_service.dart` | ❌ | 直连 Supabase |
| `notification_service.dart` | ❌ | 直连 Supabase |
| `rankings_page.dart` | ❌ | 直连 Supabase |
| `chat_detail_page.dart` | ❌ | 直连 Supabase |
| `add_friend_page.dart` | ❌ | 直连 Supabase |
| `featured_teacher_page.dart` | ❌ | 直连 Supabase |
| `customer_service_workbench_page.dart` | ❌ | 直连 Supabase |
