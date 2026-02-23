-- 群聊扩展：在 Supabase SQL Editor 执行
-- 若已存在列会报错，可忽略或改用 add column if not exists（部分 PG 支持）

alter table chat_conversations add column if not exists created_by text;
alter table chat_conversations add column if not exists avatar_url text;
alter table chat_conversations add column if not exists announcement text;

-- 成员角色已有：owner / admin / member，建群时创建者为 owner
