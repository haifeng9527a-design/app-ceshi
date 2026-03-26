-- 用户交易中心：隐藏时的显示配置（名称、备注、链接地址）
-- 非隐藏时使用 user_trading_center_menu_title / user_trading_center_menu_subtitle

insert into public.app_config (key, value, remark) values
  ('user_trading_center_hidden_menu_title', '用户交易中心', '版本在隐藏列表中时显示的名称')
on conflict (key) do update set remark = excluded.remark;

insert into public.app_config (key, value, remark) values
  ('user_trading_center_hidden_menu_subtitle', '当前版本暂不支持，请访问下方链接', '版本在隐藏列表中时显示的备注')
on conflict (key) do update set remark = excluded.remark;
