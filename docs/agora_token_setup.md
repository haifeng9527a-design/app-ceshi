# Agora RTC Token 服务端下发

当声网控制台已开启 **Token 鉴权** 时，客户端必须使用有效 Token 才能加入频道；空 Token 会触发 `errInvalidToken` 并断开。本方案通过 Supabase Edge Function 按频道生成 Token，主叫/被叫在进入通话页前自动请求。

## 1. 部署 Edge Function

在 Supabase 项目下部署 `get_agora_token`：

```bash
cd app
supabase functions deploy get_agora_token
```

## 2. 配置 Secrets

在 Supabase Dashboard → Project Settings → Edge Functions → Secrets 中新增：

- `AGORA_APP_ID`：声网控制台项目 App ID
- `AGORA_APP_CERTIFICATE`：声网控制台项目 App Certificate（与 Token 鉴权配套）

若未配置 `AGORA_APP_CERTIFICATE`，接口仍返回 200，但 `token` 为空；客户端将用空字符串加入（仅当控制台**未**开启 Token 鉴权时有效）。

## 3. 客户端行为

- **主叫**：发起通话并创建邀请后，若 `.env` 未配置 `AGORA_TOKEN` 或为空，会请求 `get_agora_token`，传入 `channel_id` 与当前用户对应的 `uid`，将返回的 token 传入 `AgoraCallPage`。
- **被叫**：接听来电后，同样在未配置静态 Token 时请求 `get_agora_token`，传入邀请中的 `channelId` 与当前用户 `uid`，再进入 `AgoraCallPage`。

若已配置 `.env` 的 `AGORA_TOKEN`，则优先使用该静态 Token，不再请求 Edge Function。

## 4. 接口说明

- **方法**：`POST` 或 `GET`
- **鉴权**：建议通过 Supabase 配置要求携带 Firebase ID Token（与 `create_call_invitation` 一致）。
- **请求**：
  - POST body 或 GET query：`channel_id`（必填）、`uid`（可选，默认 0）
- **响应**：`{ "token": "<RTC Token>", "expireSeconds": 3600 }`，Token 有效期为 1 小时。

## 5. 依赖

Edge Function 通过 `https://esm.sh/agora-access-token@2.0.4` 动态生成 RTC Token。若部署环境无法访问 esm.sh 或包 API 变更，需在函数内改为本地上传的 token 生成逻辑或更换可用的 Agora Token 库。
