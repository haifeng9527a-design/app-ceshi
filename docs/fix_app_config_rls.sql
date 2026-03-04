-- 修复 app_config RLS：允许 anon 读写（管理后台使用 anon 连接）
-- 在 Supabase SQL Editor 中执行

drop policy if exists app_config_select on public.app_config;
create policy app_config_select on public.app_config for select to authenticated, anon using (true);

drop policy if exists app_config_all on public.app_config;
create policy app_config_all on public.app_config for all to authenticated, anon using (true) with check (true);
