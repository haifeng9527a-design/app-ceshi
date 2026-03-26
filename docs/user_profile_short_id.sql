alter table public.user_profiles
add column if not exists short_id text;

create unique index if not exists user_profiles_short_id_idx
on public.user_profiles (short_id)
where short_id is not null;

alter table public.user_profiles
drop constraint if exists user_profiles_short_id_format;

alter table public.user_profiles
add constraint user_profiles_short_id_format
check (short_id is null or short_id ~ '^[0-9]{6,9}$');
