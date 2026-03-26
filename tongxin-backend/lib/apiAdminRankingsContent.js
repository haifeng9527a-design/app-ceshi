const supabaseClient = require('./supabaseClient');
const { requireAdminSession } = require('./adminSession');

const TABLE = 'rankings_carousel_content';

function normalizeCard(raw, index = 0) {
  const incomingKey = String(raw?.card_key || raw?.cardKey || '').trim().toLowerCase();
  const safeKey = incomingKey.replace(/[^a-z0-9_-]/g, '');
  const cardKey = safeKey || `card_${Date.now()}_${index + 1}`;
  return {
    card_key: cardKey,
    title: String(raw?.title || '').trim(),
    summary: String(raw?.summary || '').trim(),
    detail: String(raw?.detail || '').trim(),
    extra_link: raw?.extra_link == null ? null : String(raw.extra_link).trim() || null,
    sort_order: Number.isFinite(Number(raw?.sort_order ?? raw?.sortOrder))
      ? Number(raw?.sort_order ?? raw?.sortOrder)
      : (index + 1),
    updated_at: new Date().toISOString(),
  };
}

async function readCards(sb) {
  const { data, error } = await sb
    .from(TABLE)
    .select('card_key, title, summary, detail, extra_link, sort_order, updated_at')
    .order('sort_order', { ascending: true });
  if (error) {
    if (String(error.message || '').includes(TABLE)) {
      return readLegacyCardsFromAppConfig(sb);
    }
    throw new Error(error.message);
  }
  return (data || []).map((row) => normalizeCard(row)).filter(Boolean);
}

async function readLegacyCardsFromAppConfig(sb) {
  const keys = [
    'rankings_intro_title',
    'rankings_intro_summary',
    'rankings_intro_detail',
    'rankings_signup_title',
    'rankings_signup_summary',
    'rankings_signup_detail',
    'rankings_signup_entry_url',
    'rankings_activity_title',
    'rankings_activity_summary',
    'rankings_activity_detail',
  ];
  const { data, error } = await sb.from('app_config').select('key, value').in('key', keys);
  if (error) throw new Error(error.message);
  const map = {};
  for (const row of data || []) {
    map[row.key] = row.value != null ? String(row.value) : '';
  }
  const nowIso = new Date().toISOString();
  return [
    normalizeCard({
      card_key: 'intro',
      title: map.rankings_intro_title || '排行榜简介',
      summary:
        map.rankings_intro_summary ||
        '榜单基于导师收益与稳定性综合展示，帮助学员快速发现值得长期跟踪的导师。',
      detail:
        map.rankings_intro_detail ||
        '排行榜按不同周期展示导师表现。你可以查看周榜、月榜、季度榜、年度榜和总榜，结合胜率与盈亏趋势，评估导师风格是否与你匹配。',
      sort_order: 1,
      updated_at: nowIso,
    }),
    normalizeCard({
      card_key: 'signup',
      title: map.rankings_signup_title || '报名须知与入口',
      summary:
        map.rankings_signup_summary ||
        '参与导师评选或活动报名前，请先阅读规则说明与资格要求。',
      detail:
        map.rankings_signup_detail ||
        '报名须知：\n1. 需完成实名认证；\n2. 近30天有有效交易记录；\n3. 严禁刷单或虚假收益展示。\n\n通过入口链接提交报名信息，审核结果将在1-3个工作日内反馈。',
      extra_link: map.rankings_signup_entry_url || 'https://example.com/rankings-signup',
      sort_order: 2,
      updated_at: nowIso,
    }),
    normalizeCard({
      card_key: 'activity',
      title: map.rankings_activity_title || '最新活动介绍',
      summary:
        map.rankings_activity_summary ||
        '本月导师挑战赛进行中，完成阶段目标可获得曝光位与奖励。',
      detail:
        map.rankings_activity_detail ||
        '活动时间：每月1日-25日\n活动内容：按收益稳定性、回撤控制和互动质量综合评定。\n奖励说明：Top榜单导师将获得首页推荐位和官方流量支持。',
      sort_order: 3,
      updated_at: nowIso,
    }),
  ].filter(Boolean);
}

