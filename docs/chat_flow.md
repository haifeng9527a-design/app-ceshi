# 聊天模块逻辑梳理

## 1. 整体架构

- **数据层**
  - **Supabase**：`chat_conversations`（会话）、`chat_members`（成员与未读）、`chat_messages`（消息）
  - **MessagesRepository**：会话/消息的增删改查、发送、已读、群组与私聊创建
  - **FriendsRepository**：好友、备注、好友申请
  - **MessagesLocalStore**：本地缓存（会话列表、消息记录、草稿、置顶、静音、备注、黑名单等）

- **UI 层**
  - **MessagesPage**：会话列表 + 好友列表 Tab，`watchConversations` / `watchFriends` 实时流 + 本地缓存兜底
  - **ChatDetailPage**：单会话聊天，`watchMessages` 实时流 + 本地缓存 + 待发列表（乐观更新）

- **实时与缓存**
  - 会话列表：订阅 `chat_members`（当前用户），有变更时再查 `chat_conversations`，故**发送方**的会话行若未更新，列表不会刷新（见下方修复）
  - 消息列表：订阅 `chat_messages`（当前会话），首条立即、后续防抖合并，减少闪烁
  - 弱网/离线：先展示本地缓存，等流数据到达后覆盖

## 2. 发送流程（与常见 IM 对齐）

1. **输入**：用户输入文本/选图/录音等。
2. **乐观显示**：生成带 `localId` 的 `ChatMessage(isLocal: true)`，加入 `_pendingMessages`，清空输入框，立即滚动到底部。
3. **本地缓存**：把该条追加到 `MessagesLocalStore` 的该会话消息缓存（不阻塞 UI）。
4. **后台上传**：校验权限/好友后调用 `MessagesRepository.sendMessage` 写入 Supabase。
5. **服务端**：INSERT 触发 `chat_on_message_insert`：更新 `chat_conversations.last_message/last_time`，对非发送方 `chat_members.unread_count + 1`。
6. **对表（Reconcile）**：`watchMessages` 收到新消息后，在 builder 里用 `_reconcilePendingWithKeys`：按「发送者 + 内容 + 时间窗口」将服务端消息与 pending 对表，匹配到的从 pending 移除，用服务端 id 做 key 避免气泡闪动。
7. **失败**：仅业务失败（非好友/封禁）时移除该条并恢复输入框；网络失败只标记 `_failedLocalIds`，气泡旁显示重试。

## 3. 已读与未读

- 进入 ChatDetailPage 时调用 `markConversationRead`，将当前用户在该会话的 `chat_members.unread_count` 置 0、`last_read_at` 更新。
- 未读数来自 `chat_members.unread_count`，总未读用于角标等由 `getTotalUnreadCount` 提供。

## 4. 已知问题与修复

### 4.1 发送后会话列表不更新（已修复方案见下）

- **原因**：会话列表订阅的是 `chat_members`（当前用户）。发消息时触发器只更新了**非发送方**的 `unread_count`，发送方自己的 `chat_members` 行未变，Realtime 不推送，列表不刷新。
- **解决**：在触发器里对**该会话所有成员**（含发送方）更新一行可变更字段（如 `updated_at`），使发送方也能收到 Realtime，列表重新拉取并展示最新 `last_message` / `last_time`。见 `supabase_chat_setup.md` 中的「触发器：保证发送方会话列表更新」。

### 4.2 待发与服务端消息对表（已加固）

- **风险**：仅按 senderId + content 对表，在群聊中若两人短时间发相同内容可能对错。
- **加固**：对表时增加时间窗口（例如服务端消息 `created_at` 在 pending 时间前后 2 分钟内），超出窗口不匹配，减少误对。见 `chat_detail_page.dart` 中 `_reconcilePendingWithKeys`。

## 5. 与常见聊天应用对比

| 能力           | 本应用                     | 说明 |
|----------------|----------------------------|------|
| 乐观发送       | ✅ 先显后发                 | 与微信/Telegram 一致 |
| 弱网/离线缓存  | ✅ 会话+消息本地缓存        | 先显缓存再等流 |
| 未读/已读      | ✅ 未读数、进入即已读       | 无「已读」状态展示，可后续加 |
| 会话列表实时   | ✅ 依赖 chat_members 流     | 需触发器更新发送方行（见上） |
| 消息实时       | ✅ watchMessages + 防抖    | 正常 |
| 回复/引用      | ✅ reply_to 字段            | 支持 |
| 撤回           | ✅ 删除消息 API             | 支持 |
| 转发           | 占位「开发中」             | 未实现 |
| 输入状态       | 无                         | 可后续加 typing indicator |
| 最后上线时间   | ✅ 退出/后台/关聊天即更新   | 好友在聊天窗口可见，见 `last_online_at_schema.sql` |

## 6. 关键文件索引

- 模型：`message_models.dart`（Conversation / ChatMessage / GroupInfo 等）
- 仓库：`messages_repository.dart`、`friends_repository.dart`
- 本地：`messages_local_store.dart`
- 页面：`messages_page.dart`（会话+好友）、`chat_detail_page.dart`（聊天详情）
- 后端说明与触发器：`supabase_chat_setup.md`
- 最后上线时间：`user_profiles.last_online_at`，由 `LastOnlineService` 在 App 生命周期（后台/关闭）与离开聊天页时更新；`chat_detail_page.dart` 标题栏展示好友「最后上线：xxx」。
