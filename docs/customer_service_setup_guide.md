# 客服号配置指南

登录后看不到客服号，是因为 **Supabase 中尚未配置系统客服账号**。按以下步骤操作即可。

## 步骤 1：执行客服相关 SQL

在 Supabase 控制台 → SQL Editor 中执行：

```sql
-- 若尚未执行过 customer_service_schema.sql，先执行完整 schema
-- 见 docs/customer_service_schema.sql
```

## 步骤 2：创建或指定系统客服账号

系统客服需要是一个**真实用户账号**（Firebase UID + user_profiles 记录）。

**方式 A：使用现有账号作为客服**

1. 用该账号在 App 中登录一次，确保 `user_profiles` 有对应记录
2. 在 Firebase 控制台或 Supabase 的 `user_profiles` 表中找到该账号的 `user_id`（即 Firebase UID）

**方式 B：新建专用客服账号**

1. 在 App 中注册一个新账号（如 `kefu@example.com`）
2. 登录一次，让 Supabase 同步创建 `user_profiles`
3. 在 Supabase → Table Editor → `user_profiles` 中查看该账号的 `user_id`

## 步骤 3：配置系统客服 ID

在 Supabase SQL Editor 中执行（将 `你的客服账号user_id` 替换为实际 UID）：

```sql
-- 更新或插入配置
INSERT INTO public.app_config (key, value) 
VALUES ('customer_service_user_id', '你的客服账号user_id')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

例如，若客服账号的 user_id 为 `abc123xyz`：

```sql
INSERT INTO public.app_config (key, value) 
VALUES ('customer_service_user_id', 'abc123xyz')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

## 步骤 4：刷新 App

配置完成后：

1. 退出 App 到后台，再重新打开；或
2. 切换到「消息」页，系统会自动尝试添加客服为好友

客服号会出现在好友列表中，并带有「客服」标识。

## 可选：设置客服固定头像

```sql
INSERT INTO public.app_config (key, value) 
VALUES ('customer_service_avatar_url', 'https://你的头像URL')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

## 可选：设置客服人员（客服1、客服2...）

客服人员登录后可见「客服工作台」。在 Supabase 中将其 `user_profiles.role` 设为 `customer_service`：

```sql
UPDATE public.user_profiles 
SET role = 'customer_service' 
WHERE user_id = '客服人员的user_id';
```
