-- Split legacy single trading account into:
-- 1) spot account
-- 2) contract account (future + perpetual shared)
--
-- This migration preserves total equity by partitioning free cash, frozen cash,
-- spot market value, contract margin and contract unrealized PnL into two ledgers.

alter table public.teacher_trading_accounts
  add column if not exists id uuid default gen_random_uuid();

update public.teacher_trading_accounts
set id = gen_random_uuid()
where id is null;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conrelid = 'public.teacher_trading_accounts'::regclass
      and conname = 'teacher_trading_accounts_pkey'
  ) then
    alter table public.teacher_trading_accounts
      drop constraint teacher_trading_accounts_pkey;
  end if;
exception
  when undefined_table then null;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.teacher_trading_accounts'::regclass
      and conname = 'teacher_trading_accounts_pkey'
  ) then
    alter table public.teacher_trading_accounts
      add constraint teacher_trading_accounts_pkey primary key (id);
  end if;
exception
  when undefined_table then null;
end $$;

alter table public.teacher_orders
  add column if not exists account_id uuid,
  add column if not exists account_type text;

alter table public.teacher_positions
  add column if not exists account_id uuid,
  add column if not exists account_type text;

alter table public.teacher_order_fills
  add column if not exists account_id uuid,
  add column if not exists account_type text;

alter table public.teacher_account_ledger
  add column if not exists account_id uuid,
  add column if not exists account_type text;

update public.teacher_trading_accounts
set account_type = case
  when lower(coalesce(account_type, 'spot')) = 'contract' then 'spot'
  else 'spot'
end;

