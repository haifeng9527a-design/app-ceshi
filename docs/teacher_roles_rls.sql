-- RLS policies for teacher tables

alter table public.teacher_profiles enable row level security;
alter table public.teacher_stats enable row level security;
alter table public.trade_strategies enable row level security;
alter table public.trade_records enable row level security;
alter table public.trade_record_files enable row level security;

-- teacher_profiles
drop policy if exists teacher_profiles_select_public on public.teacher_profiles;
create policy teacher_profiles_select_public
on public.teacher_profiles
for select
using (true);

drop policy if exists teacher_profiles_insert_owner on public.teacher_profiles;
create policy teacher_profiles_insert_owner
on public.teacher_profiles
for insert
with check (auth.uid()::text = user_id);

drop policy if exists teacher_profiles_update_owner on public.teacher_profiles;
create policy teacher_profiles_update_owner
on public.teacher_profiles
for update
using (auth.uid()::text = user_id);

-- teacher_stats (read-only for owner)
drop policy if exists teacher_stats_select_owner on public.teacher_stats;
create policy teacher_stats_select_owner
on public.teacher_stats
for select
using (auth.uid()::text = user_id);

-- trade_strategies
drop policy if exists trade_strategies_select_public on public.trade_strategies;
create policy trade_strategies_select_public
on public.trade_strategies
for select
using (status = 'published' or auth.uid()::text = teacher_id);

drop policy if exists trade_strategies_insert_owner on public.trade_strategies;
create policy trade_strategies_insert_owner
on public.trade_strategies
for insert
with check (auth.uid()::text = teacher_id);

drop policy if exists trade_strategies_update_owner on public.trade_strategies;
create policy trade_strategies_update_owner
on public.trade_strategies
for update
using (auth.uid()::text = teacher_id);

-- trade_records (owner only)
drop policy if exists trade_records_select_owner on public.trade_records;
create policy trade_records_select_owner
on public.trade_records
for select
using (auth.uid()::text = teacher_id);

drop policy if exists trade_records_insert_owner on public.trade_records;
create policy trade_records_insert_owner
on public.trade_records
for insert
with check (auth.uid()::text = teacher_id);

drop policy if exists trade_records_update_owner on public.trade_records;
create policy trade_records_update_owner
on public.trade_records
for update
using (auth.uid()::text = teacher_id);

-- trade_record_files (owner only)
drop policy if exists trade_record_files_select_owner on public.trade_record_files;
create policy trade_record_files_select_owner
on public.trade_record_files
for select
using (auth.uid()::text = teacher_id);

drop policy if exists trade_record_files_insert_owner on public.trade_record_files;
create policy trade_record_files_insert_owner
on public.trade_record_files
for insert
with check (auth.uid()::text = teacher_id);

drop policy if exists trade_record_files_update_owner on public.trade_record_files;
create policy trade_record_files_update_owner
on public.trade_record_files
for update
using (auth.uid()::text = teacher_id);
