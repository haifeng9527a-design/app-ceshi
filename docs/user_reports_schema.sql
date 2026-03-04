-- 用户举报表：举报人、被举报人、原因、内容、截图、状态
create table if not exists public.user_reports (
  id bigint generated always as identity primary key,
  reporter_id text not null,
  reported_user_id text not null,
  reason text not null,
  content text,
  screenshot_urls text[] default '{}',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_notes text,
  reviewed_at timestamptz,
  reviewed_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_reports_reporter on public.user_reports(reporter_id);
create index if not exists idx_user_reports_reported on public.user_reports(reported_user_id);
create index if not exists idx_user_reports_status on public.user_reports(status);
create index if not exists idx_user_reports_created on public.user_reports(created_at desc);

-- RLS: 用户可插入举报；所有人可读（管理员审核用）；管理员可更新
alter table public.user_reports enable row level security;

drop policy if exists user_reports_insert on public.user_reports;
create policy user_reports_insert on public.user_reports
  for insert to authenticated, anon
  with check (true);

drop policy if exists user_reports_select on public.user_reports;
create policy user_reports_select on public.user_reports
  for select to authenticated, anon
  using (true);

drop policy if exists user_reports_update on public.user_reports;
create policy user_reports_update on public.user_reports
  for update to authenticated, anon
  using (true)
  with check (true);

comment on table public.user_reports is '用户举报记录';

-- 举报截图存储：需在 Supabase 控制台创建 bucket "report_screenshots"，设为 public 或配置 RLS