with
spot_positions as (
  select
    teacher_id,
    coalesce(sum(coalesce(current_price, 0) * coalesce(buy_shares, 0) * coalesce(contract_size, 1) * coalesce(multiplier, 1)), 0)::numeric as spot_market_value
  from public.teacher_positions
  where coalesce(is_history, false) = false
    and coalesce(product_type, 'spot') = 'spot'
  group by teacher_id
),
contract_positions as (
  select
    teacher_id,
    coalesce(sum(coalesce(current_price, 0) * coalesce(buy_shares, 0) * coalesce(contract_size, 1) * coalesce(multiplier, 1)), 0)::numeric as contract_notional,
    coalesce(sum(coalesce(used_margin, 0)), 0)::numeric as contract_used_margin,
    coalesce(sum(coalesce(maintenance_margin, 0)), 0)::numeric as contract_maintenance_margin,
    coalesce(sum(coalesce(floating_pnl, 0)), 0)::numeric as contract_unrealized,
    coalesce(
      max(nullif(margin_mode, '')) filter (where coalesce(product_type, 'spot') in ('perpetual', 'future')),
      'cross'
    ) as dominant_margin_mode,
    coalesce(
      max(leverage) filter (where coalesce(product_type, 'spot') in ('perpetual', 'future')),
      1
    )::numeric as dominant_leverage
  from public.teacher_positions
  where coalesce(is_history, false) = false
    and coalesce(product_type, 'spot') in ('perpetual', 'future')
  group by teacher_id
),
spot_orders as (
  select
    teacher_id,
    coalesce(sum(coalesce(frozen_cash, 0)), 0)::numeric as spot_cash_frozen
  from public.teacher_orders
  where status in ('pending', 'partial')
    and coalesce(product_type, 'spot') = 'spot'
  group by teacher_id
),
contract_orders as (
  select
    teacher_id,
    coalesce(sum(coalesce(frozen_cash, 0)), 0)::numeric as contract_cash_frozen
  from public.teacher_orders
  where status in ('pending', 'partial')
    and coalesce(product_type, 'spot') in ('perpetual', 'future')
  group by teacher_id
),
contract_fills as (
  select
    teacher_id,
    coalesce(sum(coalesce(realized_pnl, 0)), 0)::numeric as contract_realized_pnl
  from public.teacher_order_fills
  where coalesce(product_type, 'spot') in ('perpetual', 'future')
  group by teacher_id
),
alloc as (
  select
    acc.teacher_id,
    coalesce(acc.currency, 'USD') as currency,
    coalesce(acc.initial_cash, 1000000)::numeric as legacy_initial_cash,
    coalesce(acc.cash_available, 0)::numeric as legacy_cash_available,
    coalesce(acc.realized_pnl, 0)::numeric as legacy_realized_pnl,
    coalesce(sp.spot_market_value, 0)::numeric as spot_market_value,
    coalesce(so.spot_cash_frozen, 0)::numeric as spot_cash_frozen,
    coalesce(cp.contract_notional, 0)::numeric as contract_notional,
    coalesce(cp.contract_used_margin, 0)::numeric as contract_used_margin,
    coalesce(cp.contract_maintenance_margin, 0)::numeric as contract_maintenance_margin,
    coalesce(cp.contract_unrealized, 0)::numeric as contract_unrealized,
    coalesce(co.contract_cash_frozen, 0)::numeric as contract_cash_frozen,
    coalesce(cf.contract_realized_pnl, 0)::numeric as contract_realized_pnl,
    coalesce(cp.dominant_margin_mode, 'cross') as dominant_margin_mode,
    greatest(1, coalesce(cp.dominant_leverage, 1))::numeric as dominant_leverage,
    case
      when (
        greatest(coalesce(sp.spot_market_value, 0) + coalesce(so.spot_cash_frozen, 0), 0)
        + greatest(coalesce(cp.contract_used_margin, 0) + coalesce(co.contract_cash_frozen, 0), 0)
      ) > 0
        then greatest(coalesce(sp.spot_market_value, 0) + coalesce(so.spot_cash_frozen, 0), 0)
          / (
            greatest(coalesce(sp.spot_market_value, 0) + coalesce(so.spot_cash_frozen, 0), 0)
            + greatest(coalesce(cp.contract_used_margin, 0) + coalesce(co.contract_cash_frozen, 0), 0)
          )
      else 0.5
    end::numeric as spot_share
  from public.teacher_trading_accounts acc
  left join spot_positions sp on sp.teacher_id = acc.teacher_id
  left join contract_positions cp on cp.teacher_id = acc.teacher_id
  left join spot_orders so on so.teacher_id = acc.teacher_id
  left join contract_orders co on co.teacher_id = acc.teacher_id
  left join contract_fills cf on cf.teacher_id = acc.teacher_id
),
prepared as (
  select
    teacher_id,
    currency,
    legacy_initial_cash,
    legacy_cash_available,
    legacy_realized_pnl,
    spot_market_value,
    spot_cash_frozen,
    contract_notional,
    contract_used_margin,
    contract_maintenance_margin,
    contract_unrealized,
    contract_cash_frozen,
    contract_realized_pnl,
    dominant_margin_mode,
    dominant_leverage,
    greatest(0, least(1, spot_share))::numeric as spot_share,
    (legacy_cash_available * greatest(0, least(1, spot_share)))::numeric as spot_cash_available,
    (legacy_cash_available - (legacy_cash_available * greatest(0, least(1, spot_share))))::numeric as contract_cash_available
  from alloc
),
normalized as (
  select
    teacher_id,
    currency,
    (legacy_initial_cash * spot_share)::numeric as spot_initial_cash,
    (legacy_initial_cash - (legacy_initial_cash * spot_share))::numeric as contract_initial_cash,
    spot_cash_available,
    contract_cash_available,
    spot_cash_frozen,
    contract_cash_frozen,
    spot_market_value,
    contract_notional,
    contract_used_margin,
    contract_maintenance_margin,
    (legacy_realized_pnl - contract_realized_pnl)::numeric as spot_realized_pnl,
    contract_realized_pnl,
    contract_unrealized,
    dominant_margin_mode,
    dominant_leverage
  from prepared
)
update public.teacher_trading_accounts acc
set
  currency = n.currency,
  account_type = 'spot',
  margin_mode = 'cross',
  leverage = 1,
  initial_cash = n.spot_initial_cash,
  cash_balance = (n.spot_cash_available + n.spot_cash_frozen),
  cash_available = n.spot_cash_available,
  cash_frozen = n.spot_cash_frozen,
  market_value = n.spot_market_value,
  used_margin = 0,
  maintenance_margin = 0,
  margin_balance = (n.spot_cash_available + n.spot_cash_frozen + n.spot_market_value),
  realized_pnl = n.spot_realized_pnl,
  unrealized_pnl = 0,
  equity = (n.spot_cash_available + n.spot_cash_frozen + n.spot_market_value),
  updated_at = now()
