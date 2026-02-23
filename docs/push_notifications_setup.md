# 推送配置（Android / iOS）

## 1) Supabase 表

```sql
create table public.device_tokens (
  user_id text not null,
  token text not null,
  platform text not null,
  updated_at timestamp with time zone not null default now(),
  constraint device_tokens_pkey primary key (user_id, token)
) tablespace pg_default;

create index if not exists device_tokens_user_idx
  on public.device_tokens using btree (user_id) tablespace pg_default;
```

## 2) 部署 Edge Function

目录：`app/supabase/functions/send_push/index.ts`

Edge Function 读取的环境变量（需在 Supabase 中配置为 Secrets）：

- `SB_URL`：Supabase 项目 URL（与前端用的 SUPABASE_URL 一致）
- `SB_SERVICE_ROLE_KEY`：Supabase Service Role Key（**不要**用 anon key）
- `FIREBASE_SERVICE_ACCOUNT_BASE64`：Firebase 服务账号 JSON 的 **Base64 编码**（用于 FCM HTTP v1 发推送）  
  可选（无 GMS 设备走个推）：`GETUI_APPID`、`GETUI_APPKEY`、`GETUI_MASTERSECRET`

8  8888888888888888888               哦  jio873@#, ,                                                                          w buy2te7834r8i476t5iyt9o58o64r859                              b      xA425ww335

**一键部署（推荐）**

在 **`app`** 目录下用 PowerShell 执行：

```powershell
cd app
.\deploy_send_push.ps1
```

会依次部署 `send_push` 与 `create_call_invitation`。若未登录或未关联项目，脚本会提示先执行 `supabase login` 和 `supabase link --project-ref <项目 ref>`（项目 ref 在 Supabase 控制台 → Project Settings → General → Reference ID）。**注意**：`supabase link` 也需在 `app` 目录执行（因函数在 `app/supabase/functions/`）。

**手动部署**

**1. 安装并登录 Supabase CLI**

```bash
npm install -g supabase
supabase login
```

**2. 在项目里关联 Supabase 项目**

在 **`app`** 目录执行（因 Edge Functions 在 `app/supabase/functions/`）：

```bash
cd app
supabase link --project-ref <你的项目 ref>
```

项目 ref 在 Supabase 控制台 → Project Settings → General → Reference ID。

**3. 设置 Secrets（环境变量）**

在**同一目录**下执行（把值换成你自己的）：

```bash
supabase secrets set SB_URL="https://xxxx.supabase.co"
supabase secrets set SB_SERVICE_ROLE_KEY="eyJhbGc..."
supabase secrets set FIREBASE_SERVICE_ACCOUNT_BASE64="<Firebase 服务账号 JSON 的 Base64>"
```

获取 Firebase 服务账号 Base64：

- Firebase 控制台 → 项目设置 → 服务账号 → 生成新的私钥，得到 JSON 文件。
- 在本地执行：`base64 -w 0 你的服务账号.json`（Linux/macOS）或 PowerShell：`[Convert]::ToBase64String([IO.File]::ReadAllBytes("你的服务账号.json"))`
- 把输出的整段字符串设为 `FIREBASE_SERVICE_ACCOUNT_BASE64` 的值。

**4. 部署函数**

在 **`app`** 目录（已执行过 `supabase link`）执行：

```bash
supabase functions deploy send_push --workdir .
supabase functions deploy create_call_invitation --workdir .
```

或直接运行脚本：`.\deploy_send_push.ps1`（会部署上述两个函数）。

部署成功后，控制台会给出各函数的 URL。`create_call_invitation` 需与 `send_push` 相同的 Secrets（`SB_URL`、`SB_SERVICE_ROLE_KEY` 等）；若使用个推，还需 `GETUI_APPID`、`GETUI_APPKEY`、`GETUI_MASTERSECRET`。

**通过 Supabase 控制台设置 Secrets（不用 CLI 时）**  
Dashboard → Project Settings → Edge Functions → 添加/编辑 Secrets：  
`SB_URL`、`SB_SERVICE_ROLE_KEY`、`FIREBASE_SERVICE_ACCOUNT_BASE64`。部署仍可用本地 CLI 在已 link 的目录执行 `supabase functions deploy send_push`（并视情况加 `--functions-dir app/supabase/functions`）。

## 3) Firebase 配置

将 `google-services.json` 放到：

`app/android/app/google-services.json`

并在 Firebase 控制台开启 Cloud Messaging。

## 3.1) iOS 推送配置

1. **Xcode 已配置**（工程内已完成）  
   - `ios/Runner/Runner.entitlements`：已添加 `aps-environment`（development）。  
   - `ios/Runner/Info.plist`：已添加 `UIBackgroundModes` → `remote-notification`。  
   - 使用真机运行或归档时，需在 Xcode 中为 Runner 勾选 **Signing & Capabilities → Push Notifications**（若未自动生效可手动加一次）。

2. **Firebase 控制台上传 APNs 密钥**（必须，否则 iOS 收不到推送）  
   - 打开 [Firebase 控制台](https://console.firebase.google.com) → 项目设置 → **Cloud Messaging**。  
   - 在「Apple 应用配置」中上传 **APNs 认证密钥**（.p8）：  
     - 在 [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) 创建 Key，勾选 **Apple Push Notifications service (APNs)**，下载 .p8，记下 Key ID 与 Team ID、Bundle ID。  
     - 在 Firebase 中上传该 .p8，并填写 Key ID、Team ID、Bundle ID（如 `com.example.teacherHub`）。  
   - 或使用 APNs 证书（.p12）上传亦可。

3. **上架 / TestFlight**  
   - 归档前将 `Runner.entitlements` 里的 `aps-environment` 改为 `production`，或由 Xcode 在添加 Push Notifications capability 时自动区分。

## 4) 推送为何有时收不到、不及时？

当前逻辑是：**发消息的一方**在发送成功后，由客户端请求 Edge Function `send_push` 给接收方推送。因此：

- 若发送方网络差、请求超时或 App 被系统杀掉，本次推送可能不会发出。
- 接收方有多台设备时，每台设备的 token 都会发一遍，一般不会漏。

**已做优化**：  
- 每条系统通知使用**唯一 ID**，避免“上一条能推送、下一条不显示”（之前因 ID 冲突被覆盖）。  
- 图片/视频等媒体消息也会带上接收方 ID，参与推送。  
- 推送请求失败时会**自动重试一次**，减少偶发失败。

**推荐：用数据库 Webhook 做服务端推送（发消息必出系统通知）**  
1. 部署 Edge Function：在 `app` 目录执行  
   `supabase functions deploy notify_new_message`  
2. 在 Supabase Dashboard → **Database** → **Webhooks** → **Create a new webhook**：  
   - **Name**：`chat_messages_insert`  
   - **Table**：`chat_messages`  
   - **Events**：勾选 **Insert**  
   - **Type**：`HTTP Request`  
   - **URL**：`https://<你的项目 ref>.supabase.co/functions/v1/notify_new_message`（例如 `https://theqizksqjrylsnrrrhx.supabase.co/functions/v1/notify_new_message`）  
   - **HTTP Headers**：添加 `Authorization` = `Bearer <service_role_key>`（在 Project Settings → API 里复制 service_role 密钥），否则 Webhook 请求可能返回 401。  
3. 保存后，每次向 `chat_messages` 插入新行，服务端都会自动查接收人并调用 `send_push`，**不依赖发送方 App 是否在线**，对方一定能触发系统推送。客户端仍可保留 `send_push` 调用作为补充。
