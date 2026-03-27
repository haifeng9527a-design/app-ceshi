# teacher_hub

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Agora 通话配置

项目内语音/视频通话依赖 `AGORA_APP_ID` 和 Supabase Edge Function `get_agora_token`。

1. 在前端 `.env` 中配置 `AGORA_APP_ID`
2. 在 Supabase CLI 中配置项目 Secrets
3. 部署 `get_agora_token`

```powershell
supabase secrets set AGORA_APP_ID="<你的 Agora App ID>" --workdir .
supabase secrets set AGORA_APP_CERTIFICATE="<你的 Agora App Certificate>" --workdir .
supabase functions deploy get_agora_token --workdir .
```

也可以直接运行：

```powershell
.\deploy_send_push.ps1
```

如果只是临时联调，也可以在 Agora 控制台关闭项目的 Token 鉴权；这时客户端可在未拿到 token 时直接入会，但不建议长期这样配置。
