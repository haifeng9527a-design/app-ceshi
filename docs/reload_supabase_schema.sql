-- 刷新 Supabase PostgREST schema 缓存（改表结构后若 API 仍按旧类型校验可执行）
-- 在 Supabase SQL Editor 中执行，返回 "Success. No rows returned" 即生效。
notify pgrst, 'reload schema';
