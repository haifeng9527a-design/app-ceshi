# 接口模式检查报告

> 检查所有页面是否使用接口模式（走后端 API），包括登录流程。目标：不直连数据库，全部走后端 API。

## 一、登录流程

| 模块 | 当前状态 | 说明 |
|------|----------|------|
| **LoginPage** | ✅ 接口模式 | 使用 Firebase Auth 登录，登录后通过 `UserRestrictions.getMyRestrictionRow()` 校验限制 |
| **AuthService** | ✅ 接口模式 | 登录后调用 `SupabaseUserSync().upsertFromFirebase()`，内部走 `AuthApi.syncProfile` |
| **SupabaseUserSync** | ✅ 接口模式 | 仅使用 `AuthApi`，无 Supabase 直连 |
| **UserRestrictions** | ⚠️ 有 Supabase 回退 | API 可用时走 `UsersApi.getMyRestrictions()`；API 不可用时回退到 Supabase 直连 `user_profiles` |

---

## 二、仍使用 Supabase 直连或回退的模块

### 1. 核心逻辑层（Repository / Service）

| 文件 | 问题 | 建议 |
|------|------|------|
| **user_restrictions.dart** | API 不可用时直连 Supabase `user_profiles` | 移除 Supabase 回退，API 不可用时返回 null |
| **teacher_repository.dart** | 大量使用 Supabase 直连（`_client`） | 需迁移到 TeachersApi，或 API 不可用时返回空/抛错 |
| **call_invitation_repository.dart** | 使用 Supabase 获取 Agora Token（Edge Function） | 后端需提供 `/api/call/agora-token`，前端改用 MiscApi |

### 2. 页面层（Page）

| 文件 | 问题 | 建议 |
|------|------|------|
| **add_friend_page.dart** | `_MyQrCard._loadShortId` 在 API 不可用时直连 Supabase `user_profiles` | 移除 Supabase 回退，仅用 UsersApi + SupabaseUserSync |
| **chat_detail_page.dart** | ① `_ensurePeerId` 在 API 不可用时直连 `chat_members`<br>② `_sendMediaBytes` 用 `SupabaseBootstrap.isReady` 判断能否发媒体 | ① 移除 Supabase 回退，仅用 MessagesApi.getPeerId<br>② 改为 `ApiClient.instance.isAvailable` |
| **customer_service_workbench_page.dart** | API 不可用时直连 `user_profiles` 批量查 display_name/avatar | 移除 Supabase 回退，仅用 UsersApi.getProfilesBatch |
| **group_settings_page.dart** | `_editGroupAvatar` 用 `SupabaseBootstrap.isReady` 判断能否上传 | 改为 `ApiClient.instance.isAvailable` |
| **rankings_page.dart** | API 不可用时直连 `teacher_profiles` stream | 移除 Supabase 回退，仅用 TeachersApi.watchRankings |
| **featured_teacher_page.dart** | ① `_load` 用 `SupabaseBootstrap.isReady` 阻塞加载<br>② 持仓同步等仍用 Supabase | ① 改为 `ApiClient.instance.isAvailable`<br>② 需 TeacherRepository 迁移 |
| **home_page.dart** | `_subscribeIncomingRequests`、`canLoadMessages` 依赖 `SupabaseBootstrap.isReady` | 改为 `ApiClient.instance.isAvailable` |
| **messages_page.dart** | `supabaseReady` 控制是否显示消息/登录提示 | 改为 `apiReady`（ApiClient.instance.isAvailable） |
| **report_page.dart** | 仅 import `supabase_bootstrap`，未实际使用 | 删除无用 import |

### 3. 其他

| 文件 | 问题 | 说明 |
|------|------|------|
| **notification_service.dart** | 调用 `SupabaseBootstrap.init()`，`_saveDeviceToken` 后检查 `SupabaseBootstrap.isReady` | 若完全移除 Supabase，需调整 init 逻辑；device token 已走 UsersApi |
| **profile_page.dart** | 头像上传失败提示 `profileAvatarUploadFailedNoSupabase` | 可改为「API 未配置」类提示 |

---

## 三、已完全走 API 的模块

- **FriendsRepository**：仅用 FriendsApi
- **MessagesRepository**：仅用 MessagesApi
- **ReportRepository**：仅用 ReportApi
- **CustomerServiceRepository**：仅用 MiscApi
- **ProfilePage**：头像/角色等走 UsersApi（SupabaseUserSync 仅用 AuthApi）
- **SupabaseUserSync**：仅用 AuthApi
- **LastOnlineService**：仅用 UsersApi
- **NotificationService**：device token 走 UsersApi（但 init 仍调 SupabaseBootstrap）

---

## 四、统一「就绪」判断建议

当前存在两套判断：

- `SupabaseBootstrap.isReady`：Supabase 已配置并初始化
- `ApiClient.instance.isAvailable`：`TONGXIN_API_URL` 已配置

**建议**：以 `ApiClient.instance.isAvailable` 作为「数据服务就绪」的唯一标准，逐步替换所有 `SupabaseBootstrap.isReady` 的 UI 判断。

---

## 五、后端 API 覆盖情况

以下能力已有后端 API，前端可直接使用：

- 用户：profile、restrictions、avatar 上传、last-online、device-tokens
- 好友：申请、列表、备注等
- 消息/会话：列表、消息、发送、媒体上传、群管理
- 举报：提交、截图上传
- 客服：配置、分配、广播等
- 配置：app_config 读写

以下需确认或新增：

- **Agora Token**：当前走 Supabase Edge Function，需后端提供 `/api/call/agora-token` 或类似接口
- **Teacher 相关**：TeacherRepository 仍大量用 Supabase，需 TeachersApi 补齐能力
