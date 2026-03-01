-- 评论功能完整修复：策略评论 + RLS + Realtime
-- 在 Supabase Dashboard -> SQL Editor 中执行（可重复执行）

-- 1. 添加 strategy_id 列（支持每条策略独立评论）
alter table public.teacher_comments
  add column if not exists strategy_id text;

comment on column public.teacher_comments.strategy_id is '关联的策略 ID，为空表示旧版教师级评论';

create index if not exists teacher_comments_strategy_idx
  on public.teacher_comments (strategy_id) where strategy_id is not null;

-- 2. 修复 RLS：允许已登录用户发表评论（原策略仅允许教师本人插入）
drop policy if exists teacher_comments_insert_owner on public.teacher_comments;
drop policy if exists teacher_comments_insert_authenticated on public.teacher_comments;
create policy teacher_comments_insert_authenticated on public.teacher_comments
  for insert
  with check (auth.jwt()->>'sub' is not null);

-- 3. 评论回复关联（显示回复的是哪条评论）
alter table public.teacher_comments
  add column if not exists reply_to_comment_id uuid references public.teacher_comments(id) on delete set null,
  add column if not exists reply_to_content text;

-- 4. 确保 teacher_comments 在 Realtime 发布中（评论实时显示）
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'teacher_comments'
  ) then
    alter publication supabase_realtime add table public.teacher_comments;
  end if;
exception
  when undefined_object then null;  -- 若 publication 不存在则忽略
end $$;