from normalized n
where acc.teacher_id = n.teacher_id
  and acc.account_type = 'spot';

create unique index if not exists teacher_trading_accounts_teacher_account_type_uidx
  on public.teacher_trading_accounts(teacher_id, account_type);

create index if not exists teacher_trading_accounts_teacher_id_idx
  on public.teacher_trading_accounts(teacher_id);

with
spot_positions as (
  select
    teacher_id,
    coalesce(sum(coalesce(current_price, 0) * coalesce(buy_shares, 0) * coalesce(contract_size, 1) * coalesce(multiplier, 1)), 0)::numeric as spot_market_value
  from public.teacher_positions
  where coalesce(is_history, false) = false
    and coalesce(product_type, 'spot') = 'spot'
  group by teacher_id
),
contract_positions as (
  select
    teacher_id,
    coalesce(sum(coalesce(current_price, 0) * coalesce(buy_shares, 0) * coalesce(contract_size, 1) * coalesce(multiplier, 1)), 0)::numeric as contract_notional,
    coalesce(sum(coalesce(used_margin, 0)), 0)::numeric as contract_used_margin,
    coalesce(sum(coalesce(maintenance_margin, 0)), 0)::numeric as contract_maintenance_margin,
    coalesce(sum(coalesce(floating_pnl, 0)), 0)::numeric as contract_unrealized,
    coalesce(
      max(nullif(margin_mode, '')) filter (where coalesce(product_type, 'spot') in ('perpetual', 'future')),
      'cross'
    ) as dominant_margin_mode,
    coalesce(
      max(leverage) filter (where coalesce(product_type, 'spot') in ('perpetual', 'future')),
      1
    )::numeric as dominant_leverage
  from public.teacher_positions
  where coalesce(is_history, false) = false
    and coalesce(product_type, 'spot') in ('perpetual', 'future')
  group by teacher_id
),
spot_orders as (
  select
    teacher_id,
    coalesce(sum(coalesce(frozen_cash, 0)), 0)::numeric as spot_cash_frozen
  from public.teacher_orders
  where status in ('pending', 'partial')
    and coalesce(product_type, 'spot') = 'spot'
  group by teacher_id
),
contract_orders as (
  select
    teacher_id,
    coalesce(sum(coalesce(frozen_cash, 0)), 0)::numeric as contract_cash_frozen
  from public.teacher_orders
  where status in ('pending', 'partial')
    and coalesce(product_type, 'spot') in ('perpetual', 'future')
  group by teacher_id
),
contract_fills as (
  select
    teacher_id,
    coalesce(sum(coalesce(realized_pnl, 0)), 0)::numeric as contract_realized_pnl
  from public.teacher_order_fills
  where coalesce(product_type, 'spot') in ('perpetual', 'future')
  group by teacher_id
),
alloc as (
  select
    acc.teacher_id,
    coalesce(acc.currency, 'USD') as currency,
    coalesce(acc.initial_cash, 1000000)::numeric as legacy_initial_cash,
    coalesce(acc.cash_available, 0)::numeric as legacy_cash_available,
    coalesce(acc.realized_pnl, 0)::numeric as legacy_realized_pnl,
    coalesce(sp.spot_market_value, 0)::numeric as spot_market_value,
    coalesce(so.spot_cash_frozen, 0)::numeric as spot_cash_frozen,
    coalesce(cp.contract_notional, 0)::numeric as contract_notional,
    coalesce(cp.contract_used_margin, 0)::numeric as contract_used_margin,
    coalesce(cp.contract_maintenance_margin, 0)::numeric as contract_maintenance_margin,
    coalesce(cp.contract_unrealized, 0)::numeric as contract_unrealized,
    coalesce(co.contract_cash_frozen, 0)::numeric as contract_cash_frozen,
    coalesce(cf.contract_realized_pnl, 0)::numeric as contract_realized_pnl,
    coalesce(cp.dominant_margin_mode, 'cross') as dominant_margin_mode,
    greatest(1, coalesce(cp.dominant_leverage, 1))::numeric as dominant_leverage,
    case
      when (
        greatest(coalesce(sp.spot_market_value, 0) + coalesce(so.spot_cash_frozen, 0), 0)
        + greatest(coalesce(cp.contract_used_margin, 0) + coalesce(co.contract_cash_frozen, 0), 0)
      ) > 0
        then greatest(coalesce(sp.spot_market_value, 0) + coalesce(so.spot_cash_frozen, 0), 0)
          / (
            greatest(coalesce(sp.spot_market_value, 0) + coalesce(so.spot_cash_frozen, 0), 0)
            + greatest(coalesce(cp.contract_used_margin, 0) + coalesce(co.contract_cash_frozen, 0), 0)
          )
      else 0.5
    end::numeric as spot_share
  from public.teacher_trading_accounts acc
  left join spot_positions sp on sp.teacher_id = acc.teacher_id
  left join contract_positions cp on cp.teacher_id = acc.teacher_id
  left join spot_orders so on so.teacher_id = acc.teacher_id
  left join contract_orders co on co.teacher_id = acc.teacher_id
  left join contract_fills cf on cf.teacher_id = acc.teacher_id
  where acc.account_type = 'spot'
),
prepared as (
  select
    teacher_id,
    currency,
    legacy_initial_cash,
    legacy_cash_available,
    legacy_realized_pnl,
    spot_market_value,
    spot_cash_frozen,
    contract_notional,
    contract_used_margin,
    contract_maintenance_margin,
    contract_unrealized,
    contract_cash_frozen,
    contract_realized_pnl,
    dominant_margin_mode,
    dominant_leverage,
    greatest(0, least(1, spot_share))::numeric as spot_share,
    (legacy_cash_available * greatest(0, least(1, spot_share)))::numeric as spot_cash_available,
    (legacy_cash_available - (legacy_cash_available * greatest(0, least(1, spot_share))))::numeric as contract_cash_available
  from alloc
),
normalized as (
  select
    teacher_id,
    currency,
    (legacy_initial_cash * spot_share)::numeric as spot_initial_cash,
    (legacy_initial_cash - (legacy_initial_cash * spot_share))::numeric as contract_initial_cash,
    spot_cash_available,
    contract_cash_available,
    spot_cash_frozen,
    contract_cash_frozen,
    spot_market_value,
    contract_notional,
    contract_used_margin,
    contract_maintenance_margin,
    (legacy_realized_pnl - contract_realized_pnl)::numeric as spot_realized_pnl,
    contract_realized_pnl,
    contract_unrealized,
    dominant_margin_mode,
    dominant_leverage
  from prepared
)
insert into public.teacher_trading_accounts (
  id,
  teacher_id,
  currency,
  account_type,
  margin_mode,
  leverage,
  initial_cash,
  cash_balance,
  cash_available,
  cash_frozen,
  market_value,
  used_margin,
  maintenance_margin,
  margin_balance,
  realized_pnl,
  unrealized_pnl,
  equity,
  created_at,
  updated_at
)
select
  gen_random_uuid(),
  n.teacher_id,
  n.currency,
  'contract',
  n.dominant_margin_mode,
  n.dominant_leverage,
  n.contract_initial_cash,
  (n.contract_cash_available + n.contract_cash_frozen + n.contract_used_margin),
  n.contract_cash_available,
  n.contract_cash_frozen,
  n.contract_notional,
  n.contract_used_margin,
  n.contract_maintenance_margin,
  (n.contract_cash_available + n.contract_cash_frozen + n.contract_used_margin + n.contract_unrealized),
  n.contract_realized_pnl,
  n.contract_unrealized,
  (n.contract_cash_available + n.contract_cash_frozen + n.contract_used_margin + n.contract_unrealized),
  now(),
  now()
