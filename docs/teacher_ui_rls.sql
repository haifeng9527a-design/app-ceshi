-- RLS for UI tables (strict)

alter table public.teacher_positions enable row level security;
alter table public.teacher_comments enable row level security;
alter table public.teacher_articles enable row level security;
alter table public.teacher_schedules enable row level security;

-- teacher_positions
drop policy if exists teacher_positions_select_owner on public.teacher_positions;
create policy teacher_positions_select_owner
on public.teacher_positions
for select
using (auth.uid()::text = teacher_id);

drop policy if exists teacher_positions_insert_owner on public.teacher_positions;
create policy teacher_positions_insert_owner
on public.teacher_positions
for insert
with check (auth.uid()::text = teacher_id);

drop policy if exists teacher_positions_update_owner on public.teacher_positions;
create policy teacher_positions_update_owner
on public.teacher_positions
for update
using (auth.uid()::text = teacher_id);

-- teacher_comments (public read, owner write)
drop policy if exists teacher_comments_select_public on public.teacher_comments;
create policy teacher_comments_select_public
on public.teacher_comments
for select
using (true);

drop policy if exists teacher_comments_insert_owner on public.teacher_comments;
create policy teacher_comments_insert_owner
on public.teacher_comments
for insert
with check (auth.uid()::text = teacher_id);

-- teacher_articles (public read, owner write)
drop policy if exists teacher_articles_select_public on public.teacher_articles;
create policy teacher_articles_select_public
on public.teacher_articles
for select
using (true);

drop policy if exists teacher_articles_insert_owner on public.teacher_articles;
create policy teacher_articles_insert_owner
on public.teacher_articles
for insert
with check (auth.uid()::text = teacher_id);

-- teacher_schedules (public read, owner write)
drop policy if exists teacher_schedules_select_public on public.teacher_schedules;
create policy teacher_schedules_select_public
on public.teacher_schedules
for select
using (true);

drop policy if exists teacher_schedules_insert_owner on public.teacher_schedules;
create policy teacher_schedules_insert_owner
on public.teacher_schedules
for insert
with check (auth.uid()::text = teacher_id);
