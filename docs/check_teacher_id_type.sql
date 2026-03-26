-- 检查 teacher_id 列当前类型。在 Supabase SQL Editor 中执行。
-- 若 data_type 为 'uuid'，需要执行 fix_teacher_id_to_text.sql 全文。
-- 若 data_type 已是 'text' 但 app 仍报 uuid 错误，先执行下面的「刷新 API 缓存」。

-- ========== 1) 查看列类型 ==========
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('trade_strategies', 'trade_records', 'trade_record_files', 'teacher_positions')
  and column_name = 'teacher_id'
order by table_name;

-- ========== 2) 若列已是 text 仍报错：刷新 PostgREST schema 缓存（执行下面一行） ==========
-- notify pgrst, 'reload schema';
