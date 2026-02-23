-- 将 teacher_id 从 uuid 改为 text，以兼容 Firebase UID（如 OFxSf3otmqaEJo7vvDwgJNORfbG2）
-- 在 Supabase SQL Editor 中执行。
--
-- 重要：必须一次性执行本文件全部内容（从第 1 行选到最后一行，再点 Run）。
-- 若只执行后半段（重建策略），teacher_id 列仍是 uuid，发布策略会继续报错。

-- ========== 1) 删除依赖 teacher_id 的 RLS 策略 ==========
drop policy if exists trade_strategies_select_public on public.trade_strategies;
drop policy if exists trade_strategies_insert_owner on public.trade_strategies;
drop policy if exists trade_strategies_update_owner on public.trade_strategies;

drop policy if exists trade_records_select_owner on public.trade_records;
drop policy if exists trade_records_insert_owner on public.trade_records;
drop policy if exists trade_records_update_owner on public.trade_records;

drop policy if exists trade_record_files_select_owner on public.trade_record_files;
drop policy if exists trade_record_files_insert_owner on public.trade_record_files;
drop policy if exists trade_record_files_update_owner on public.trade_record_files;

-- teacher_positions（若表存在且有策略）
drop policy if exists teacher_positions_select_owner on public.teacher_positions;
drop policy if exists teacher_positions_insert_owner on public.teacher_positions;
drop policy if exists teacher_positions_update_owner on public.teacher_positions;

-- ========== 2) 修改列类型 uuid -> text ==========
alter table public.trade_strategies
  alter column teacher_id type text using teacher_id::text;

alter table public.trade_records
  alter column teacher_id type text using teacher_id::text;

alter table public.trade_record_files
  alter column teacher_id type text using teacher_id::text;

-- teacher_positions（若存在）
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'teacher_positions' and column_name = 'teacher_id'
  ) then
    execute 'alter table public.teacher_positions alter column teacher_id type text using teacher_id::text';
  end if;
end $$;

-- ========== 3) 重新创建 RLS 策略 ==========
-- trade_strategies
create policy trade_strategies_select_public on public.trade_strategies
  for select using (status = 'published' or auth.uid()::text = teacher_id);
create policy trade_strategies_insert_owner on public.trade_strategies
  for insert with check (auth.uid()::text = teacher_id);
create policy trade_strategies_update_owner on public.trade_strategies
  for update using (auth.uid()::text = teacher_id);

-- trade_records
create policy trade_records_select_owner on public.trade_records
  for select using (auth.uid()::text = teacher_id);
create policy trade_records_insert_owner on public.trade_records
  for insert with check (auth.uid()::text = teacher_id);
create policy trade_records_update_owner on public.trade_records
  for update using (auth.uid()::text = teacher_id);

-- trade_record_files
create policy trade_record_files_select_owner on public.trade_record_files
  for select using (auth.uid()::text = teacher_id);
create policy trade_record_files_insert_owner on public.trade_record_files
  for insert with check (auth.uid()::text = teacher_id);
create policy trade_record_files_update_owner on public.trade_record_files
  for update using (auth.uid()::text = teacher_id);

-- teacher_positions（若表存在）
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'teacher_positions') then
    create policy teacher_positions_select_owner on public.teacher_positions
      for select using (auth.uid()::text = teacher_id);
    create policy teacher_positions_insert_owner on public.teacher_positions
      for insert with check (auth.uid()::text = teacher_id);
    create policy teacher_positions_update_owner on public.teacher_positions
      for update using (auth.uid()::text = teacher_id);
  end if;
end $$;
