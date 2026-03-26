-- Patch: teacher_account_ledger compatibility for multi-asset fields

create table if not exists public.teacher_account_ledger (
  id uuid primary key default gen_random_uuid(),
  teacher_id text not null,
  entry_type text not null,
  amount numeric not null,
  balance_after numeric not null,
  order_id uuid,
  symbol text,
  asset_class text,
  product_type text,
  side text,
  position_side text,
  note text,
  created_at timestamptz not null default now()
);

alter table public.teacher_account_ledger
  add column if not exists asset_class text,
  add column if not exists product_type text,
  add column if not exists side text,
  add column if not exists position_side text,
  add column if not exists note text,
  add column if not exists created_at timestamptz not null default now();

create index if not exists teacher_account_ledger_teacher_time_idx
  on public.teacher_account_ledger(teacher_id, created_at desc);