async function writeLegacyAppConfig(sb, cards) {
  const byKey = Object.fromEntries(cards.map((c) => [c.card_key, c]));
  const intro = byKey.intro || {};
  const signup = byKey.signup || {};
  const activity = byKey.activity || {};
  const rows = [
    { key: 'rankings_intro_title', value: intro.title || '', remark: '排行榜介绍模块标题' },
    { key: 'rankings_intro_summary', value: intro.summary || '', remark: '排行榜介绍模块摘要' },
    { key: 'rankings_intro_detail', value: intro.detail || '', remark: '排行榜介绍弹窗详情' },
    { key: 'rankings_signup_title', value: signup.title || '', remark: '报名模块标题' },
    { key: 'rankings_signup_summary', value: signup.summary || '', remark: '报名模块摘要' },
    { key: 'rankings_signup_detail', value: signup.detail || '', remark: '报名弹窗详情' },
    { key: 'rankings_signup_entry_url', value: signup.extra_link || '', remark: '报名入口链接' },
    { key: 'rankings_activity_title', value: activity.title || '', remark: '排行榜活动模块标题' },
    { key: 'rankings_activity_summary', value: activity.summary || '', remark: '排行榜活动模块摘要' },
    { key: 'rankings_activity_detail', value: activity.detail || '', remark: '排行榜活动模块详情' },
  ].map((r) => ({ ...r, updated_at: new Date().toISOString() }));
  const { error } = await sb.from('app_config').upsert(rows, { onConflict: 'key' });
  if (error) throw new Error(error.message);
}

function toAppConfigShape(cards) {
  const sorted = [...cards].sort((a, b) => Number(a.sort_order || 0) - Number(b.sort_order || 0));
  const intro = sorted[0] || {};
  const signup = sorted[1] || {};
  const activity = sorted[2] || {};
  return {
    rankings_intro_title: intro.title || null,
    rankings_intro_summary: intro.summary || null,
    rankings_intro_detail: intro.detail || null,
    rankings_signup_title: signup.title || null,
    rankings_signup_summary: signup.summary || null,
    rankings_signup_detail: signup.detail || null,
    rankings_signup_entry_url: signup.extra_link || null,
    rankings_activity_title: activity.title || null,
    rankings_activity_summary: activity.summary || null,
    rankings_activity_detail: activity.detail || null,
  };
}

async function fetchRankingsContentForApp(sb) {
  const cards = await readCards(sb);
  return { cards, config: toAppConfigShape(cards) };
}

function registerAdminRankingsContentRoutes(app) {
  app.get('/api/admin/rankings/content', requireAdminSession, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    try {
      const cards = await readCards(sb);
      return res.json({ cards });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.put('/api/admin/rankings/content', requireAdminSession, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    const incoming = Array.isArray(req.body?.cards) ? req.body.cards : null;
    if (!incoming || incoming.length === 0) {
      return res.status(400).json({ error: 'cards 不能为空' });
    }

    const normalized = incoming.map((item, idx) => normalizeCard(item, idx)).filter(Boolean);
    const keys = new Set(normalized.map((c) => c.card_key));
    if (normalized.length !== incoming.length || keys.size !== normalized.length) {
      return res.status(400).json({ error: 'cards 数据非法或 card_key 重复' });
    }
    for (const card of normalized) {
      if (!card.title || !card.summary || !card.detail) {
        return res.status(400).json({ error: `卡片 ${card.card_key} 标题/摘要/详情不能为空` });
      }
    }
    try {
      const { error } = await sb.from(TABLE).upsert(normalized, { onConflict: 'card_key' });
      if (error) {
        if (String(error.message || '').includes(TABLE)) {
          await writeLegacyAppConfig(sb, normalized);
        } else {
          return res.status(502).json({ error: error.message });
        }
      } else {
        const { data: currentRows, error: listErr } = await sb.from(TABLE).select('card_key');
        if (listErr) return res.status(502).json({ error: listErr.message });
        const incomingKeys = new Set(normalized.map((c) => c.card_key));
        const keysToDelete = (currentRows || [])
          .map((r) => String(r.card_key || '').trim())
          .filter((k) => k && !incomingKeys.has(k));
        if (keysToDelete.length > 0) {
          const { error: delErr } = await sb.from(TABLE).delete().in('card_key', keysToDelete);
          if (delErr) return res.status(502).json({ error: delErr.message });
        }
      }
      const cards = await readCards(sb);
      return res.json({ ok: true, cards });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/rankings/content', async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    try {
      const data = await fetchRankingsContentForApp(sb);
      return res.json(data);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = {
  registerAdminRankingsContentRoutes,
  fetchRankingsContentForApp,
};
