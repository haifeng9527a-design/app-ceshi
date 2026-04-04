# Tongxin Frontend

Tongxin 的 Flutter 前端，支持移动端、桌面端和 Web。

## Local Development

```bash
flutter pub get
flutter run -d chrome
```

本项目会在启动时加载根目录 `.env`。你可以从 `.env.example` 复制一份本地配置。

最少需要：

```env
TONGXIN_API_URL=http://localhost:3000
```

如果要启用 Supabase / Firebase Web / 行情能力，再补齐对应变量。

## Render Deployment

这个仓库已经包含 Render 蓝图文件 `render.yaml` 和构建脚本 `scripts/render_build.sh`。

推荐部署方式：

1. 把前端仓库连接到 Render
2. 选择 `Blueprint`
3. 直接使用仓库根目录下的 `render.yaml`
4. 在 Render 后台补齐环境变量后发起部署

静态站点会执行：

```bash
./scripts/render_build.sh
```

脚本会在构建时动态生成 `.env`，然后执行 `flutter build web --release`。

### Required Render Env Vars

- `TONGXIN_API_URL`: 你的后端地址，例如 `https://your-backend.onrender.com`

### Common Optional Env Vars

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_MEASUREMENT_ID`
- `AGORA_APP_ID`
- `AGORA_TOKEN`
- `POLYGON_API_KEY`
- `TWELVE_DATA_API_KEY`
- `APP_DOWNLOAD_URL`
- `WEBVIEW_USER_PAGE_URL`
- `LOCAL_DEV_MODE`

## Agora

项目内语音/视频通话统一通过后端 `GET /api/call-invitations/agora-token` 获取 token，前端不再直连 Supabase Function。

前端至少需要：

```env
AGORA_APP_ID=<你的 Agora App ID>
TONGXIN_API_URL=http://localhost:3000
```

后端至少需要：

```env
AGORA_APP_ID=<你的 Agora App ID>
AGORA_APP_CERTIFICATE=<你的 Agora App Certificate>
```
