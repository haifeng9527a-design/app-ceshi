-- Fix trading summary: available funds should use account cash_available
-- instead of re-deriving from equity.

create or replace function public.get_teacher_trading_summary(
  p_teacher_id text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
with acc as (
  select *
  from public.teacher_trading_accounts
  where teacher_id = p_teacher_id
  limit 1
),
pos as (
  select
    count(*)::int as positions_count,
    coalesce(sum(coalesce(current_price, 0) * coalesce(buy_shares, 0) * coalesce(contract_size, 1) * coalesce(multiplier, 1)), 0)::numeric as market_value,
    coalesce(sum(coalesce(floating_pnl, 0)), 0)::numeric as unrealized_pnl,
    coalesce(sum(coalesce(used_margin, 0)), 0)::numeric as used_margin,
    coalesce(sum(coalesce(maintenance_margin, 0)), 0)::numeric as maintenance_margin,
    coalesce(sum(
      case
        when coalesce(product_type, 'spot') = 'spot'
          then coalesce(current_price, 0) * coalesce(buy_shares, 0) * coalesce(contract_size, 1) * coalesce(multiplier, 1)
        else 0
      end
    ), 0)::numeric as spot_market_value,
    coalesce(sum(
      case
        when coalesce(product_type, 'spot') in ('perpetual', 'future')
          then coalesce(floating_pnl, 0)
        else 0
      end
    ), 0)::numeric as contract_unrealized,
    coalesce(bool_or(coalesce(product_type, 'spot') in ('perpetual', 'future')), false) as has_contract_position,
    coalesce(
      max(nullif(margin_mode, '')) filter (where coalesce(product_type, 'spot') in ('perpetual', 'future')),
      max(nullif(margin_mode, '')),
      'cross'
    ) as dominant_margin_mode,
    coalesce(
      max(leverage) filter (where coalesce(product_type, 'spot') in ('perpetual', 'future')),
      max(leverage),
      1
    )::numeric as dominant_leverage
  from public.teacher_positions
  where teacher_id = p_teacher_id
    and coalesce(is_history, false) = false
),
ord as (
  select count(*)::int as open_orders
  from public.teacher_orders
  where teacher_id = p_teacher_id
    and status in ('pending', 'partial')
),
agg as (
  select
    acc.teacher_id,
    coalesce(acc.currency, 'USD') as currency,
    coalesce(acc.cash_balance, 0)::numeric as cash_balance,
    coalesce(acc.cash_available, 0)::numeric as cash_available,
    coalesce(acc.cash_frozen, 0)::numeric as cash_frozen,
    coalesce(pos.market_value, 0)::numeric as market_value,
    coalesce(pos.used_margin, 0)::numeric as used_margin,
    coalesce(pos.maintenance_margin, 0)::numeric as maintenance_margin,
    coalesce(acc.realized_pnl, 0)::numeric as realized_pnl,
    coalesce(pos.unrealized_pnl, 0)::numeric as unrealized_pnl,
    (
      coalesce(acc.cash_balance, 0)
      + coalesce(pos.spot_market_value, 0)
      + coalesce(pos.contract_unrealized, 0)
    )::numeric as equity,
    case
      when coalesce(pos.has_contract_position, false) then 'contract'
      else coalesce(acc.account_type, 'spot')
    end as account_type,
    case
      when coalesce(pos.has_contract_position, false) then coalesce(pos.dominant_margin_mode, 'cross')
      else coalesce(acc.margin_mode, 'cross')
    end as margin_mode,
    case
      when coalesce(pos.has_contract_position, false) then coalesce(pos.dominant_leverage, 1)
      else coalesce(acc.leverage, 1)
    end::numeric as leverage,
    coalesce(ord.open_orders, 0)::int as open_orders,
    coalesce(pos.positions_count, 0)::int as positions_count
  from acc
  cross join pos
  cross join ord
)
select jsonb_build_object(
  'account',
  jsonb_build_object(
    'teacher_id', agg.teacher_id,
    'currency', agg.currency,
    'cash_balance', agg.cash_balance,
    'cash_frozen', agg.cash_frozen,
    'cash_available', agg.cash_available,
    'market_value', agg.market_value,
    'used_margin', agg.used_margin,
    'maintenance_margin', agg.maintenance_margin,
    'realized_pnl', agg.realized_pnl,
    'unrealized_pnl', agg.unrealized_pnl,
    'equity', agg.equity,
    'margin_balance', agg.equity,
    'account_type', agg.account_type,
    'margin_mode', agg.margin_mode,
    'leverage', agg.leverage,
    'today_pnl', (agg.realized_pnl + agg.unrealized_pnl),
    'today_pnl_pct',
      case
        when agg.equity > 0 then ((agg.realized_pnl + agg.unrealized_pnl) / agg.equity) * 100
        else 0
      end,
    'available_pct',
      case
        when agg.equity > 0 then (agg.cash_available / agg.equity)
        else 0
      end,
    'market_pct',
      case
        when agg.equity > 0 then (agg.market_value / agg.equity)
        else 0
      end,
    'frozen_pct',
      case
        when agg.equity > 0 then (agg.cash_frozen / agg.equity)
        else 0
      end
  ),
  'open_orders', agg.open_orders,
  'positions', agg.positions_count
)
from agg;
$$;
