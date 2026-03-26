# 聊天接口排查说明

## 接口与调用关系

### 前端调用链
```
MessagesPage
  → MessagesRepository.watchConversations(userId)
    → MessagesApi.getConversations()  // GET api/conversations
    → ApiClient.get() + Authorization: Bearer <FirebaseToken>
```

### 后端接口
| 路径 | 鉴权 | 说明 |
|------|------|------|
| GET /api/conversations | requireAuth | 会话列表 |
| GET /api/conversations/unread-count | requireAuth | 未读数 |
| GET /api/conversations/:id | requireAuth | 单个会话 |
| GET /api/conversations/:id/messages | requireAuth | 消息列表 |
| POST /api/messages | requireAuth | 发送消息 |

### 与其他接口的区别
- **教师/行情**：部分用 `optionalAuth`，未登录也能返回数据
- **聊天**：全部用 `requireAuth`，必须有效 Firebase Token + 后端 Firebase Admin 已配置

---

## 常见问题

### 1. 返回 401「未鉴权」
- 用户未登录，或 Token 未带上
- 后端 Firebase Admin 未配置（GOOGLE_APPLICATION_CREDENTIALS）时，requireAuth 会返回 503

### 2. 返回 503「鉴权服务未配置」
- 后端 `.env` 缺少 `GOOGLE_APPLICATION_CREDENTIALS` 或 `FIREBASE_PROJECT_ID`
- 需配置 Firebase Admin SDK 才能验证 Token

### 3. 返回 502（Supabase 查询失败）
- **最常见**：后端使用 `SUPABASE_ANON_KEY` 而非 `SUPABASE_SERVICE_ROLE_KEY`
- Anon Key 受 RLS 限制，后端请求无用户上下文，chat_members 等表查询会被 RLS 拦截
- **解决**：在 Supabase 控制台 → Settings → API 复制 **service_role** 密钥，写入后端 `.env`：
  ```
  SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  ```

### 4. 返回 200 但列表为空 []
- 用户确实没有会话（chat_members 中无该 user_id）
- 新用户需先加好友、发起会话才会有数据

### 5. 无法收发消息（收发都失败）

**排查顺序：**

| 步骤 | 检查项 | 如何验证 |
|------|--------|----------|
| 1 | 前端 `TONGXIN_API_URL` | 确认 `tongxin-frontend/.env` 有 `TONGXIN_API_URL` 且非空 |
| 2 | 后端可访问 | 浏览器访问 `{TONGXIN_API_URL}/health` 应返回 `{"ok":true}` |
| 3 | 用户已登录 | App 消息页需 Firebase 登录，否则 401 |
| 4 | 后端鉴权 | 后端 `.env` 需 `GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json` 且文件存在 |
| 5 | Supabase | 后端 `.env` 需 `SUPABASE_SERVICE_ROLE_KEY`（非 anon key） |

**收发流程：**
- **收**：WebSocket 实时推送（`/ws/chat`）+ Supabase Realtime；未连接时回退 2 秒轮询
- **发**：优先 WebSocket 发送；未连接时回退 `POST /api/messages`；失败时消息旁显示红感叹号

### 6. 部署后收发消息很慢

| 原因 | 说明 | 建议 |
|------|------|------|
| **Render 冷启动** | 免费版闲置约 15 分钟后休眠，首请求需 30–60 秒唤醒 | 用 cron 每 5 分钟请求 `/health` 保活；或升级付费计划 |
| **跨地域延迟** | 服务器在海外、用户在境内，单次请求 200–500ms | 考虑将后端部署到国内（如阿里云、腾讯云） |
| **轮询间隔** | 未连接 WS 时回退 2 秒轮询 | 已改为 WebSocket + Supabase Realtime 实时推送 |

**调试**：Flutter Debug 模式下控制台会输出 `[MessagesApi] GET/POST ... => 401/403/502 {...}`

---

## 调试

1. **前端**：已加 debugPrint，非 200 时会在控制台输出 `[MessagesApi] GET /api/conversations => 401 {...}`
2. **后端**：已加 console.warn，401 或 chat_members 查询失败时会打印
3. **手动测试**：用 Postman 等工具，带 `Authorization: Bearer <Firebase_ID_Token>` 请求 `GET http://192.168.1.105:3000/api/conversations`
