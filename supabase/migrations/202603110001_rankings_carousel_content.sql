create table if not exists public.rankings_carousel_content (
  card_key text primary key,
  title text not null default '',
  summary text not null default '',
  detail text not null default '',
  extra_link text null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rankings_carousel_content_card_key_check check (
    card_key in ('intro', 'signup', 'activity')
  )
);

insert into public.rankings_carousel_content (card_key, title, summary, detail, extra_link, sort_order, updated_at)
values
  (
    'intro',
    coalesce((select value from public.app_config where key = 'rankings_intro_title'), '排行榜简介'),
    coalesce((select value from public.app_config where key = 'rankings_intro_summary'), '榜单基于导师收益与稳定性综合展示，帮助学员快速发现值得长期跟踪的导师。'),
    coalesce((select value from public.app_config where key = 'rankings_intro_detail'), '排行榜按不同周期展示导师表现。你可以查看周榜、月榜、季度榜、年度榜和总榜，结合胜率与盈亏趋势，评估导师风格是否与你匹配。'),
    null,
    1,
    now()
  ),
  (
    'signup',
    coalesce((select value from public.app_config where key = 'rankings_signup_title'), '报名须知与入口'),
    coalesce((select value from public.app_config where key = 'rankings_signup_summary'), '参与导师评选或活动报名前，请先阅读规则说明与资格要求。'),
    coalesce((select value from public.app_config where key = 'rankings_signup_detail'), E'报名须知：\n1. 需完成实名认证；\n2. 近30天有有效交易记录；\n3. 严禁刷单或虚假收益展示。\n\n通过入口链接提交报名信息，审核结果将在1-3个工作日内反馈。'),
    (select value from public.app_config where key = 'rankings_signup_entry_url'),
    2,
    now()
  ),
  (
    'activity',
    coalesce((select value from public.app_config where key = 'rankings_activity_title'), '最新活动介绍'),
    coalesce((select value from public.app_config where key = 'rankings_activity_summary'), '本月导师挑战赛进行中，完成阶段目标可获得曝光位与奖励。'),
    coalesce((select value from public.app_config where key = 'rankings_activity_detail'), E'活动时间：每月1日-25日\n活动内容：按收益稳定性、回撤控制和互动质量综合评定。\n奖励说明：Top榜单导师将获得首页推荐位和官方流量支持。'),
    null,
    3,
    now()
  )
on conflict (card_key) do update set
  title = excluded.title,
  summary = excluded.summary,
  detail = excluded.detail,
  extra_link = excluded.extra_link,
  sort_order = excluded.sort_order,
  updated_at = now();
