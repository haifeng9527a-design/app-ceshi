/**
 * 活动管理 API（基于 app_config 存储）
 * - GET    /api/admin/activities
 * - POST   /api/admin/activities
 * - PATCH  /api/admin/activities/:id
 * - PATCH  /api/admin/activities/:id/status
 * - DELETE /api/admin/activities/:id
 */
const supabaseClient = require('./supabaseClient');
const { requireAdminSession } = require('./adminSession');

const CONFIG_KEY = 'admin_activities';

function toIsoOrNull(value) {
  const text = value == null ? '' : String(value).trim();
  if (!text) return null;
  const t = Date.parse(text);
  if (Number.isNaN(t)) return null;
  return new Date(t).toISOString();
}

function normalizeStatus(raw) {
  const v = String(raw || '').trim().toLowerCase();
  if (v === 'online' || v === 'offline' || v === 'draft') return v;
  return 'draft';
}

function normalizeActivity(input, nowIso) {
  const id = String(input?.id || '').trim();
  const title = String(input?.title || '').trim();
  const summary = String(input?.summary || '').trim();
  const detail = String(input?.detail || '').trim();
  const rewardRule = String(input?.rewardRule || '').trim();
  const bannerUrl = String(input?.bannerUrl || '').trim();
  const sort = Number.isFinite(Number(input?.sort)) ? Number(input.sort) : 0;
  const status = normalizeStatus(input?.status);
  const startAt = toIsoOrNull(input?.startAt);
  const endAt = toIsoOrNull(input?.endAt);
  const createdAt = toIsoOrNull(input?.createdAt) || nowIso;
  const updatedAt = nowIso;
  return {
    id,
    title,
    summary,
    detail,
    rewardRule,
    bannerUrl,
    sort,
    status,
    startAt,
    endAt,
    createdAt,
    updatedAt,
  };
}

function sortActivities(list) {
  return [...list].sort((a, b) => {
    const sortDiff = (Number(a.sort) || 0) - (Number(b.sort) || 0);
    if (sortDiff !== 0) return sortDiff;
    return String(b.updatedAt || '').localeCompare(String(a.updatedAt || ''));
  });
}

async function readActivities(sb) {
  const { data, error } = await sb
    .from('app_config')
    .select('value')
    .eq('key', CONFIG_KEY)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!data || data.value == null || String(data.value).trim() === '') return [];
  try {
    const parsed = JSON.parse(String(data.value));
    if (!Array.isArray(parsed)) return [];
    const nowIso = new Date().toISOString();
    return parsed
      .map((it) => normalizeActivity(it, nowIso))
      .filter((it) => it.id && it.title);
  } catch (_) {
    return [];
  }
}

async function writeActivities(sb, list) {
  const nowIso = new Date().toISOString();
  const normalized = sortActivities(
    list.map((it) => normalizeActivity(it, toIsoOrNull(it.updatedAt) || nowIso)),
  );
  const { error } = await sb
    .from('app_config')
    .upsert(
      {
        key: CONFIG_KEY,
        value: JSON.stringify(normalized),
        remark: '活动管理配置(JSON)',
        updated_at: nowIso,
      },
      { onConflict: 'key' },
    );
  if (error) throw new Error(error.message);
  return normalized;
}

function registerAdminActivityRoutes(app) {
  app.get('/api/admin/activities', requireAdminSession, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    try {
      const list = await readActivities(sb);
      return res.json(sortActivities(list));
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.post('/api/admin/activities', requireAdminSession, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    const nowIso = new Date().toISOString();
    const title = String(req.body?.title || '').trim();
    if (!title) return res.status(400).json({ error: 'title 不能为空' });
    try {
      const list = await readActivities(sb);
      const id = String(req.body?.id || `act_${Date.now()}`).trim();
      if (list.some((it) => it.id === id)) {
        return res.status(409).json({ error: '活动ID已存在' });
      }
      const next = normalizeActivity(
        {
          id,
          title,
          summary: req.body?.summary,
          detail: req.body?.detail,
          rewardRule: req.body?.rewardRule,
          bannerUrl: req.body?.bannerUrl,
          sort: req.body?.sort,
          status: req.body?.status,
          startAt: req.body?.startAt,
          endAt: req.body?.endAt,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
        nowIso,
      );
      const saved = await writeActivities(sb, [...list, next]);
      return res.status(201).json(saved.find((it) => it.id === id) || next);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.patch('/api/admin/activities/:id', requireAdminSession, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'id 不能为空' });
    try {
      const list = await readActivities(sb);
      const index = list.findIndex((it) => it.id === id);
      if (index < 0) return res.status(404).json({ error: '活动不存在' });
      const merged = {
        ...list[index],
        ...req.body,
        id,
        updatedAt: new Date().toISOString(),
      };
      if (!String(merged.title || '').trim()) {
        return res.status(400).json({ error: 'title 不能为空' });
      }
      const nextItem = normalizeActivity(merged, new Date().toISOString());
      const nextList = [...list];
      nextList[index] = nextItem;
      const saved = await writeActivities(sb, nextList);
      return res.json(saved.find((it) => it.id === id) || nextItem);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.patch('/api/admin/activities/:id/status', requireAdminSession, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'id 不能为空' });
    const status = normalizeStatus(req.body?.status);
    try {
      const list = await readActivities(sb);
      const index = list.findIndex((it) => it.id === id);
      if (index < 0) return res.status(404).json({ error: '活动不存在' });
      const nextList = [...list];
      nextList[index] = {
        ...nextList[index],
        status,
        updatedAt: new Date().toISOString(),
      };
      const saved = await writeActivities(sb, nextList);
      return res.json(saved.find((it) => it.id === id) || nextList[index]);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.delete('/api/admin/activities/:id', requireAdminSession, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'id 不能为空' });
    try {
      const list = await readActivities(sb);
      const nextList = list.filter((it) => it.id !== id);
      if (nextList.length === list.length) {
        return res.status(404).json({ error: '活动不存在' });
      }
      await writeActivities(sb, nextList);
      return res.status(204).send();
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerAdminActivityRoutes };
