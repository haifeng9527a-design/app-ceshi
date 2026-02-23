-- Storage policies for teacher records bucket

-- Allow authenticated users to upload only to their own folder.
drop policy if exists teacher_records_upload on storage.objects;
create policy teacher_records_upload
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'teacher-records'
  and (storage.foldername(name))[1] = 'records'
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
  and (storage.foldername(name))[1] = 'records'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists teacher_records_delete on storage.objects;
create policy teacher_records_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'teacher-records'
  and (storage.foldername(name))[1] = 'records'
  and (storage.foldername(name))[2] = auth.uid()::text
);
