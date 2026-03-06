/**
 * 用户相关 API：/api/auth/profile/sync、/api/users/me
 * 由 backend 代理 Supabase user_profiles，避免前端直连
 */
const supabaseClient = require('./supabaseClient');

async function isAdminUser(sb, uid) {
  const { data, error } = await sb.from('user_profiles').select('role').eq('user_id', uid).maybeSingle();
  if (error) throw new Error(error.message);
  const role = String(data?.role || '').toLowerCase();
  return role === 'admin' || role === 'customer_service_admin';
}

async function ensureAdmin(req, res, sb) {
  if (req.isAdminByKey === true) return true;
  const uid = req.firebaseUid;
  if (!uid) {
    res.status(401).json({ error: '未鉴权' });
    return false;
  }
  const admin = await isAdminUser(sb, uid);
  if (!admin) {
    res.status(403).json({ error: 'forbidden' });
    return false;
  }
  return true;
}

function registerUserRoutes(app, requireAuth) {
  const supabase = () => supabaseClient.getClient();
  if (!supabase()) {
    console.warn('[apiUsers] Supabase 未配置，用户接口不可用');
    return;
  }

  /** POST /api/auth/profile/sync — 登录后同步 Firebase 用户到 user_profiles */
  app.post('/api/auth/profile/sync', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { display_name, email, avatar_url } = req.body || {};
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const data = {
        user_id: uid,
        display_name: display_name || null,
        email: email || null,
        avatar_url: avatar_url || null,
        updated_at: new Date().toISOString(),
      };
      const { error } = await sb.from('user_profiles').upsert(data, { onConflict: 'user_id' });
      if (error) return res.status(502).json({ error: error.message });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/users/me — 当前用户 profile */
  app.get('/api/users/me', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('user_profiles').select('*').eq('user_id', uid).maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || {});
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/users/me — 更新当前用户 profile */
  app.patch('/api/users/me', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const body = req.body || {};
    const allowed = ['display_name', 'email', 'avatar_url', 'short_id', 'signature', 'updated_at'];
    const updates = {};
    for (const k of allowed) {
      if (body[k] !== undefined) updates[k] = body[k];
    }
    if (Object.keys(updates).length === 0) return res.status(400).json({ error: '无有效字段' });
    updates.updated_at = new Date().toISOString();
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { error } = await sb.from('user_profiles').update(updates).eq('user_id', uid);
      if (error) return res.status(502).json({ error: error.message });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/users/:userId/profile — 获取指定用户 profile（含 teacher_status） */
  app.get('/api/users/:userId/profile', requireAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: up, error: upErr } = await sb.from('user_profiles').select('*').eq('user_id', userId).maybeSingle();
      if (upErr) return res.status(502).json({ error: upErr.message });
      if (!up) return res.json(null);
      const { data: tp } = await sb.from('teacher_profiles').select('status').eq('user_id', userId).maybeSingle();
      const out = { ...up };
      if (tp?.status) out.teacher_status = tp.status;
      res.json(out);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/users/:userId/role — 设置用户角色（管理员） */
  app.patch('/api/users/:userId/role', requireAuth, async (req, res) => {
    const { userId } = req.params;
    const { role } = req.body || {};
    if (!userId || !role) return res.status(400).json({ error: 'missing userId or role' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      if (!(await ensureAdmin(req, res, sb))) return;
      const { error } = await sb.from('user_profiles').update({ role, updated_at: new Date().toISOString() }).eq('user_id', userId);
      if (error) return res.status(502).json({ error: error.message });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/admin/users/basic — 管理后台基础用户列表 */
  app.get('/api/admin/users/basic', requireAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      if (!(await ensureAdmin(req, res, sb))) return;
      const { data, error } = await sb
        .from('user_profiles')
        .select('user_id, display_name, email, short_id, avatar_url, role')
        .order('display_name', { ascending: true });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/admin/users/detailed — 管理后台用户详情列表（含限制字段） */
  app.get('/api/admin/users/detailed', requireAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      if (!(await ensureAdmin(req, res, sb))) return;
      const { data, error } = await sb
        .from('user_profiles')
        .select(
          'user_id, display_name, avatar_url, role, email, signature, short_id, banned_until, frozen_until, restrict_login, restrict_send_message, restrict_add_friend, restrict_join_group, restrict_create_group'
        )
        .order('display_name', { ascending: true });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/admin/users/:userId/restrictions — 管理后台更新限制字段 */
  app.patch('/api/admin/users/:userId/restrictions', requireAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      if (!(await ensureAdmin(req, res, sb))) return;
      const body = req.body || {};
      const allowed = [
        'banned_until',
        'frozen_until',
        'restrict_login',
        'restrict_send_message',
        'restrict_add_friend',
        'restrict_join_group',
        'restrict_create_group',
      ];
      const updates = {};
      for (const k of allowed) {
        if (body[k] !== undefined) updates[k] = body[k];
      }
      if (Object.keys(updates).length === 0) {
        return res.status(400).json({ error: 'no valid fields' });
      }
      updates.updated_at = new Date().toISOString();
      const { error } = await sb.from('user_profiles').update(updates).eq('user_id', userId);
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/admin/teachers/stats — 交易员状态统计 */
  app.get('/api/admin/teachers/stats', requireAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      if (!(await ensureAdmin(req, res, sb))) return;
      const { data, error } = await sb.from('teacher_profiles').select('status');
      if (error) return res.status(502).json({ error: error.message });
      const counts = { pending: 0, approved: 0, rejected: 0, frozen: 0, blocked: 0 };
      for (const row of data || []) {
        const s = String(row.status || 'pending');
        if (counts[s] == null) counts[s] = 0;
        counts[s] += 1;
      }
      return res.json(counts);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/admin/customer-service/staff-basic — 客服人员基础信息 */
  app.get('/api/admin/customer-service/staff-basic', requireAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      if (!(await ensureAdmin(req, res, sb))) return;
      const { data, error } = await sb
        .from('user_profiles')
        .select('user_id, display_name, email, short_id')
        .eq('role', 'customer_service')
        .order('display_name', { ascending: true });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/users/:userId/is-customer-service */
  app.get('/api/users/:userId/is-customer-service', requireAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data } = await sb.from('user_profiles').select('role').eq('user_id', userId).maybeSingle();
      const r = (data?.role || '').toString().toLowerCase();
      res.json({ is_customer_service: r === 'customer_service' });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/users/me/restrictions — 当前用户限制状态 */
  app.get('/api/users/me/restrictions', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('user_profiles')
        .select('banned_until, frozen_until, restrict_login, restrict_send_message, restrict_add_friend, restrict_join_group, restrict_create_group')
        .eq('user_id', uid).maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || {});
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/users/me/last-online — 更新最后上线时间 */
  app.patch('/api/users/me/last-online', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { error } = await sb.from('user_profiles').update({
        last_online_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq('user_id', uid);
      if (error) return res.status(502).json({ error: error.message });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/device-tokens — 保存推送 token */
  app.post('/api/device-tokens', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { token, platform } = req.body || {};
    if (!token || typeof token !== 'string') return res.status(400).json({ error: 'missing token' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { error } = await sb.from('device_tokens').upsert({
        user_id: uid,
        token: token.trim(),
        platform: (platform || 'unknown').toString().trim(),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id,platform' });
      if (error) return res.status(502).json({ error: error.message });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/auth/profile/short-id — 确保 short_id，服务端生成 */
  app.post('/api/auth/profile/short-id', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: existing } = await sb.from('user_profiles').select('short_id').eq('user_id', uid).maybeSingle();
      if (existing?.short_id) return res.json({ short_id: existing.short_id });
      for (let i = 0; i < 10; i++) {
        const candidate = String(Math.floor(100000 + Math.random() * 900000));
        const { error } = await sb.from('user_profiles').update({
          short_id: candidate,
          updated_at: new Date().toISOString(),
        }).eq('user_id', uid).is('short_id', null);
        if (!error) {
          const { data: confirmed } = await sb.from('user_profiles').select('short_id').eq('user_id', uid).maybeSingle();
          if (confirmed?.short_id) return res.json({ short_id: confirmed.short_id });
        }
      }
      res.status(502).json({ error: '生成 short_id 失败' });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerUserRoutes };
