# Agora 语音/视频通话流程说明

## 1. 配置校验（能否通话）

- **必须**：在项目根目录 `app/.env` 中配置 `AGORA_APP_ID`（声网控制台创建项目后获得）。
- **Token 鉴权**（二选一）：
  - **不开启**：声网控制台不启用 Token 鉴权时，可不配置 Token，两端用空字符串即可加入。
  - **开启**：在 Supabase 项目 Secrets 中配置 `AGORA_APP_ID`、`AGORA_APP_CERTIFICATE`，并部署 Edge Function `get_agora_token`。主叫/被叫进入通话页前会自动请求该频道的 Token；若未部署或未配置 CERTIFICATE，则使用空 Token（仅在不鉴权时有效）。也可在 `app/.env` 中配置静态 `AGORA_TOKEN` 优先使用。
- 代码中通过 `AgoraConfig.isAvailable` 判断（即 `AGORA_APP_ID` 非空）；未配置时发起通话会提示「未配置 Agora，无法发起通话」，被叫接听会提示「未配置 Agora App ID」并关闭。

**自测配置是否生效**：在聊天里点「语音通话」能进入通话页且无报错、且日志有 `[TH_CALL] 正在加入频道` / `joinChannel 成功` / `onJoinChannelSuccess localUid=xxx`，即说明配置可用。

---

## 2. 角色与页面

| 角色 | 入口 | 页面 |
|------|------|------|
| **主叫（呼叫方）** | 聊天页 → 语音/视频通话 | `AgoraCallPage`（带 `invitationId`） |
| **被叫（接听方）** | 来电弹窗 → 接听 | `AgoraCallPage`（无 `invitationId`） |

- 主叫：监听 `call_invitations` 该条邀请的 `status`（rejected / cancelled），并加入同一 `channelId`。
- 被叫：来电弹窗监听该条邀请的 `status`（cancelled）；接听后只加入频道，不监听邀请状态。

---

## 3. 完整流程与预期表现

### 3.1 主叫发起 → 被叫接听 → 接通

1. 主叫在聊天点「语音/视频通话」→ 创建邀请（status=ringing）→ 进入通话页并加入 Agora 频道。
2. 被叫收到来电（Realtime/轮询或推送）→ 弹出来电界面。
3. 被叫点「接听」→ 邀请 status 更新为 accepted → 被叫进入通话页并加入**同一** channelId。
4. 两端 Agora 互相触发 `onUserJoined` → 界面显示通话时长，可正常通话。

**预期**：双方都看到对方进入、显示计时，能听到声音。

---

### 3.2 主叫主动挂断（未接通时）

- **主叫**：点「挂断」→ 邀请 status 更新为 cancelled → 离开频道并关闭通话页。
- **被叫**：若仍在**来电弹窗**（未接听），会收到 status=cancelled → 来电弹窗关闭，并提示 **「对方已取消」**。

**预期**：主叫页面消失；被叫弹窗消失并看到「对方已取消」。

---

### 3.3 主叫主动挂断（已接通后）

- **主叫**：点「挂断」→ 邀请 status 更新为 cancelled → 离开频道并关闭通话页。
- **被叫**：Agora 触发 `onUserOffline` → 提示 **「对方已挂断」**，并自动关闭通话页。

**预期**：主叫页面消失；被叫先看到「对方已挂断」再页面关闭。

---

### 3.4 被叫拒绝

- **被叫**：在来电弹窗点「拒绝」→ 邀请 status 更新为 rejected → 弹窗关闭。
- **主叫**：监听 status=rejected → 提示 **「对方已拒绝」**，并关闭通话页。

**预期**：被叫弹窗消失；主叫看到「对方已拒绝」后页面关闭。

---

### 3.5 被叫接听后再挂断

- **被叫**：在通话页点「挂断」→ 离开频道并关闭通话页（不写邀请 status，因被叫未持有 invitationId）。
- **主叫**：Agora 触发 `onUserOffline` → 提示 **「对方已挂断」**，并自动关闭通话页。

**预期**：被叫页面消失；主叫看到「对方已挂断」后页面关闭。

---

## 4. 小结表

| 场景 | 主叫页面 | 被叫页面/弹窗 | 主叫提示 | 被叫提示 |
|------|----------|----------------|----------|----------|
| 主叫取消（未接通） | 关闭 | 来电弹窗关闭 | - | 「对方已取消」 |
| 主叫挂断（已接通） | 关闭 | 通话页关闭 | - | 「对方已挂断」 |
| 被叫拒绝 | 关闭 | 来电弹窗关闭 | 「对方已拒绝」 | - |
| 被叫挂断（已接通） | 关闭 | 关闭 | 「对方已挂断」 | - |

---

## 5. 若仍「等待对方接听」不接通

- 确认两端日志均有：`joinChannel 成功`、`onJoinChannelSuccess localUid=xxx`，且 **channelId 一致**。
- 若一端无上述日志，说明该端未成功加入频道（检查该端 .env / 网络）。
- 若两端都加入成功但仍无 `onUserJoined`，需排查声网控制台（同一 App ID、区域、Token 策略等）及网络/NAT。

---

## 6. 接听后能计时但听不到声音（正常通话必备）

界面已显示「已接通」和计时，但提示「若听不到声音请检查网络」说明：**信令已接通，但 Agora 尚未收到对方进频道**（`onUserJoined` 未触发），因此没有语音流。按下面自检：

1. **同一频道**：主叫、被叫使用的 `channelId` 必须完全一致（来自同一条邀请的 `channel_id`）。  
2. **Token**  
   - 声网控制台若未开启 Token 鉴权：可不配 Token，两端用空字符串加入。  
   - 若已开启 Token 鉴权：部署 Edge Function `get_agora_token` 并在 Supabase Secrets 中配置 `AGORA_APP_ID`、`AGORA_APP_CERTIFICATE`。主叫发起、被叫接听时会自动请求该 `channelId` 的 Token；或配置 `.env` 的 `AGORA_TOKEN` 作为静态 Token 优先使用。  
3. **加入失败**：任一端加入失败时，应用会提示「无法加入语音频道，请检查网络或 Token 配置」并退出。可看日志中的 `[TH_CALL] onError` 或异常信息。  
4. **麦克风权限**：两端都要允许应用使用麦克风，否则无法发话。  
5. **日志确认**：两端都应出现 `onJoinChannelSuccess` 和 `onUserJoined remoteUid=xxx`；若只有前者没有后者，说明对端未成功进频道或 UID/Token/网络异常。
