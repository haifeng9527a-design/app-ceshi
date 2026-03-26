-- 策略支持多图：为 trade_strategies 增加 image_urls 列（Supabase SQL Editor 执行一次即可）
alter table public.trade_strategies
  add column if not exists image_urls text[] default '{}';

comment on column public.trade_strategies.image_urls is '策略配图 URL 列表，来自 Storage';
