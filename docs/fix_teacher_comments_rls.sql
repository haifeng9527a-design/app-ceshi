-- 修复 teacher_comments RLS：允许已登录用户发表评论（评论对象为 teacher_id）
-- 原策略 auth.uid() = teacher_id 仅允许教师本人插入，导致关注者无法评论
-- 在 Supabase SQL Editor 中执行（可重复执行）

drop policy if exists teacher_comments_insert_owner on public.teacher_comments;
drop policy if exists teacher_comments_insert_authenticated on public.teacher_comments;
create policy teacher_comments_insert_authenticated on public.teacher_comments
  for insert
  with check (auth.jwt()->>'sub' is not null);
