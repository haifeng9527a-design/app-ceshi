# Supabase 聊天核心设置

以下内容用于在 Supabase 中创建最小可用的聊天后端（会话 + 消息 + 未读数）。

## 1) 建表与触发器
在 Supabase SQL Editor 执行：

```sql
-- 用户资料表（同步 Firebase 用户）
create table if not exists user_profiles (
  user_id text primary key,
  display_name text,
  email text,
  avatar_url text,
  status text default 'online',
  updated_at timestamptz not null default now()
);

-- 好友申请表
create table if not exists friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id text not null,
  receiver_id text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now()
);

create index if not exists friend_requests_receiver_idx
  on friend_requests (receiver_id, status);

-- 好友关系表（双向）
create table if not exists friends (
  user_id text not null,
  friend_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id)
);

create index if not exists friends_user_idx
  on friends (user_id);

-- 会话表
create table if not exists chat_conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('direct', 'group')),
  title text,
  last_message text,
  last_time timestamptz,
  created_at timestamptz not null default now()
);

-- 成员表
create table if not exists chat_members (
  conversation_id uuid not null references chat_conversations(id) on delete cascade,
  user_id text not null,
  role text not null default 'member',
  unread_count int not null default 0,
  last_read_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- 消息表
create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references chat_conversations(id) on delete cascade,
  sender_id text not null,
  sender_name text not null,
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_conversation_idx
  on chat_messages (conversation_id, created_at);

create index if not exists chat_members_user_idx
  on chat_members (user_id);

-- 触发器：消息写入后更新会话摘要与未读数
create or replace function chat_on_message_insert()
returns trigger as $$
begin
  update chat_conversations
    set last_message = new.content,
        last_time = new.created_at
  where id = new.conversation_id;

  update chat_members
    set unread_count = unread_count + 1
  where conversation_id = new.conversation_id
    and user_id <> new.sender_id;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_chat_message_insert on chat_messages;
create trigger trg_chat_message_insert
after insert on chat_messages
for each row execute function chat_on_message_insert();
```

## 2) 示例数据（可选）
```sql
-- 创建一条会话与两位成员
insert into chat_conversations (type, title) values ('direct', '周远');
insert into chat_members (conversation_id, user_id, role)
select id, 'user_a', 'member' from chat_conversations limit 1;
insert into chat_members (conversation_id, user_id, role)
select id, 'user_b', 'member' from chat_conversations limit 1;
```

## 3) RLS 说明
此版本默认未启用 RLS，以便快速联调。正式上线前请开启 RLS 并添加安全策略。

若启用 RLS，客户端会通过 `chat_members` 的 UPDATE 来标记会话已读（`unread_count = 0`, `last_read_at = now()`）。需允许「当前用户只能更新自己的成员行」：

```sql
-- 若用 Supabase Auth：允许用户更新自己的 chat_members 行（标记已读）
alter table chat_members enable row level security;
create policy "Users can update own chat_members"
  on chat_members for update
  using (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);
```

若用 Firebase 等外部认证，需在 Supabase 侧用自定义 JWT 或 service role 更新，或通过 Edge Function 代理「标记已读」请求。

## 4) 图片 / 视频 / 语音支持（新增字段 + 存储桶）
为消息表增加媒体字段：

```sql
alter table chat_messages add column if not exists message_type text default 'text';
alter table chat_messages add column if not exists media_url text;
alter table chat_messages add column if not exists media_url_transcoded text;
alter table chat_messages add column if not exists duration_ms int;
alter table chat_messages add column if not exists local_path text;
```

更新触发器（让会话列表显示「[图片]/[视频]/[语音]」）：

```sql
create or replace function chat_on_message_insert()
returns trigger as $$
begin
  update chat_conversations
    set last_message = case
      when new.message_type = 'image' then '[图片]'
      when new.message_type = 'video' then '[视频]'
      when new.message_type = 'audio' then '[语音]'
      else new.content
    end,
        last_time = new.created_at
  where id = new.conversation_id;

  update chat_members
    set unread_count = unread_count + 1
  where conversation_id = new.conversation_id
    and user_id <> new.sender_id;

  return new;
end;
$$ language plpgsql;
```

创建存储桶（Storage）：
- 在 Supabase Storage 中新建桶：`chat-media`
- 设置为 Public（快速联调）

## 5) 触发器：保证发送方会话列表更新（推荐）

客户端会话列表通过 **Realtime 订阅 `chat_members`（当前用户）** 来刷新。发消息时上面触发器只更新了**非发送方**的 `unread_count`，发送方自己的 `chat_members` 行没有变化，Realtime 不会推送，导致发送后会话列表不置顶、最后一条不更新。

解决：给 `chat_members` 增加 `updated_at`，并在触发器里对**该会话所有成员**（含发送方）更新该字段，这样发送方也会收到 Realtime，列表会重新拉取并显示最新 `last_message` / `last_time`。

```sql
-- 若表已存在，先加列
alter table chat_members add column if not exists updated_at timestamptz not null default now();

-- 替换触发器：在更新未读数的同时，对该会话所有成员的 updated_at 更新（触发发送方 Realtime）
create or replace function chat_on_message_insert()
returns trigger as $$
begin
  update chat_conversations
    set last_message = case
      when new.message_type = 'image' then '[图片]'
      when new.message_type = 'video' then '[视频]'
      when new.message_type = 'audio' then '[语音]'
      else new.content
    end,
        last_time = new.created_at
  where id = new.conversation_id;

  update chat_members
    set unread_count = unread_count + 1
  where conversation_id = new.conversation_id
    and user_id <> new.sender_id;

  -- 让发送方所在行也更新，以便其 Realtime 订阅能收到事件，会话列表刷新
  update chat_members
    set updated_at = now()
  where conversation_id = new.conversation_id;

  return new;
end;
$$ language plpgsql;
```

## 6) 会话列表最后一条显示「我: xxx」（推荐）

当最后一条消息是自己发的时，会话列表应显示「我: 消息内容」而不是光秃秃的消息内容，避免误以为是对方发的。

在 Supabase SQL Editor 执行：

```sql
-- 会话表增加「最后一条消息的发送者」
alter table chat_conversations add column if not exists last_sender_id text;

-- 触发器里同时更新 last_sender_id；退群系统消息（system_leave）不更新会话摘要与未读，仅群主/管理员在聊天内可见
create or replace function chat_on_message_insert()
returns trigger as $$
begin
  if coalesce(new.message_type, 'text') = 'system_leave' then
    return new;
  end if;

  update chat_conversations
    set last_message = case
      when new.message_type = 'image' then '[图片]'
      when new.message_type = 'video' then '[视频]'
      when new.message_type = 'audio' then '[语音]'
      else new.content
    end,
        last_time = new.created_at,
        last_sender_id = new.sender_id
  where id = new.conversation_id;

  update chat_members
    set unread_count = unread_count + 1
  where conversation_id = new.conversation_id
    and user_id <> new.sender_id;

  update chat_members
    set updated_at = now()
  where conversation_id = new.conversation_id;

  return new;
end;
$$ language plpgsql;
```
