# 通知与角标问题逐步排查

## 常见结论（根据真机日志）

- **Android 通知权限请求结果: PermissionStatus.denied**  
  用户点了“不允许”或从未授权 → 系统不会显示任何通知、角标也不会显示。  
  **处理**：在 设置 → 应用 → teacher_hub → 通知 里打开“允许通知”，或下次打开 App 时在弹窗中点“允许”。

- **FCM token 获取失败: MISSING_INSTANCEID_SERVICE**  
  当前设备没有 Google 服务（如华为/荣耀），FCM 不可用，推送走**个推(Getui)**。  
  **处理**：服务端需用该设备的 Getui CID 发推送；应用内已改为在个推消息到达时也弹本地通知。

---

# 以下为逐步排查步骤

## 1. 用电脑连手机跑起来看日志

在项目根目录的 `app` 下执行（确保只连一台手机或指定设备）：

```bash
cd app
flutter run
```

启动后**先登录账号**，然后保持 App 在前台或后台，用另一台设备/账号给当前账号发一条聊天消息。

在终端里按下面顺序看有没有对应日志，判断卡在哪一步。

---

## 2. 按顺序看日志（都带 `[通知]` 前缀）

| 步骤 | 期望看到的日志 | 若没有说明 |
|-----|----------------|------------|
| 1 | `[通知] Firebase 初始化成功` | Firebase 没起来（如 google-services.json 缺失/错误），后面通知都不会有 |
| 2 | `[通知] NotificationService.init 开始` | 说明进了通知初始化 |
| 3 | `[通知] Android 通知权限请求结果: granted`（Android） | 若为 denied，系统会拦截通知栏和角标 |
| 4 | `[通知] 本地通知插件已初始化` | 本地通知库初始化成功 |
| 5 | `[通知] Android 通知渠道已创建`（Android） | 渠道创建成功 |
| 6 | `[通知] FCM onMessage 监听已注册` | 已注册“前台收到 FCM 消息”的监听 |
| 7 | `[通知] FCM token 获取: 成功` | 能拿到 FCM 设备 token |
| 8 | `[通知] 保存 device_token: platform=fcm userId=xxx` | **必须登录后才有**；没有则服务端无法给这台设备发推送 |
| 9 | `[通知] NotificationService.init 完成` | 整个通知初始化跑完 |

**若 7 有、8 没有**：说明当前没登录，token 不会写入数据库，推送也发不到这台设备。请登录后再看是否出现第 8 条。

---

## 3. 发一条消息后看是否收到 FCM

别人给你发一条消息后，看终端是否出现：

| 日志 | 含义 |
|------|------|
| `[通知] FCM onMessage 收到: notification=true` | FCM 收到了带 notification 的消息，会尝试显示系统通知 |
| `[通知] 消息无 notification 载荷，不显示系统通知` | 服务端发的是纯 data 消息，我们当前逻辑不弹系统通知 |
| `[通知] 本地通知已显示 id=xxx` | 本地通知已弹出 |
| `[通知] 显示本地通知失败: xxx` | 弹通知失败，看后面的异常原因 |
| `[通知] 角标 updateBadgeCount(count=x) supported=true/false` | 角标是否被调用、当前设备是否支持角标 |

---

## 4. 常见结论对照

- **没有「Firebase 初始化成功」**  
  检查 `android/app/google-services.json` 是否存在、包名是否与 Firebase 控制台一致。

- **没有「保存 device_token」**  
  先登录再试；或检查 Supabase 是否初始化成功、网络是否正常。

- **有「FCM onMessage 收到」但没有「本地通知已显示」**  
  看是否有「显示本地通知失败」；常见原因：通知权限被关、渠道/权限配置问题。

- **角标 supported=false**  
  当前设备/Launcher 可能不支持数字角标（仅支持红点或完全不支持），属系统/厂商限制。

- **从未出现「FCM onMessage 收到」**  
  要么服务端没发 FCM（或发错 token/用户），要么设备没收到 FCM；可在 Supabase `device_tokens` 表确认该用户是否有正确的 `token` 和 `platform=fcm`。

---

## 5. 服务端与数据库自查

1. **device_tokens 表**  
   当前登录用户的 `user_id` 下是否有 `platform = 'fcm'`（或 getui）的 token，且 `token` 非空、最近有更新。

2. **发送推送的时机**  
   确认发聊天消息时是否调用了 `send_push`（或你们自己的推送接口），且 `receiverId` 为当前用户的 ID。

3. **Android 系统设置**  
   设置 → 应用 → teacher_hub → 通知：确认未关闭通知，且“新消息”或对应渠道已开启。

按上述顺序跑一遍 `flutter run` 并把出现的 `[通知]` 日志贴出来，就能精确定位是权限、初始化、收消息还是展示/角标的问题。
