-- TEMP: allow anon access for UI tables (Firebase-only auth)

drop policy if exists teacher_positions_insert_anon on public.teacher_positions;
create policy teacher_positions_insert_anon
on public.teacher_positions
for insert
to anon
with check (true);

drop policy if exists teacher_positions_update_anon on public.teacher_positions;
create policy teacher_positions_update_anon
on public.teacher_positions
for update
to anon
using (true);

drop policy if exists teacher_comments_insert_anon on public.teacher_comments;
create policy teacher_comments_insert_anon
on public.teacher_comments
for insert
to anon
with check (true);

drop policy if exists teacher_articles_insert_anon on public.teacher_articles;
create policy teacher_articles_insert_anon
on public.teacher_articles
for insert
to anon
with check (true);

drop policy if exists teacher_schedules_insert_anon on public.teacher_schedules;
create policy teacher_schedules_insert_anon
on public.teacher_schedules
for insert
to anon
with check (true);
