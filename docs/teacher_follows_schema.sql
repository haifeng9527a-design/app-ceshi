-- Teacher follow relations
create table if not exists public.teacher_follows (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  user_id text not null,
  created_at timestamp with time zone not null default now()
);

create index if not exists teacher_follows_teacher_idx
  on public.teacher_follows (teacher_id);

create index if not exists teacher_follows_user_idx
  on public.teacher_follows (user_id);

create unique index if not exists teacher_follows_unique
  on public.teacher_follows (teacher_id, user_id);
