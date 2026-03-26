-- 删除「林然」全部数据（该用户不存在，清理测试/脏数据）
-- 在 Supabase SQL Editor 中执行。按依赖顺序先删子表，再删 teacher_profiles / user_profiles。

do $$
declare
  v_uid text;
begin
  for v_uid in
    select user_id
    from public.teacher_profiles
    where display_name = '林然' or real_name = '林然'
  loop
    -- 1) 交易记录相关
    delete from public.trade_record_files where teacher_id = v_uid;
    delete from public.trade_records where teacher_id = v_uid;

    -- 2) 策略、持仓、评论、文章、日程等
    delete from public.teacher_positions where teacher_id = v_uid;
    delete from public.teacher_comments where teacher_id = v_uid;
    delete from public.teacher_articles where teacher_id = v_uid;
    delete from public.teacher_schedules where teacher_id = v_uid;
    delete from public.trade_strategies where teacher_id = v_uid;

    -- 3) 关注关系（谁关注了林然 + 林然关注了谁）
    delete from public.teacher_follows where teacher_id = v_uid or user_id = v_uid;

    -- 4) 交易员统计（若存在该表）
    if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'teacher_stats') then
      delete from public.teacher_stats where user_id = v_uid;
    end if;

    -- 5) 交易员档案
    delete from public.teacher_profiles where user_id = v_uid;

    -- 6) 若 user_profiles 里也有该用户（同一 user_id），一并删除
    delete from public.user_profiles where user_id = v_uid;
  end loop;
end $$;
