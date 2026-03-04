/**
 * 杂项 API：客服配置、通话邀请、举报等
 */
const supabaseClient = require('./supabaseClient');

function registerMiscRoutes(app, requireAuth) {
  const supabase = () => supabaseClient.getClient();
  if (!supabase()) {
    console.warn('[apiMisc] Supabase 未配置');
    return;
  }

  /** GET /api/config/:key — 获取 app_config 值 */
  app.get('/api/config/:key', requireAuth, async (req, res) => {
    const { key } = req.params;
    if (!key) return res.status(400).json({ error: 'missing key' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('app_config').select('value').eq('key', key).maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      res.json({ value: data?.value ?? null });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/config/:key — 设置 app_config 值（管理员） */
  app.patch('/api/config/:key', requireAuth, async (req, res) => {
    const { key } = req.params;
    const { value } = req.body || {};
    if (!key) return res.status(400).json({ error: 'missing key' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const val = value != null ? String(value).trim() : null;
      await sb.from('app_config').upsert({
        key,
        value: val,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'key' });
      if (key === 'customer_service_avatar_url' && val) {
        const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
        const csId = csRow?.value?.trim();
        if (csId) await sb.from('user_profiles').update({ avatar_url: val, updated_at: new Date().toISOString() }).eq('user_id', csId);
      }
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/customer-service/online-staff */
  app.get('/api/customer-service/online-staff', requireAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
      const csId = csRow?.value?.trim();
      if (!csId) return res.json([]);
      const { data: rows } = await sb.from('user_profiles').select('user_id, status, last_online_at').eq('role', 'customer_service');
      const now = new Date();
      const threshold = 5 * 60 * 1000;
      const list = (rows || []).filter(r => {
        if (r.user_id === csId) return false;
        const status = (r.status || 'offline').toLowerCase();
        if (status === 'online' || status === 'active') return true;
        const lastAt = r.last_online_at;
        if (!lastAt) return false;
        const dt = new Date(lastAt);
        return (now - dt) < threshold;
      }).map(r => r.user_id);
      res.json(list);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/customer-service/all-staff */
  app.get('/api/customer-service/all-staff', requireAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data } = await sb.from('user_profiles').select('user_id').eq('role', 'customer_service');
      res.json((data || []).map(r => r.user_id).filter(Boolean));
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/customer-service/assignments/:userId */
  app.get('/api/customer-service/assignments/:userId', requireAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data } = await sb.from('customer_service_assignments').select('staff_id').eq('user_id', userId).maybeSingle();
      res.json({ staff_id: data?.staff_id || null });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PUT /api/customer-service/assignments */
  app.put('/api/customer-service/assignments', requireAuth, async (req, res) => {
    const { user_id, staff_id } = req.body || {};
    if (!user_id || !staff_id) return res.status(400).json({ error: 'missing user_id or staff_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await sb.from('customer_service_assignments').upsert({ user_id, staff_id, assigned_at: new Date().toISOString() }, { onConflict: 'user_id' });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/customer-service/conversations — 系统客服的会话列表 */
  app.get('/api/customer-service/conversations', requireAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
      const csId = csRow?.value?.trim();
      if (!csId) return res.json([]);
      const { data: memberRows } = await sb.from('chat_members').select('conversation_id, user_id, unread_count').eq('user_id', csId);
      if (!memberRows?.length) return res.json([]);
      const unreadMap = {};
      const convIds = memberRows.map(r => r.conversation_id).filter(Boolean);
      for (const r of memberRows) {
        if (r.conversation_id) unreadMap[r.conversation_id] = r.unread_count || 0;
      }
      const { data: allMembers } = await sb.from('chat_members').select('conversation_id, user_id').in('conversation_id', convIds);
      const peerMap = {};
      for (const r of allMembers || []) {
        if (r.user_id !== csId) peerMap[r.conversation_id] = r.user_id;
      }
      const { data: convos } = await sb.from('chat_conversations').select('*').in('id', convIds).eq('type', 'direct').order('last_time', { ascending: false });
      const list = (convos || []).map(c => ({ ...c, peer_user_id: peerMap[c.id], unread_count: unreadMap[c.id] || 0 }));
      res.json(list);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/customer-service/welcome-message */
  app.post('/api/customer-service/welcome-message', requireAuth, async (req, res) => {
    const { conversation_id, peer_id } = req.body || {};
    if (!conversation_id || !peer_id) return res.status(400).json({ error: 'missing conversation_id or peer_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
      const csId = csRow?.value?.trim();
      if (!csId || peer_id !== csId) return res.json({ ok: true });
      const { data: welcomeRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_welcome_message').maybeSingle();
      const welcome = welcomeRow?.value?.trim();
      if (!welcome) return res.json({ ok: true });
      const { data: existing } = await sb.from('chat_messages').select('id').eq('conversation_id', conversation_id).eq('sender_id', csId).limit(1);
      if (existing?.length) return res.json({ ok: true });
      const { data: profile } = await sb.from('user_profiles').select('display_name').eq('user_id', csId).maybeSingle();
      const displayName = profile?.display_name || '客服';
      await sb.from('chat_messages').insert({ conversation_id, sender_id: csId, sender_name: displayName, content: welcome, message_type: 'text' });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/customer-service/broadcast */
  app.post('/api/customer-service/broadcast', requireAuth, async (req, res) => {
    const { message } = req.body || {};
    if (!message?.trim()) return res.status(400).json({ error: 'missing message' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.rpc('broadcast_customer_service_message', { msg: String(message).trim() });
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || { ok: true, count: 0 });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e), ok: false, count: 0 });
    }
  });

  /** POST /api/customer-service/assign-or-get */
  app.post('/api/customer-service/assign-or-get', requireAuth, async (req, res) => {
    const { user_id } = req.body || {};
    if (!user_id) return res.status(400).json({ error: 'missing user_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
      const csId = csRow?.value?.trim();
      if (!csId) return res.json({ staff_id: null });
      const { data: existing } = await sb.from('customer_service_assignments').select('staff_id').eq('user_id', user_id).maybeSingle();
      if (existing?.staff_id) return res.json({ staff_id: existing.staff_id });
      const { data: online } = await sb.from('user_profiles').select('user_id').eq('role', 'customer_service');
      const staffList = (online || []).map(r => r.user_id).filter(Boolean).filter(id => id !== csId);
      let staffId = csId;
      if (staffList.length > 0) {
        staffId = staffList[Math.abs(parseInt(user_id.slice(-4), 16) || 0) % staffList.length];
        await sb.from('customer_service_assignments').upsert({ user_id, staff_id: staffId, assigned_at: new Date().toISOString() }, { onConflict: 'user_id' });
      }
      res.json({ staff_id: staffId });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/user-profiles/batch — 批量获取用户 display_name、avatar_url，query: ids=id1,id2,id3 */
  app.get('/api/user-profiles/batch', requireAuth, async (req, res) => {
    const ids = (req.query.ids || '').split(',').map(s => s.trim()).filter(Boolean);
    if (ids.length === 0) return res.json({});
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('user_profiles').select('user_id, display_name, email, avatar_url').in('user_id', ids);
      if (error) return res.status(502).json({ error: error.message });
      const out = {};
      for (const row of data || []) {
        const uid = row['user_id'];
        out[uid] = {
          display_name: (row['display_name'] || '').trim() || (row['email'] || '').split('@')[0] || '用户',
          avatar_url: row['avatar_url'] || null,
        };
      }
      res.json(out);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/user-profiles/:userId/display-name — 获取用户展示名 */
  app.get('/api/user-profiles/:userId/display-name', requireAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('user_profiles').select('display_name, email').eq('user_id', userId).maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      const name = data?.display_name?.trim() || data?.email?.split('@')[0] || '用户';
      res.json({ display_name: name });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/reports — 管理员：举报列表 */
  app.get('/api/reports', requireAuth, async (req, res) => {
    const { status } = req.query || {};
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      let q = sb.from('user_reports').select('*').order('created_at', { ascending: false });
      if (status && status !== 'all') q = q.eq('status', status);
      const { data, error } = await q;
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/reports/:id — 管理员：更新举报状态 */
  app.patch('/api/reports/:id', requireAuth, async (req, res) => {
    const { id } = req.params;
    const { status, admin_notes } = req.body || {};
    if (!id || !status) return res.status(400).json({ error: 'missing id or status' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await sb.from('user_reports').update({
        status,
        admin_notes: admin_notes || null,
        reviewed_at: new Date().toISOString(),
        reviewed_by: req.firebaseUid,
        updated_at: new Date().toISOString(),
      }).eq('id', parseInt(id, 10));
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/reports — 提交举报 */
  app.post('/api/reports', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { reported_user_id, reason, content, screenshot_urls } = req.body || {};
    if (!reported_user_id || !reason) return res.status(400).json({ error: 'missing reported_user_id or reason' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await sb.from('user_reports').insert({
        reporter_id: uid,
        reported_user_id,
        reason,
        content: content?.trim() || null,
        screenshot_urls: Array.isArray(screenshot_urls) ? screenshot_urls : [],
        status: 'pending',
        updated_at: new Date().toISOString(),
      });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/call-invitations — 创建通话邀请（简化版，替代 Edge Function） */
  app.post('/api/call-invitations', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { to_user_id, from_user_name, channel_id, call_type } = req.body || {};
    if (!to_user_id || !channel_id) return res.status(400).json({ error: 'missing to_user_id or channel_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: profile } = await sb.from('user_profiles').select('display_name').eq('user_id', uid).maybeSingle();
      const name = from_user_name || profile?.display_name || '用户';
      const { data: inserted, error } = await sb.from('call_invitations').insert({
        from_user_id: uid,
        from_user_name: name,
        to_user_id,
        channel_id,
        call_type: call_type || 'voice',
        status: 'ringing',
      }).select('id').single();
      if (error) return res.status(502).json({ error: error.message });
      res.json({ id: inserted.id });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/call-invitations/:id — 查询邀请状态 */
  app.get('/api/call-invitations/:id', requireAuth, async (req, res) => {
    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('call_invitations').select('*').eq('id', id).maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      res.json(data);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/call-invitations/ringing — 被叫：获取发给我且 status=ringing 的最新一条（2分钟内） */
  app.get('/api/call-invitations/ringing', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const since = new Date(Date.now() - 2 * 60 * 1000).toISOString();
      const { data, error } = await sb.from('call_invitations')
        .select('*')
        .eq('to_user_id', uid)
        .eq('status', 'ringing')
        .gte('created_at', since)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      res.json(data);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/call-invitations/:id/status — 更新通话状态 */
  app.patch('/api/call-invitations/:id/status', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    const { status } = req.body || {};
    if (!id || !status) return res.status(400).json({ error: 'missing id or status' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await sb.from('call_invitations').update({ status }).eq('id', id);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/call-invitations/records — 与某人的通话记录 */
  app.get('/api/call-invitations/records', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { peer_user_id, limit } = req.query || {};
    if (!peer_user_id) return res.status(400).json({ error: 'missing peer_user_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const lim = Math.min(parseInt(limit, 10) || 50, 100);
      const { data, error } = await sb.from('call_invitations')
        .select('id, from_user_id, to_user_id, call_type, status, created_at')
        .or(`and(from_user_id.eq.${uid},to_user_id.eq.${peer_user_id}),and(from_user_id.eq.${peer_user_id},to_user_id.eq.${uid})`)
        .order('created_at', { ascending: false })
        .limit(lim);
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerMiscRoutes };
