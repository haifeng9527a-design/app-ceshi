-- Storage policies for avatars bucket

-- Allow authenticated users to upload/update/delete their own avatars.
drop policy if exists avatars_upload_auth on storage.objects;
create policy avatars_upload_auth
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] in ('users', 'teachers')
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists avatars_update_auth on storage.objects;
create policy avatars_update_auth
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] in ('users', 'teachers')
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists avatars_delete_auth on storage.objects;
create policy avatars_delete_auth
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] in ('users', 'teachers')
  and (storage.foldername(name))[2] = auth.uid()::text
);

-- Allow read avatars (public display)
drop policy if exists avatars_read_auth on storage.objects;
create policy avatars_read_auth
on storage.objects
for select
to authenticated
using (bucket_id = 'avatars');

-- TEMP: allow anon to upload/update (Firebase-only auth)
drop policy if exists avatars_upload_anon on storage.objects;
create policy avatars_upload_anon
on storage.objects
for insert
to anon
with check (bucket_id = 'avatars');

drop policy if exists avatars_update_anon on storage.objects;
create policy avatars_update_anon
on storage.objects
for update
to anon
using (bucket_id = 'avatars');

drop policy if exists avatars_read_anon on storage.objects;
create policy avatars_read_anon
on storage.objects
for select
to anon
using (bucket_id = 'avatars');
