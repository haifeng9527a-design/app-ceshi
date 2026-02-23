# 通话与来电日志抓取说明

## 0. 双机通话日志 [TH_CALL]（排查接听/语音通道）

用于同时抓取**主叫（NOP）**和**被叫（ELS）**两台的 [TH_CALL] 日志，判断主叫是否收到 accepted、两端是否都加入 Agora 频道、是否触发 onUserJoined。

1. **两台手机 USB 连接电脑**，在 **`app`** 目录执行（若在项目根目录 `D:\teacher_hub`，先执行 `cd app`）：
   ```powershell
   cd app
   .\capture_call_logs_both.ps1
   ```
2. 脚本会清空两台设备的 logcat，然后开始抓取（仅包含含 `TH_CALL` 的行）。
3. **在本窗口做一通语音通话**：主叫发起 → 被叫接听（或拒绝）。
4. 结束后在本窗口 **按 Enter** 停止抓取。
5. 日志保存在 **`app\logs\`** 下：
   - `call_NOP_4EU_yyyyMMdd_HHmmss.log` — 主叫
   - `call_ELS_K5J_yyyyMMdd_HHmmss.log` — 被叫

**如何看日志：**

| 日志内容 | 含义 |
|----------|------|
| `主叫 进入通话页` / `被叫 进入通话页` | 该端已打开通话页，带 channelId、invitationId、tokenLen |
| `主叫 首次 getStatus => status=accepted` | 主叫一进页就查到已接听 |
| `主叫 轮询 getStatus => status=accepted` | 主叫轮询到已接听 |
| `主叫 执行：收到 accepted，开始计时` | 主叫 UI 应变为计时 |
| `getStatus id=xxx => status=null` | 主叫查不到该邀请（RLS 或 id 不一致） |
| `updateStatus id=xxx status=accepted` | 被叫已把邀请更新为 accepted |
| `onJoinChannelSuccess localUid=xxx channelId=xxx` | 该端已成功加入 Agora 频道 |
| `onUserJoined remoteUid=xxx` | 该端已发现对方进频道，语音通道应可用 |
| `onError err=xxx` | 该端加入或通话出错 |

若**主叫日志里没有** `getStatus => status=accepted` 或 `执行：收到 accepted`，说明主叫没拿到状态更新（轮询/RLS/网络）。若**两端都没有** `onUserJoined`，说明双方未在同一频道互相可见（Token/uid/网络）。

---

## 1. 抓取日志（单机 K5J 全量）

在 **`app`** 目录下执行（需已用 USB 连接 K5J 并开启 USB 调试）：

```powershell
cd app
.\capture_logs_k5j.ps1
```

- 会先清空设备 logcat 缓冲区，然后持续抓取并同时输出到终端和 **`app\logs_k5j.txt`**。
- 需要结束时按 **Ctrl+C**，日志会已写入 `logs_k5j.txt`。

建议操作：先运行脚本，再在另一台手机发起语音/视频通话，在 K5J 上接听或拒绝，然后停止脚本。

## 2. 查看与来电相关的日志

在 `logs_k5j.txt` 中可搜索：

| 关键字 | 含义 |
|--------|------|
| `来电` | 应用内打印的来电相关日志（Realtime/弹窗） |
| `call_invitation` | 来电邀请 |
| `postgres_changes` / `call_invitations` | Realtime 订阅到新来电 |
| `FCM` / `NotificationService` | 推送与通知服务 |
| `incoming_call` | 系统里“来电”通知渠道（铃声、震动） |
| `com.example.teacher_hub` | 本应用包名 |

## 3. 本次抓取结果摘要（约 09:13–09:15）

- **Realtime 来电订阅正常**：有 `postgres_changes 已订阅 call_invitations INSERT` 和 `已订阅 Realtime 来电`，说明应用内来电监听已建立。
- **FCM 不可用**：出现 `FCM token unavailable: MISSING_INSTANCEID_SERVICE`，K5J 若为无 GMS 的华为/荣耀机型，无法走 FCM 推送，来电只能依赖 Realtime/轮询。
- **已触发来电通知**：约 09:14:16 系统收到 `com.example.teacher_hub` 的 `incoming_call` 通知，并尝试播放系统铃声与震动；同时有 `HwNotificationService: Notificatin Switch is false`，表示系统侧可能关闭了该应用或该渠道的“通知开关”，导致不响铃、不弹条或仅静默。

## 4. 若 K5J 仍无铃声或接听界面

在 K5J 上检查：

1. **设置 → 应用 → teacher_hub → 通知**  
   - 打开“允许通知”。  
   - 找到“来电”或“语音/视频通话”类渠道，打开并允许**声音**、**震动**、**横幅/锁屏**等。
2. **设置 → 应用 → teacher_hub**  
   - 省电/自启动：允许自启动、后台活动，避免进程被系统杀掉导致收不到 Realtime 来电。
3. 若为华为/荣耀：**通知管理** 里确认“来电”渠道未被静音，且未勾选“静默通知”。
