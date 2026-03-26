-- 排行榜页文案配置（可在后台“应用配置”中编辑）
insert into public.app_config (key, value, remark, updated_at)
values
  (
    'rankings_intro_title',
    '排行榜简介',
    '排行榜介绍模块标题',
    now()
  ),
  (
    'rankings_intro_summary',
    '榜单基于导师收益与稳定性综合展示，帮助学员快速发现值得长期跟踪的导师。',
    '排行榜介绍模块摘要',
    now()
  ),
  (
    'rankings_intro_detail',
    E'排行榜按不同周期展示导师表现。你可以查看周榜、月榜、季度榜、年度榜和总榜，结合胜率与盈亏趋势，评估导师风格是否与你匹配。',
    '排行榜介绍弹窗详情',
    now()
  ),
  (
    'rankings_signup_title',
    '报名须知与入口',
    '报名模块标题',
    now()
  ),
  (
    'rankings_signup_summary',
    '参与导师评选或活动报名前，请先阅读规则说明与资格要求。',
    '报名模块摘要',
    now()
  ),
  (
    'rankings_signup_detail',
    E'报名须知：\n1. 需完成实名认证；\n2. 近30天有有效交易记录；\n3. 严禁刷单或虚假收益展示。\n\n通过入口链接提交报名信息，审核结果将在1-3个工作日内反馈。',
    '报名弹窗详情',
    now()
  ),
  (
    'rankings_signup_entry_url',
    'https://example.com/rankings-signup',
    '报名入口链接',
    now()
  ),
  (
    'rankings_activity_title',
    '最新活动介绍',
    '活动模块标题',
    now()
  ),
  (
    'rankings_activity_summary',
    '本月导师挑战赛进行中，完成阶段目标可获得曝光位与奖励。',
    '活动模块摘要',
    now()
  ),
  (
    'rankings_activity_detail',
    E'活动时间：每月1日-25日\n活动内容：按收益稳定性、回撤控制和互动质量综合评定。\n奖励说明：Top榜单导师将获得首页推荐位和官方流量支持。',
    '活动弹窗详情',
    now()
  )
on conflict (key) do update set
  value = excluded.value,
  remark = excluded.remark,
  updated_at = now();
