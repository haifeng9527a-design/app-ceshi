-- 用户交易中心菜单：改为「隐藏版本号」模式
-- user_trading_center_hidden_versions: 逗号分隔的版本号列表，这些版本不显示菜单；其他版本显示
-- 示例：0.1.0,0.1.1,1.0.0 表示这三个版本隐藏菜单

insert into public.app_config (key, value, remark) values
  ('user_trading_center_hidden_versions', '', '逗号分隔的版本号，这些版本不显示用户交易中心菜单；留空则全部显示')
on conflict (key) do update set remark = excluded.remark;

-- 移除旧参数（若存在）
delete from public.app_config where key = 'user_trading_center_min_version';
