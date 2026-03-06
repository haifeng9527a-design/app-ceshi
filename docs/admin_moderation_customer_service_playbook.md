# 后台举报与客服操作手册

## 1. 举报审核处理流程

### 1.1 审核入口
- 管理后台 -> `举报管理`
- 每条待处理举报点击 `处理工单`

### 1.2 审核结论
- 通过并处罚：会执行处罚动作，并把举报状态改为 `approved`
- 驳回：只把举报状态改为 `rejected`

### 1.3 可选处罚动作（可多选）
- 冻结账号 -> 写入 `user_profiles.frozen_until`
- 封禁账号 -> 写入 `user_profiles.banned_until`
- 停止发消息 -> 写入 `user_profiles.restrict_send_message=true`
- 停止加好友 -> 写入 `user_profiles.restrict_add_friend=true`
- 停止加群 -> 写入 `user_profiles.restrict_join_group=true`
- 停止建群 -> 写入 `user_profiles.restrict_create_group=true`

### 1.4 时长规则
- 7 天 / 30 天 / 90 天：写入对应截止时间
- 永久：写入远期时间 `2099-01-01`

### 1.5 审核追踪字段
- `user_reports.status`
- `user_reports.admin_notes`
- `user_reports.reviewed_by`
- `user_reports.reviewed_at`

## 2. 后端限制生效说明

为了防止“仅前端限制可绕过”，后端已对关键写接口做限制校验：

- 发消息：`/api/messages`
- 发起单聊：`/api/conversations/direct`
- 建群：`/api/conversations/group`
- 邀请入群：`/api/conversations/:id/members`
- 发好友申请：`/api/friends/requests`
- 接受好友申请：`/api/friends/requests/:requestId/accept`

若命中限制，接口返回 `403` 与具体原因（如“账号已限制发消息”）。

## 3. 客服设置重构后的结构

管理后台 -> `设置` -> 客服配置，分为四个标签：

1. 系统客服账号
   - 选择唯一系统客服账号
   - 设置客服头像 URL / 上传头像
   - 设置欢迎语
2. 客服人员
   - 查看当前客服人员
   - 添加 / 移除客服角色
3. 分配规则
   - 展示当前分配规则说明
   - 展示每个客服当前已分配用户数
4. 群发中心
   - 编辑群发内容
   - 发送并查看执行反馈

## 4. 客服分配逻辑

- 若用户已有分配记录，优先复用
- 否则从在线客服池分配
- 在线池为空时回退到系统客服账号

相关接口：
- `/api/customer-service/assign-or-get`
- `/api/customer-service/stats`

## 5. 建议运营规范

- “通过并处罚”时建议填写处理备注，便于复盘
- 封禁/冻结优先用于严重违规；轻度违规建议先禁言、禁加好友
- 每周查看一次客服分配统计，避免个别客服超载
