-- 用户交易中心菜单的名称和备注，可在 app_config 中配置

insert into public.app_config (key, value, remark) values
  ('user_trading_center_menu_title', '用户交易中心', '用户交易中心菜单标题')
on conflict (key) do update set remark = excluded.remark;

insert into public.app_config (key, value, remark) values
  ('user_trading_center_menu_subtitle', '通过 WebView 打开用户交易中心', '用户交易中心菜单备注/副标题')
on conflict (key) do update set remark = excluded.remark;
