-- 评论用户头像：teacher_comments 增加 user_id 和 avatar_url
-- 在 Supabase SQL Editor 中执行

alter table public.teacher_comments
  add column if not exists user_id text,
  add column if not exists avatar_url text;

comment on column public.teacher_comments.user_id is '评论者 Firebase UID，用于关联 user_profiles';
comment on column public.teacher_comments.avatar_url is '评论者头像 URL，发表时从 user_profiles 同步';
