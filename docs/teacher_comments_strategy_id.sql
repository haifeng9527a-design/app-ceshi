-- 为 teacher_comments 添加 strategy_id，支持每条策略独立评论
-- 在 Supabase SQL Editor 中执行（可重复执行）

alter table public.teacher_comments
  add column if not exists strategy_id text;

comment on column public.teacher_comments.strategy_id is '关联的策略 ID，为空表示旧版教师级评论';

create index if not exists teacher_comments_strategy_idx
  on public.teacher_comments (strategy_id) where strategy_id is not null;
