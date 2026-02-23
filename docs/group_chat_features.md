# 群聊功能说明

## 一、功能清单

### 1. 建群（已实现）
- 选择好友、填写群名称
- 创建者自动为**群主**（role=owner）

### 2. 群设置页
- 入口：群聊会话 → 右上角菜单 →「群设置」
- 展示：群名称、群头像、群公告、成员数
- 操作：
  - **编辑群名称/群头像/群公告**（群主或管理员）
  - **邀请新成员**
  - **群成员列表**
  - **消息免打扰**（本地设置）
  - **退出群聊**
  - **解散群聊**（仅群主）

### 3. 邀请好友入群
- 从群设置进入「邀请新成员」
- 仅展示当前用户的好友且**未在群内**的用户
- 勾选后加入群（写入 chat_members）

### 4. 群成员列表
- 展示所有成员，标识群主/管理员/成员
- 群主可：移除成员（不可移除自己）、转让群主、设置/取消管理员
- 管理员可：移除普通成员
- 普通成员仅可查看

### 5. 退出群聊
- 任意成员可退出
- 从 chat_members 移除自己；若为群主退出则需先转让或解散

### 6. 解散群聊
- 仅群主可操作
- 删除会话（cascade 会删除成员与消息）

### 7. 角色与权限（建议）
- **owner**：转让群主、解散群、编辑群资料、邀请/移除/设管理员
- **admin**：邀请、移除普通成员、编辑群公告（可选）
- **member**：邀请（可选）、无移除权限

---

## 二、数据库扩展（Supabase 执行）

```sql
-- 群聊扩展字段
alter table chat_conversations add column if not exists created_by text;
alter table chat_conversations add column if not exists avatar_url text;
alter table chat_conversations add column if not exists announcement text;

-- 成员角色：owner / admin / member（已有 role，默认 member）
-- 建群时插入创建者 role='owner' 即可
```

---

## 三、实现顺序
1. 数据库迁移（如上）
2. Repository：群资料查询/更新、成员列表、邀请/移除/退出/解散、角色判断
3. 群设置页（含入口）
4. 邀请新成员页
5. 群成员列表页
6. 编辑群名称/群公告
7. 消息免打扰（本地）
