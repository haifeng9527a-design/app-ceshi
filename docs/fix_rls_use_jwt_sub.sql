-- 使用 Firebase JWT 时，auth.uid() 在 Postgres 中为 uuid 类型，会尝试把 JWT 的 sub（Firebase UID）
-- 转成 uuid 导致报错：invalid input syntax for type uuid。
-- 改用 auth.jwt()->>'sub' 直接取 JWT 的 sub 文本，不经过 uuid 解析。
-- 在 Supabase SQL Editor 中一次性执行本文件全部内容。

-- ========== 1) 删除现有策略 ==========
drop policy if exists trade_strategies_select_public on public.trade_strategies;
drop policy if exists trade_strategies_insert_owner on public.trade_strategies;
drop policy if exists trade_strategies_update_owner on public.trade_strategies;

drop policy if exists trade_records_select_owner on public.trade_records;
drop policy if exists trade_records_insert_owner on public.trade_records;
drop policy if exists trade_records_update_owner on public.trade_records;

drop policy if exists trade_record_files_select_owner on public.trade_record_files;
drop policy if exists trade_record_files_insert_owner on public.trade_record_files;
drop policy if exists trade_record_files_update_owner on public.trade_record_files;

drop policy if exists teacher_positions_select_owner on public.teacher_positions;
drop policy if exists teacher_positions_insert_owner on public.teacher_positions;
drop policy if exists teacher_positions_update_owner on public.teacher_positions;

-- ========== 2) 用 auth.jwt()->>'sub' 重建策略（与 Firebase UID 一致） ==========
-- trade_strategies
create policy trade_strategies_select_public on public.trade_strategies
  for select using (status = 'published' or (auth.jwt()->>'sub') = teacher_id);
create policy trade_strategies_insert_owner on public.trade_strategies
  for insert with check ((auth.jwt()->>'sub') = teacher_id);
create policy trade_strategies_update_owner on public.trade_strategies
  for update using ((auth.jwt()->>'sub') = teacher_id);

-- trade_records
create policy trade_records_select_owner on public.trade_records
  for select using ((auth.jwt()->>'sub') = teacher_id);
create policy trade_records_insert_owner on public.trade_records
  for insert with check ((auth.jwt()->>'sub') = teacher_id);
create policy trade_records_update_owner on public.trade_records
  for update using ((auth.jwt()->>'sub') = teacher_id);

-- trade_record_files
create policy trade_record_files_select_owner on public.trade_record_files
  for select using ((auth.jwt()->>'sub') = teacher_id);
create policy trade_record_files_insert_owner on public.trade_record_files
  for insert with check ((auth.jwt()->>'sub') = teacher_id);
create policy trade_record_files_update_owner on public.trade_record_files
  for update using ((auth.jwt()->>'sub') = teacher_id);

-- teacher_positions（若表存在）
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'teacher_positions') then
    create policy teacher_positions_select_owner on public.teacher_positions
      for select using ((auth.jwt()->>'sub') = teacher_id);
    create policy teacher_positions_insert_owner on public.teacher_positions
      for insert with check ((auth.jwt()->>'sub') = teacher_id);
    create policy teacher_positions_update_owner on public.teacher_positions
      for update using ((auth.jwt()->>'sub') = teacher_id);
  end if;
end $$;
