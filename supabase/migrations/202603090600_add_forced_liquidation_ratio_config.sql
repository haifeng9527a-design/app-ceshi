-- Trading risk config: forced liquidation risk ratio.
-- 强制平仓风险比例（maintenance_margin / margin_balance）阈值，默认 0.95。

insert into public.app_config (key, value, remark)
values (
  'trading_forced_liquidation_ratio',
  '0.95',
  '强制平仓风险比例阈值，risk_ratio >= 该值触发强平'
)
on conflict (key) do update
set value = excluded.value,
    remark = excluded.remark,
    updated_at = now();
