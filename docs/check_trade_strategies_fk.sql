-- 检查 trade_strategies 上的外键与触发器（若 teacher_id 引用 auth.users(id) 会导致 Firebase UID 报 uuid 错误）
-- 在 Supabase SQL Editor 中执行。

-- 1) 外键约束
select
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  ccu.table_schema as ref_schema,
  ccu.table_name as ref_table,
  ccu.column_name as ref_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
  and tc.table_name = 'trade_strategies';

-- 2) 触发器
select trigger_name, event_manipulation, action_statement
from information_schema.triggers
where event_object_schema = 'public' and event_object_table = 'trade_strategies';
