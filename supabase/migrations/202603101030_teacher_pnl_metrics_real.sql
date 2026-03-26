-- Real teacher PnL metrics and rankings should be computed in DB functions.
-- 口径：
-- - 持仓盈亏 = teacher_positions 当前未平仓的 floating_pnl 汇总
-- - 当月盈亏 / 总盈亏 / 年盈亏 = teacher_order_fills.realized_pnl 汇总
-- - 胜 / 负场 = teacher_positions 历史平仓记录 pnl_amount 正负统计

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
open_positions as (
  select
    p.teacher_id,
    coalesce(sum(coalesce(p.floating_pnl, p.pnl_amount, 0)), 0)::numeric as floating_pnl
  from public.teacher_positions p
  join target t on t.teacher_id = p.teacher_id
  where coalesce(p.is_history, false) = false
  group by p.teacher_id
),
realized as (
  select
    f.teacher_id,
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
  where f.realized_pnl is not null
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
  'floating_pnl', coalesce(op.floating_pnl, 0),
  'month_realized_pnl', coalesce(r.month_realized_pnl, 0),
  'year_realized_pnl', coalesce(r.year_realized_pnl, 0),
  'total_realized_pnl', coalesce(r.total_realized_pnl, 0),
  'wins', coalesce(h.wins, 0),
  'losses', coalesce(h.losses, 0)
)
from target t
left join open_positions op on op.teacher_id = t.teacher_id
left join realized r on r.teacher_id = t.teacher_id
left join history_stats h on h.teacher_id = t.teacher_id;
$$;

create or replace function public.get_teacher_rankings_real(
  p_only_approved boolean default true,
  p_limit integer default null
)
returns table (
  user_id text,
  floating_pnl numeric,
  month_realized_pnl numeric,
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
open_positions as (
  select
    p.teacher_id,
    coalesce(sum(coalesce(p.floating_pnl, p.pnl_amount, 0)), 0)::numeric as floating_pnl
  from public.teacher_positions p
  where coalesce(p.is_history, false) = false
  group by p.teacher_id
),
realized as (
  select
    f.teacher_id,
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
  where f.realized_pnl is not null
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
    coalesce(op.floating_pnl, 0)::numeric as floating_pnl,
    coalesce(r.month_realized_pnl, 0)::numeric as month_realized_pnl,
    coalesce(r.year_realized_pnl, 0)::numeric as year_realized_pnl,
    coalesce(r.total_realized_pnl, 0)::numeric as total_realized_pnl,
    coalesce(h.wins, 0)::int as wins,
    coalesce(h.losses, 0)::int as losses,
    row_number() over (
      order by
        coalesce(r.month_realized_pnl, 0) desc,
        coalesce(r.total_realized_pnl, 0) desc,
        coalesce(op.floating_pnl, 0) desc,
        tb.user_id asc
    ) as rn
  from teacher_base tb
  left join open_positions op on op.teacher_id = tb.user_id
  left join realized r on r.teacher_id = tb.user_id
  left join history_stats h on h.teacher_id = tb.user_id
)
select
  user_id,
  floating_pnl,
  month_realized_pnl,
  year_realized_pnl,
  total_realized_pnl,
  wins,
  losses
from ranked
where coalesce(p_limit, 0) <= 0 or rn <= p_limit
order by rn;
$$;
