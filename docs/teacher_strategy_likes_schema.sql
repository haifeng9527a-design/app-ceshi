-- 今日交易策略点赞
-- 在 Supabase SQL Editor 中执行

create table if not exists public.teacher_strategy_likes (
  teacher_id text not null,
  user_id text not null,
  created_at timestamp with time zone not null default now(),
  primary key (teacher_id, user_id)
);

create index if not exists teacher_strategy_likes_teacher_idx
  on public.teacher_strategy_likes (teacher_id);

-- RLS
alter table public.teacher_strategy_likes enable row level security;

drop policy if exists teacher_strategy_likes_select on public.teacher_strategy_likes;
create policy teacher_strategy_likes_select on public.teacher_strategy_likes
  for select using (true);

drop policy if exists teacher_strategy_likes_insert on public.teacher_strategy_likes;
create policy teacher_strategy_likes_insert on public.teacher_strategy_likes
  for insert with check (auth.jwt()->>'sub' is not null);

drop policy if exists teacher_strategy_likes_delete on public.teacher_strategy_likes;
create policy teacher_strategy_likes_delete on public.teacher_strategy_likes
  for delete using (auth.uid()::text = user_id);
