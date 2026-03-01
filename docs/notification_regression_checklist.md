# 通知与启动回归验证清单

Step 5 加固后建议按下列项做回归验证。

## 1. 静态分析

```bash
cd app
flutter analyze
```

- 无 error，无新增 warning。

## 2. Android Release 启动

```bash
cd app
flutter run --release -d <android_device_id>
```

- 应用能正常启动，无闪退。
- 启动后进入首页 / 闪屏再进首页。

## 3. 推送：前台 / 后台 / 杀进程

- **前台**：App 在前台时发 FCM 测试消息 → 应收到通知或 in-app 处理（视 payload）。
- **后台**：App 在后台时发 FCM → 应弹出系统通知，不初始化 Supabase/Realtime。
- **杀进程**：强制结束 App 后发 FCM → 应弹出系统通知（后台 handler 能执行）。

## 4. 点击通知跳转

- 从系统通知栏点击一条「聊天」通知 → 应打开对应会话页（且使用与 MaterialApp 同一 navigatorKey，不静默失败）。
- Supabase 未配置时点击通知 → 应提示「Supabase 未配置，无法打开会话」，不静默失败。

## 5. Supabase 缺配置场景

- 不传 `SUPABASE_URL` / `SUPABASE_ANON_KEY`（或传空）启动 App。
- 预期：不崩溃；首页顶部有缺配置提示条；「消息」入口禁用（灰显、点击不切换）。
- 点击会跳转会话的通知时，应出现「Supabase 未配置，无法打开会话」提示。

## 6. 可选：来电 Realtime

- 已登录且 Supabase 就绪时，另一端发起来电 → 应收到 Realtime 来电并弹接听界面。
- 登出或 Supabase 未就绪时，不订阅 Realtime，无重复订阅/泄漏。

---

**检查项速查**

| 项           | 命令/操作              | 预期                         |
|--------------|------------------------|------------------------------|
| flutter analyze | `flutter analyze`     | 无 error                     |
| Release 启动 | `flutter run --release` | 正常启动不崩                 |
| 推送前台     | 发 FCM，App 在前台     | 收到/处理                    |
| 推送后台     | 发 FCM，App 在后台     | 系统通知，无 Supabase 初始化 |
| 推送杀进程   | 杀进程后发 FCM         | 系统通知                     |
| 点击通知     | 点聊天通知             | 进入对应会话                 |
| 缺配置       | 不配 Supabase 启动     | 提示条 + 消息禁用 + 点击提示 |
