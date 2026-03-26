-- 排行榜收益口径 v2：
-- 1) 周/月/季/年/总收益全部使用「平仓已实现收益」
-- 2) 同时覆盖现货 + 期货（teacher_order_fills 全量，按 close 口径）
-- 3) 排行榜统一按 total_realized_pnl 排序
-- 4) 后端仅调用本函数，不在后端/前端做收益计算

create index if not exists teacher_order_fills_teacher_close_time_idx
  on public.teacher_order_fills (teacher_id, fill_time desc)
  where realized_pnl is not null;

create index if not exists teacher_positions_teacher_history_idx
  on public.teacher_positions (teacher_id, is_history);

drop function if exists public.get_teacher_rankings_real(boolean, integer);

create or replace function public.get_teacher_pnl_metrics(
  p_teacher_id text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
with target as (
  select trim(coalesce(p_teacher_id, '')) as teacher_id
),
closed_realized as (
  select
    f.teacher_id,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('week', now())
            and f.fill_time < date_trunc('week', now()) + interval '1 week'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as week_realized_pnl,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('month', now())
            and f.fill_time < date_trunc('month', now()) + interval '1 month'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as month_realized_pnl,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('quarter', now())
            and f.fill_time < date_trunc('quarter', now()) + interval '3 months'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as quarter_realized_pnl,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('year', now())
            and f.fill_time < date_trunc('year', now()) + interval '1 year'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as year_realized_pnl,
    coalesce(sum(coalesce(f.realized_pnl, 0)), 0)::numeric as total_realized_pnl
  from public.teacher_order_fills f
  join target t on t.teacher_id = f.teacher_id
  where
    f.realized_pnl is not null
  group by f.teacher_id
),
history_stats as (
  select
    p.teacher_id,
    count(*) filter (where coalesce(p.pnl_amount, 0) > 0)::int as wins,
    count(*) filter (where coalesce(p.pnl_amount, 0) < 0)::int as losses
  from public.teacher_positions p
  join target t on t.teacher_id = p.teacher_id
  where coalesce(p.is_history, false) = true
  group by p.teacher_id
)
select jsonb_build_object(
  'user_id', t.teacher_id,
  'week_realized_pnl', coalesce(r.week_realized_pnl, 0),
  'month_realized_pnl', coalesce(r.month_realized_pnl, 0),
  'quarter_realized_pnl', coalesce(r.quarter_realized_pnl, 0),
  'year_realized_pnl', coalesce(r.year_realized_pnl, 0),
  'total_realized_pnl', coalesce(r.total_realized_pnl, 0),
  'wins', coalesce(h.wins, 0),
  'losses', coalesce(h.losses, 0)
)
from target t
left join closed_realized r on r.teacher_id = t.teacher_id
left join history_stats h on h.teacher_id = t.teacher_id;
$$;

create or replace function public.get_teacher_rankings_real(
  p_only_approved boolean default true,
  p_limit integer default null
)
returns table (
  user_id text,
  week_realized_pnl numeric,
  month_realized_pnl numeric,
  quarter_realized_pnl numeric,
  year_realized_pnl numeric,
  total_realized_pnl numeric,
  wins integer,
  losses integer
)
language sql
security definer
set search_path = public
as $$
with teacher_base as (
  select tp.user_id
  from public.teacher_profiles tp
  where
    case
      when coalesce(p_only_approved, true)
        then lower(coalesce(tp.status, '')) = 'approved'
      else lower(coalesce(tp.status, '')) <> 'blocked'
    end
),
closed_realized as (
  select
    f.teacher_id,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('week', now())
            and f.fill_time < date_trunc('week', now()) + interval '1 week'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as week_realized_pnl,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('month', now())
            and f.fill_time < date_trunc('month', now()) + interval '1 month'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as month_realized_pnl,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('quarter', now())
            and f.fill_time < date_trunc('quarter', now()) + interval '3 months'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as quarter_realized_pnl,
    coalesce(
      sum(
        case
          when f.fill_time >= date_trunc('year', now())
            and f.fill_time < date_trunc('year', now()) + interval '1 year'
            then coalesce(f.realized_pnl, 0)
          else 0
        end
      ),
      0
    )::numeric as year_realized_pnl,
    coalesce(sum(coalesce(f.realized_pnl, 0)), 0)::numeric as total_realized_pnl
  from public.teacher_order_fills f
  where
    f.realized_pnl is not null
  group by f.teacher_id
),
history_stats as (
  select
    p.teacher_id,
    count(*) filter (where coalesce(p.pnl_amount, 0) > 0)::int as wins,
    count(*) filter (where coalesce(p.pnl_amount, 0) < 0)::int as losses
  from public.teacher_positions p
  where coalesce(p.is_history, false) = true
  group by p.teacher_id
),
ranked as (
  select
    tb.user_id,
    coalesce(r.week_realized_pnl, 0)::numeric as week_realized_pnl,
    coalesce(r.month_realized_pnl, 0)::numeric as month_realized_pnl,
    coalesce(r.quarter_realized_pnl, 0)::numeric as quarter_realized_pnl,
    coalesce(r.year_realized_pnl, 0)::numeric as year_realized_pnl,
    coalesce(r.total_realized_pnl, 0)::numeric as total_realized_pnl,
    coalesce(h.wins, 0)::int as wins,
    coalesce(h.losses, 0)::int as losses,
    row_number() over (
      order by
        coalesce(r.total_realized_pnl, 0) desc,
        coalesce(r.year_realized_pnl, 0) desc,
        coalesce(r.quarter_realized_pnl, 0) desc,
        coalesce(r.month_realized_pnl, 0) desc,
        coalesce(r.week_realized_pnl, 0) desc,
        tb.user_id asc
    ) as rn
  from teacher_base tb
  left join closed_realized r on r.teacher_id = tb.user_id
  left join history_stats h on h.teacher_id = tb.user_id
)
select
  user_id,
  week_realized_pnl,
  month_realized_pnl,
  quarter_realized_pnl,
  year_realized_pnl,
  total_realized_pnl,
  wins,
  losses
from ranked
where coalesce(p_limit, 0) <= 0 or rn <= p_limit
order by rn;
$$;
