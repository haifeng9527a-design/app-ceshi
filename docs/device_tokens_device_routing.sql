alter table public.device_tokens
  add column if not exists device_id text,
  add column if not exists manufacturer text,
  add column if not exists brand text,
  add column if not exists model text,
  add column if not exists os_name text,
  add column if not exists os_version text,
  add column if not exists app_version text,
  add column if not exists app_build text,
  add column if not exists preferred_push_provider text,
  add column if not exists supports_fcm boolean,
  add column if not exists supports_getui boolean;

create unique index if not exists device_tokens_user_device_platform_idx
  on public.device_tokens (user_id, device_id, platform)
  where device_id is not null;

create index if not exists device_tokens_user_updated_at_idx
  on public.device_tokens (user_id, updated_at desc);
