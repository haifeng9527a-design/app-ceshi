-- Storage policies for teacher verification bucket
-- Create bucket: teacher-verify

drop policy if exists teacher_verify_upload_auth on storage.objects;
create policy teacher_verify_upload_auth
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'teacher-verify'
  and (storage.foldername(name))[1] = 'teachers'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists teacher_verify_update_auth on storage.objects;
create policy teacher_verify_update_auth
on storage.objects
for update
to authenticated
using (
  bucket_id = 'teacher-verify'
  and (storage.foldername(name))[1] = 'teachers'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists teacher_verify_delete_auth on storage.objects;
create policy teacher_verify_delete_auth
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'teacher-verify'
  and (storage.foldername(name))[1] = 'teachers'
  and (storage.foldername(name))[2] = auth.uid()::text
);

-- 使用 Firebase 登录、用 anon key 访问时，必须启用下面 anon 策略，否则上传会 403
-- TEMP: allow anon to upload/update (Firebase-only auth)
drop policy if exists teacher_verify_upload_anon on storage.objects;
create policy teacher_verify_upload_anon
on storage.objects
for insert
to anon
with check (bucket_id = 'teacher-verify');

drop policy if exists teacher_verify_update_anon on storage.objects;
create policy teacher_verify_update_anon
on storage.objects
for update
to anon
using (bucket_id = 'teacher-verify');

-- anon 可读，便于应用展示已上传的图片（若 bucket 为私有也需此策略）
drop policy if exists teacher_verify_select_anon on storage.objects;
create policy teacher_verify_select_anon
on storage.objects
for select
to anon
using (bucket_id = 'teacher-verify');
