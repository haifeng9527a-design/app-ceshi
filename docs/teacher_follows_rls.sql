-- RLS policies for teacher_follows
alter table public.teacher_follows enable row level security;

drop policy if exists teacher_follows_select_public on public.teacher_follows;
create policy teacher_follows_select_public
on public.teacher_follows
for select
using (true);

drop policy if exists teacher_follows_insert_owner on public.teacher_follows;
create policy teacher_follows_insert_owner
on public.teacher_follows
for insert
with check (auth.uid()::text = user_id);

drop policy if exists teacher_follows_delete_owner on public.teacher_follows;
create policy teacher_follows_delete_owner
on public.teacher_follows
for delete
using (auth.uid()::text = user_id);
