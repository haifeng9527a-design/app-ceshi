-- 客服头像存储：允许上传到 avatars/customer_service/
-- 在 Supabase SQL Editor 中执行

drop policy if exists avatars_upload_customer_service on storage.objects;
create policy avatars_upload_customer_service
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = 'customer_service'
);

drop policy if exists avatars_update_customer_service on storage.objects;
create policy avatars_update_customer_service
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = 'customer_service'
);
