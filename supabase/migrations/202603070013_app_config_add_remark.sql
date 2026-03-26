-- app_config 增加备注栏，便于使用者了解每个参数的用途

alter table public.app_config add column if not exists remark text;

comment on column public.app_config.remark is '参数说明，便于管理时了解用途';

-- 为已有配置补充默认备注
update public.app_config set remark = '系统客服账号（用户添加的好友、消息接收方），需先在 Firebase 注册并同步到 user_profiles' where key = 'customer_service_user_id' and (remark is null or remark = '');
update public.app_config set remark = '客服固定头像 URL，不填则用 user_profiles.avatar_url' where key = 'customer_service_avatar_url' and (remark is null or remark = '');
update public.app_config set remark = '客服欢迎语，用户首次添加客服好友时显示' where key = 'customer_service_welcome_message' and (remark is null or remark = '');
update public.app_config set remark = '交易模拟盘默认初始资金（USD）' where key = 'trading_default_initial_cash_usd' and (remark is null or remark = '');
update public.app_config set remark = '默认产品类型：spot | perpetual | future' where key = 'trading_default_product_type' and (remark is null or remark = '');
update public.app_config set remark = '默认保证金模式：cross | isolated' where key = 'trading_default_margin_mode' and (remark is null or remark = '');
update public.app_config set remark = '默认杠杆倍数' where key = 'trading_default_leverage' and (remark is null or remark = '');
update public.app_config set remark = '最大杠杆倍数' where key = 'trading_max_leverage' and (remark is null or remark = '');
update public.app_config set remark = '是否允许做空：true | false' where key = 'trading_allow_short' and (remark is null or remark = '');
update public.app_config set remark = '维持保证金率，如 0.005 表示 0.5%' where key = 'trading_maintenance_margin_rate' and (remark is null or remark = '');