from normalized n
on conflict (teacher_id, account_type) do update
set
  currency = excluded.currency,
  margin_mode = excluded.margin_mode,
  leverage = excluded.leverage,
  initial_cash = excluded.initial_cash,
  cash_balance = excluded.cash_balance,
  cash_available = excluded.cash_available,
  cash_frozen = excluded.cash_frozen,
  market_value = excluded.market_value,
  used_margin = excluded.used_margin,
  maintenance_margin = excluded.maintenance_margin,
  margin_balance = excluded.margin_balance,
  realized_pnl = excluded.realized_pnl,
  unrealized_pnl = excluded.unrealized_pnl,
  equity = excluded.equity,
  updated_at = now();

update public.teacher_orders
set account_type = case
  when coalesce(product_type, 'spot') in ('perpetual', 'future') then 'contract'
  else 'spot'
end
where account_type is null;

update public.teacher_positions
set account_type = case
  when coalesce(product_type, 'spot') in ('perpetual', 'future') then 'contract'
  else 'spot'
end
where account_type is null;

update public.teacher_order_fills
set account_type = case
  when coalesce(product_type, 'spot') in ('perpetual', 'future') then 'contract'
  else 'spot'
end
where account_type is null;

update public.teacher_account_ledger
set account_type = case
  when coalesce(product_type, 'spot') in ('perpetual', 'future') then 'contract'
  else 'spot'
