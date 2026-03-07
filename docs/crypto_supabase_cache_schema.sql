-- Crypto cache tables for tongxin-backend
-- Execute in Supabase SQL editor before enabling crypto cache pipeline.

create table if not exists public.crypto_pair_cache (
  symbol text primary key,
  name text,
  market text default 'crypto',
  last_quote_at_ms bigint,
  updated_at_ms bigint not null default (extract(epoch from now()) * 1000)::bigint
);

create index if not exists idx_crypto_pair_cache_updated
  on public.crypto_pair_cache (updated_at_ms desc);

create table if not exists public.crypto_quote_cache (
  symbol text primary key,
  payload_json jsonb not null,
  updated_at_ms bigint not null default (extract(epoch from now()) * 1000)::bigint
);

create index if not exists idx_crypto_quote_cache_updated
  on public.crypto_quote_cache (updated_at_ms desc);
