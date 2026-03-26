-- 钱包 RLS：用户只能看自己的钱包和流水
-- 使用 auth.jwt()->>'sub' 兼容 Firebase UID（非 UUID），避免 "invalid input syntax for type uuid"。
-- 在 Supabase SQL Editor 中执行（可重复执行：先删后建）

alter table public.user_wallets enable row level security;
alter table public.wallet_transactions enable row level security;

-- 先删除再创建，避免 "policy already exists" 报错
drop policy if exists "user_wallets_select_own" on public.user_wallets;
drop policy if exists "user_wallets_update_own" on public.user_wallets;
drop policy if exists "user_wallets_insert_own" on public.user_wallets;
drop policy if exists "wallet_transactions_select_own" on public.wallet_transactions;

-- 用 JWT 的 sub 与 user_id 比较，不调用 auth.uid()，避免 Firebase UID 被当 UUID 解析报错
create policy "user_wallets_select_own"
  on public.user_wallets for select
  using ((auth.jwt()->>'sub') = user_id);

create policy "user_wallets_update_own"
  on public.user_wallets for update
  using ((auth.jwt()->>'sub') = user_id);

create policy "user_wallets_insert_own"
  on public.user_wallets for insert
  with check ((auth.jwt()->>'sub') = user_id and balance_usdt = 0);

create policy "wallet_transactions_select_own"
  on public.wallet_transactions for select
  using ((auth.jwt()->>'sub') = user_id);

-- 流水插入由 transfer_usdt 等 service/definer 完成，不开放给 anon
-- 若需后台写入流水，使用 service_role 或 definer 函数

-- 授予已认证用户
grant select, update on public.user_wallets to authenticated;
grant insert on public.user_wallets to authenticated;
grant select on public.wallet_transactions to authenticated;
grant execute on function public.transfer_usdt(text,text,numeric) to authenticated;
