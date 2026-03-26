-- 用户交易中心菜单相关配置
-- user_trading_center_min_version: 最低版本号（如 1.0.0），该版本及以上显示菜单；留空则隐藏
-- webview_user_page_url: 用户交易中心 WebView 页面 URL，不填则用 .env 的 WEBVIEW_USER_PAGE_URL

insert into public.app_config (key, value, remark) values
  ('user_trading_center_min_version', '0.1.0', '用户交易中心菜单最低版本号，该版本及以上显示；留空则隐藏')
on conflict (key) do update set remark = excluded.remark;

insert into public.app_config (key, value, remark) values
  ('webview_user_page_url', '', '用户交易中心 WebView 页面 URL，不填则用 .env 的 WEBVIEW_USER_PAGE_URL')
on conflict (key) do update set remark = excluded.remark;
