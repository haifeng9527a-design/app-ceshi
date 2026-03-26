-- 评论回复关联：支持显示回复的是哪条评论
-- 在 Supabase Dashboard -> SQL Editor 中执行（可重复执行）

alter table public.teacher_comments
  add column if not exists reply_to_comment_id uuid references public.teacher_comments(id) on delete set null,
  add column if not exists reply_to_content text;

comment on column public.teacher_comments.reply_to_comment_id is '被回复的评论 ID';
comment on column public.teacher_comments.reply_to_content is '被回复评论的内容摘要，用于展示';
