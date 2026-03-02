-- Storage policies for teacher records bucket
-- 路径格式：records/userId/xxx（交易记录）或 strategies/userId/xxx（策略配图）

-- Allow authenticated users to upload only to their own folder.
drop policy if exists teacher_records_upload on storage.objects;
create policy teacher_records_upload
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'teacher-records'
  and (storage.foldername(name))[1] in ('records', 'strategies')
  and (storage.foldername(name))[2] = auth.uid()::text
);

-- Allow authenticated users to update/delete only their own files.
drop policy if exists teacher_records_update on storage.objects;
create policy teacher_records_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'teacher-records'
  and (storage.foldername(name))[1] in ('records', 'strategies')
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists teacher_records_delete on storage.objects;
create policy teacher_records_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'teacher-records'
  and (storage.foldername(name))[1] in ('records', 'strategies')
  and (storage.foldername(name))[2] = auth.uid()::text
);
