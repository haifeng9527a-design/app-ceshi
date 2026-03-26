-- 允许排行榜轮播卡片动态新增（不再限制固定 3 张卡）
alter table public.rankings_carousel_content
  drop constraint if exists rankings_carousel_content_card_key_check;

create index if not exists rankings_carousel_content_sort_order_idx
  on public.rankings_carousel_content(sort_order asc, updated_at desc);
