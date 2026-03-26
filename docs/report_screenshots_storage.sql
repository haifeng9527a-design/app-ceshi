-- 举报截图存储：使用 avatars bucket 的 reports/ 路径
-- 路径格式: reports/{reporter_id}/{timestamp}_{filename}
-- 复用 avatars 的 anon 上传策略（bucket_id = 'avatars'），reports 路径需在 with check 中允许
-- 若 avatars 的 anon 策略已允许任意路径，则无需修改；否则添加：

-- 允许 authenticated/anon 上传举报截图到 avatars/reports/
drop policy if exists report_screenshots_upload on storage.objects;
create policy report_screenshots_upload on storage.objects
for insert to authenticated, anon
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = 'reports'
);

drop policy if exists report_screenshots_read on storage.objects;
create policy report_screenshots_read on storage.objects
for select to authenticated, anon
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'reports');
