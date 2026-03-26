-- DB-side trading summary aggregation
-- Used by backend API to avoid per-request Node-side summary assembly.

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
)
select jsonb_build_object(
  'account',
  jsonb_build_object(
    'teacher_id', acc.teacher_id,
    'currency', coalesce(acc.currency, 'USD'),
    'cash_balance', coalesce(acc.cash_balance, 0),
    'cash_frozen', coalesce(acc.cash_frozen, 0),
    'cash_available',
      greatest(
        0,
        (
          coalesce(acc.cash_balance, 0)
          + coalesce(pos.spot_market_value, 0)
          + coalesce(pos.contract_unrealized, 0)
        )
        - coalesce(pos.used_margin, 0)
        - coalesce(acc.cash_frozen, 0)
      ),
    'market_value', coalesce(pos.market_value, 0),
    'used_margin', coalesce(pos.used_margin, 0),
    'maintenance_margin', coalesce(pos.maintenance_margin, 0),
    'realized_pnl', coalesce(acc.realized_pnl, 0),
    'unrealized_pnl', coalesce(pos.unrealized_pnl, 0),
    'equity',
      (
        coalesce(acc.cash_balance, 0)
        + coalesce(pos.spot_market_value, 0)
        + coalesce(pos.contract_unrealized, 0)
      ),
    'margin_balance',
      (
        coalesce(acc.cash_balance, 0)
        + coalesce(pos.spot_market_value, 0)
        + coalesce(pos.contract_unrealized, 0)
      ),
    'account_type',
      case
        when coalesce(pos.has_contract_position, false) then 'contract'
        else coalesce(acc.account_type, 'spot')
      end,
    'margin_mode',
      case
        when coalesce(pos.has_contract_position, false) then coalesce(pos.dominant_margin_mode, 'cross')
        else coalesce(acc.margin_mode, 'cross')
      end,
    'leverage',
      case
        when coalesce(pos.has_contract_position, false) then coalesce(pos.dominant_leverage, 1)
        else coalesce(acc.leverage, 1)
      end
  ),
  'open_orders', coalesce(ord.open_orders, 0),
  'positions', coalesce(pos.positions_count, 0)
)
from acc
cross join pos
cross join ord;
$$;