end
where account_type is null;

update public.teacher_orders o
set account_id = acc.id
from public.teacher_trading_accounts acc
where o.account_id is null
  and acc.teacher_id = o.teacher_id
  and acc.account_type = coalesce(o.account_type, case
    when coalesce(o.product_type, 'spot') in ('perpetual', 'future') then 'contract'
    else 'spot'
  end);

update public.teacher_positions p
set account_id = acc.id
from public.teacher_trading_accounts acc
where p.account_id is null
  and acc.teacher_id = p.teacher_id
  and acc.account_type = coalesce(p.account_type, case
    when coalesce(p.product_type, 'spot') in ('perpetual', 'future') then 'contract'
    else 'spot'
  end);

update public.teacher_order_fills f
set account_id = acc.id
from public.teacher_trading_accounts acc
where f.account_id is null
  and acc.teacher_id = f.teacher_id
  and acc.account_type = coalesce(f.account_type, case
    when coalesce(f.product_type, 'spot') in ('perpetual', 'future') then 'contract'
    else 'spot'
  end);

update public.teacher_account_ledger l
set account_id = acc.id
from public.teacher_trading_accounts acc
where l.account_id is null
  and acc.teacher_id = l.teacher_id
  and acc.account_type = coalesce(l.account_type, case
    when coalesce(l.product_type, 'spot') in ('perpetual', 'future') then 'contract'
    else 'spot'
  end);

create index if not exists teacher_orders_account_idx
  on public.teacher_orders(account_id, created_at desc);

create index if not exists teacher_positions_account_idx
  on public.teacher_positions(account_id, is_history, created_at desc);

create index if not exists teacher_order_fills_account_idx
  on public.teacher_order_fills(account_id, fill_time desc);

create index if not exists teacher_account_ledger_account_idx
  on public.teacher_account_ledger(account_id, created_at desc);

-- Validation examples after running the migration:
-- 1) Each teacher should have exactly two rows:
--    select teacher_id, count(*) from public.teacher_trading_accounts group by teacher_id having count(*) <> 2;
-- 2) Split equity should reconcile to the legacy total:
--    select teacher_id, sum(equity) from public.teacher_trading_accounts group by teacher_id;
