-- 若 trade_strategies.teacher_id 上有指向 auth.users(id) 的外键，插入 Firebase UID 会报 invalid uuid。
-- 本脚本删除该外键（teacher_id 存的是 Firebase UID 文本，不应引用 auth.users 的 uuid）。
-- 先运行 check_trade_strategies_fk.sql 确认有外键后再执行，或直接执行（无此 FK 则跳过）。

do $$
declare
  r record;
begin
  for r in (
    select tc.constraint_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and tc.table_name = 'trade_strategies'
      and kcu.column_name = 'teacher_id'
  ) loop
    execute format('alter table public.trade_strategies drop constraint if exists %I', r.constraint_name);
    raise notice 'Dropped FK: %', r.constraint_name;
  end loop;
end $$;
