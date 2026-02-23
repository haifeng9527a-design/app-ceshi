# 聊天媒体 24 小时清理

## 目的

用户多时，聊天图片/视频/语音/文件一天可能产生几十甚至上百 GB，容易占满服务器。  
**规则**：每个文件在服务器上只保留 **24 小时**，超过 24 小时就**自动从 Storage 删除**，持续腾出空间，避免存储被撑爆。

## 规则

- 聊天中的**图片、视频、语音、文件**在服务器只保留 **24 小时**。
- 超过 24 小时后，Storage 中的对应文件会被定时任务删除，以节省空间。
- 若接收方 24 小时内未下载，需发送方重新发送。
- 仅针对 `chat_messages` 中 `message_type` 为 `image` / `video` / `audio` / `file` 的 `media_url`、`media_url_transcoded` 所指向的 Storage 对象进行删除；聊天记录行与文本消息不受影响。

## 实现

- **Edge Function**：`supabase/functions/cleanup_chat_media/index.ts`
  - 查询 `created_at` 早于「当前时间 − 24 小时」且 `message_type` 为上述类型的消息。
  - 从 `media_url` / `media_url_transcoded` 解析出 `chat-media` bucket 下的对象路径并删除。
- **客户端**：点击文件时若下载失败（如 404），会提示「文件已过期或不存在，请让对方重新发送」。

## 部署与密钥

1. 部署函数（在项目根目录或 app 目录下，按你当前 Supabase 部署方式执行）：
   ```bash
   supabase functions deploy cleanup_chat_media
   ```
2. 在 Supabase 项目 **Settings → Edge Functions → Secrets** 中配置：
   - `CRON_SECRET`：一串随机字符串，用于校验定时调用方，避免被他人随意触发。

## 定时触发

- **执行逻辑**：每次执行时，会删除所有「创建时间早于 24 小时」的聊天媒体文件，所以**每个文件超过 24 小时就会被删**，从而持续给服务器腾空间。
- **执行频率建议**：
  - 用户量小：**每天一次**（如凌晨 3 点）即可。
  - 用户量大、一天可能几十上百 GB：建议 **每 1～6 小时执行一次**（例如每 2 小时），这样过期文件会更快被删，不会堆积太多占用空间。

任选一种方式配置定时任务：

### 方式一：Supabase Dashboard Cron（推荐）

若项目已启用 **pg_cron** 或 Supabase 提供的 Cron：

1. 在 Dashboard 中为该项目添加 Cron 任务。angang
### 方式三：本地或手动测试

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/cleanup_chat_media" \
  -H "Authorization: Bearer 你的CRON_SECRET"
```

返回示例：`{"ok":true,"deleted":12,"totalMessages":8,"expireMinutes":1440}`

**测试「5 分钟后删除」**：先发一条带图片/视频/文件的聊天，等 5 分钟后再调用，并加上 `?expireMinutes=5`，会删除「创建超过 5 分钟」的媒体，用于验证流程：

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/cleanup_chat_media?expireMinutes=5" \
  -H "Authorization: Bearer 你的CRON_SECRET"
```

## 说明

- 不修改 `chat_messages` 表：仅删除 Storage 文件，不把 `media_url` 置空，前端通过下载失败提示「已过期」。
- 已下载到本地的文件由客户端缓存（如 `ChatMediaCache`）保留，不受服务端删除影响。
