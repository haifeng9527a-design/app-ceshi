-- 最后上线时间：用户退出 APP（后台/关闭应用/关闭聊天窗口）时更新，好友可在聊天窗口看到
-- 在 Supabase SQL Editor 执行

alter table user_profiles
  add column if not exists last_online_at timestamptz;

comment on column user_profiles.last_online_at is '最后上线时间：用户切到后台、关闭应用或离开聊天时更新';

-- RLS：用户只能更新自己的 last_online_at（若已启用 RLS，需有 update 策略允许更新本行）
-- 好友可读：通过现有 friends + user_profiles 查询，若已有「可读好友资料」策略则无需改
