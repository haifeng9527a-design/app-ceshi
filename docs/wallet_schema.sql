-- 托管 USDT 钱包（方案 B）
-- 在 Supabase SQL Editor 中执行

-- 用户钱包：每人一条，余额 + 充值备注（充值到平台地址时带 memo 区分用户）
-- user_id 与 Firebase UID 一致，使用 text
create table if not exists public.user_wallets (
  user_id text primary key,
  balance_usdt numeric not null default 0 check (balance_usdt >= 0),
  deposit_memo text unique not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.user_wallets.deposit_memo is '充值备注：用户充值时必须填写，用于入账到对应用户';

-- 钱包流水
create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  type text not null check (type in ('deposit','transfer_in','transfer_out','withdraw')),
  amount numeric not null check (amount > 0),
  balance_after numeric,
  counterparty_user_id text,
  external_address text,
  tx_hash text,
  memo text,
  created_at timestamptz not null default now()
);

create index if not exists wallet_transactions_user_id_idx on public.wallet_transactions(user_id);
create index if not exists wallet_transactions_created_at_idx on public.wallet_transactions(created_at desc);

-- 用户注册时自动创建钱包（deposit_memo 用 short_id 或 user_id 的短码）
-- 需在 app 或 edge function 中：insert into user_wallets (user_id, deposit_memo) values (new_user_id, ...) on signup

-- 原子转账：扣转出方、加转入方、写两条流水（由 RPC 调用）
create or replace function public.transfer_usdt(
  p_from_user_id text,
  p_to_user_id text,
  p_amount numeric
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from_balance numeric;
  v_to_balance numeric;
begin
  if p_amount is null or p_amount <= 0 then
    return json_build_object('ok', false, 'error', 'invalid_amount');
  end if;
  if p_from_user_id is null or p_to_user_id is null or p_from_user_id = '' or p_to_user_id = '' then
    return json_build_object('ok', false, 'error', 'invalid_user');
  end if;
  if p_from_user_id = p_to_user_id then
    return json_build_object('ok', false, 'error', 'cannot_transfer_to_self');
  end if;

  select balance_usdt into v_from_balance from user_wallets where user_id = p_from_user_id for update;
  if not found or v_from_balance is null then
    return json_build_object('ok', false, 'error', 'wallet_not_found');
  end if;
  if v_from_balance < p_amount then
    return json_build_object('ok', false, 'error', 'insufficient_balance');
  end if;

  if not exists (select 1 from user_wallets where user_id = p_to_user_id) then
    return json_build_object('ok', false, 'error', 'receiver_wallet_not_found');
  end if;

  update user_wallets set balance_usdt = balance_usdt - p_amount, updated_at = now() where user_id = p_from_user_id;
  update user_wallets set balance_usdt = balance_usdt + p_amount, updated_at = now() where user_id = p_to_user_id;

  select balance_usdt into v_from_balance from user_wallets where user_id = p_from_user_id;
  select balance_usdt into v_to_balance from user_wallets where user_id = p_to_user_id;

  insert into wallet_transactions (user_id, type, amount, balance_after, counterparty_user_id)
  values (p_from_user_id, 'transfer_out', p_amount, v_from_balance, p_to_user_id);
  insert into wallet_transactions (user_id, type, amount, balance_after, counterparty_user_id)
  values (p_to_user_id, 'transfer_in', p_amount, v_to_balance, p_from_user_id);

  return json_build_object('ok', true);
end;
$$;
