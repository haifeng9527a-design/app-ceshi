-- Trading summary should be computed in DB function.
-- 后端仅调用 RPC，不在 Node 里做汇总计算。

create or replace function public.get_teacher_trading_summary(
  p_teacher_id text,
  p_account_type text default null
)
returns jsonb
language sql
security definer
set search_path = public
as $$
with requested as (
  select case
    when lower(coalesce(p_account_type, '')) in ('spot', 'contract')
      then lower(p_account_type)
    else null
  end as account_type
),
accounts as (
  select
    id,
    teacher_id,
    coalesce(currency, 'USD') as currency,
    lower(coalesce(account_type, 'spot')) as account_type,
    coalesce(margin_mode, 'cross') as margin_mode,
    greatest(1, coalesce(leverage, 1))::numeric as leverage,
    coalesce(cash_balance, 0)::numeric as cash_balance,
    coalesce(cash_available, 0)::numeric as cash_available,
    coalesce(cash_frozen, 0)::numeric as cash_frozen,
    coalesce(market_value, 0)::numeric as market_value,
    coalesce(used_margin, 0)::numeric as used_margin,
    coalesce(maintenance_margin, 0)::numeric as maintenance_margin,
    coalesce(margin_balance, coalesce(equity, 0))::numeric as margin_balance,
    coalesce(realized_pnl, 0)::numeric as realized_pnl,
    coalesce(unrealized_pnl, 0)::numeric as unrealized_pnl,
    coalesce(equity, 0)::numeric as equity
  from public.teacher_trading_accounts
  where teacher_id = p_teacher_id
),
selected as (
  select a.*
  from accounts a
  cross join requested r
  where r.account_type is null or a.account_type = r.account_type
),
agg as (
  select
    coalesce(sum(cash_balance), 0)::numeric as cash_balance,
    coalesce(sum(cash_available), 0)::numeric as cash_available,
    coalesce(sum(cash_frozen), 0)::numeric as cash_frozen,
    coalesce(sum(market_value), 0)::numeric as market_value,
    coalesce(sum(case when account_type = 'spot' then market_value else 0 end), 0)::numeric as spot_market_value,
    coalesce(sum(case when account_type = 'contract' then market_value else 0 end), 0)::numeric as contract_notional,
    coalesce(sum(used_margin), 0)::numeric as used_margin,
    coalesce(sum(maintenance_margin), 0)::numeric as maintenance_margin,
    coalesce(sum(margin_balance), 0)::numeric as margin_balance,
    coalesce(sum(realized_pnl), 0)::numeric as realized_pnl,
    coalesce(sum(unrealized_pnl), 0)::numeric as unrealized_pnl,
    coalesce(sum(equity), 0)::numeric as equity,
    coalesce(max(leverage), 1)::numeric as leverage,
    coalesce(
      max(case when account_type = 'contract' then nullif(margin_mode, '') end),
      max(nullif(margin_mode, '')),
      'cross'
    ) as margin_mode,
    coalesce(
      max(case
        when account_type = 'spot' then case when upper(currency) = 'USDT' then 'USDT' else 'USD' end
        else null
      end),
      max(case
        when account_type = 'contract' then case when upper(currency) = 'USDT' then 'USDT' else 'USD' end
        else null
      end),
      'USD'
    ) as currency
  from selected
),
counts as (
  select
    (
      select count(*)::int
      from public.teacher_orders o
      cross join requested r
      where o.teacher_id = p_teacher_id
        and o.status in ('pending', 'partial')
        and (r.account_type is null or lower(coalesce(o.account_type, 'spot')) = r.account_type)
    ) as open_orders,
    (
      select count(*)::int
      from public.teacher_positions p
      cross join requested r
      where p.teacher_id = p_teacher_id
        and coalesce(p.is_history, false) = false
        and (r.account_type is null or lower(coalesce(p.account_type, 'spot')) = r.account_type)
    ) as positions_count
),
accounts_payload as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'teacher_id', a.teacher_id,
        'currency', a.currency,
        'account_type', a.account_type,
        'margin_mode', a.margin_mode,
        'leverage', a.leverage,
        'cash_balance', a.cash_balance,
        'cash_available', a.cash_available,
        'cash_frozen', a.cash_frozen,
        'market_value', a.market_value,
        'used_margin', a.used_margin,
        'maintenance_margin', a.maintenance_margin,
        'margin_balance', a.margin_balance,
        'realized_pnl', a.realized_pnl,
        'unrealized_pnl', a.unrealized_pnl,
        'equity', a.equity
      )
      order by a.account_type
    ),
    '[]'::jsonb
  ) as payload
  from accounts a
)
select jsonb_build_object(
  'account',
  jsonb_build_object(
    'teacher_id', p_teacher_id,
    'currency', agg.currency,
    'cash_balance', agg.cash_balance,
    'cash_frozen', agg.cash_frozen,
    'cash_available', agg.cash_available,
    'market_value', agg.market_value,
    'spot_market_value', agg.spot_market_value,
    'contract_notional', agg.contract_notional,
    'used_margin', agg.used_margin,
    'maintenance_margin', agg.maintenance_margin,
    'realized_pnl', agg.realized_pnl,
    'unrealized_pnl', agg.unrealized_pnl,
    'equity', agg.equity,
    'margin_balance', agg.margin_balance,
    'account_type', coalesce((select account_type from requested), 'aggregate'),
    'margin_mode', agg.margin_mode,
    'leverage', agg.leverage,
    'today_pnl', (agg.realized_pnl + agg.unrealized_pnl),
    'today_pnl_pct',
      case when agg.equity > 0 then ((agg.realized_pnl + agg.unrealized_pnl) / agg.equity) * 100 else 0 end,
    'available_pct',
      case when agg.equity > 0 then (agg.cash_available / agg.equity) else 0 end,
    'market_pct',
      case when agg.equity > 0 then (agg.spot_market_value / agg.equity) else 0 end,
    'spot_market_pct',
      case when agg.equity > 0 then (agg.spot_market_value / agg.equity) else 0 end,
    'margin_pct',
      case when agg.equity > 0 then (agg.used_margin / agg.equity) else 0 end,
    'frozen_pct',
      case when agg.equity > 0 then (agg.cash_frozen / agg.equity) else 0 end
  ),
  'accounts', (select payload from accounts_payload),
  'selected_account_type', coalesce((select account_type from requested), 'aggregate'),
  'open_orders', (select open_orders from counts),
  'positions', (select positions_count from counts)
)
from agg;
$$;
