-- 清空交易相关数据，用于完整测试（买入 -> 委托 -> 成交 -> 持仓）
-- 在 Supabase SQL Editor 中执行
-- 注意：将 YOUR_FIREBASE_UID 替换为你的 Firebase 用户 ID（可在 App 登录后从 Firebase Auth 获取，或从 teacher_profiles.user_id 查）

-- 方式一：清空指定用户的数据（推荐，替换下面的 UID）
-- delete from public.teacher_orders where teacher_id = 'YOUR_FIREBASE_UID';
-- delete from public.teacher_positions where teacher_id = 'YOUR_FIREBASE_UID';

-- 方式二：清空所有用户的交易数据（仅测试环境使用）
delete from public.teacher_orders;
delete from public.teacher_positions;
