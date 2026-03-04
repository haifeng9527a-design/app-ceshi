/**
 * 好友相关 API：/api/friends/*
 * 由 backend 代理 Supabase friends、friend_requests、friend_remarks
 */
const supabaseClient = require('./supabaseClient');

function registerFriendRoutes(app, requireAuth) {
  const supabase = () => supabaseClient.getClient();
  if (!supabase()) {
    console.warn('[apiFriends] Supabase 未配置，好友接口不可用');
    return;
  }

  /** GET /api/friends — 好友列表 */
  app.get('/api/friends', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: friendRows, error: e1 } = await sb.from('friends').select('friend_id').eq('user_id', uid);
      if (e1) return res.status(502).json({ error: e1.message });
      const friendIds = (friendRows || []).map(r => r.friend_id).filter(Boolean);
      if (friendIds.length === 0) return res.json([]);
      const { data: profiles, error: e2 } = await sb.from('user_profiles')
        .select('user_id, display_name, email, avatar_url, status, short_id, role, level, teacher_status, last_online_at')
        .in('user_id', friendIds);
      if (e2) return res.status(502).json({ error: e2.message });
      const { data: teacherRows } = await sb.from('teacher_profiles').select('user_id, status').in('user_id', friendIds);
      const tpMap = Object.fromEntries((teacherRows || []).map(r => [r.user_id, r.status]));
      const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
      const csId = csRow?.value?.trim();
      let csAvatar = null;
      if (csId) {
        const { data: avRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_avatar_url').maybeSingle();
        csAvatar = avRow?.value?.trim();
      }
      const list = (profiles || []).map(row => {
        const r = { ...row };
        r.teacher_status = tpMap[row.user_id] ?? row.teacher_status ?? 'pending';
        if (row.user_id === csId && csAvatar) r.avatar_url = csAvatar;
        return r;
      });
      res.json(list);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/friends/remarks — 好友备注 */
  app.get('/api/friends/remarks', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: rows, error } = await sb.from('friend_remarks').select('*').eq('user_id', uid);
      if (error) return res.status(502).json({ error: error.message });
      const friendIds = [...new Set((rows || []).map(r => r.friend_id).filter(Boolean))];
      let profiles = [];
      if (friendIds.length > 0) {
        const { data: p } = await sb.from('user_profiles').select('user_id, display_name, email').in('user_id', friendIds);
        profiles = p || [];
      }
      const profileMap = Object.fromEntries(profiles.map(p => [p.user_id, p]));
      const remarks = {};
      for (const row of rows || []) {
        const fid = row.friend_id;
        const remark = row.remark?.trim();
        if (!fid || !remark) continue;
        remarks[`id:${fid}`] = remark;
        remarks[fid] = remark;
        const profile = profileMap[fid];
        if (profile?.display_name) remarks[`name:${profile.display_name}`] = remark;
        if (profile?.email) remarks[`email:${profile.email}`] = remark;
      }
      res.json(remarks);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PUT /api/friends/remarks — 保存好友备注 */
  app.put('/api/friends/remarks', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { friend_id, remark } = req.body || {};
    if (!friend_id) return res.status(400).json({ error: 'missing friend_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const trimmed = String(remark || '').trim();
      if (trimmed === '') {
        await sb.from('friend_remarks').delete().eq('user_id', uid).eq('friend_id', friend_id);
      } else {
        await sb.from('friend_remarks').upsert({
          user_id: uid,
          friend_id: friend_id,
          remark: trimmed,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id,friend_id' });
      }
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/friends/requests/incoming — 收到的好友申请 */
  app.get('/api/friends/requests/incoming', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: rows, error } = await sb.from('friend_requests').select('*').eq('receiver_id', uid).eq('status', 'pending');
      if (error) return res.status(502).json({ error: error.message });
      const requesterIds = [...new Set((rows || []).map(r => r.requester_id).filter(Boolean))];
      let profiles = [];
      if (requesterIds.length > 0) {
        const { data: p } = await sb.from('user_profiles').select('user_id, display_name, email, avatar_url, short_id').in('user_id', requesterIds);
        profiles = p || [];
      }
      const profileMap = Object.fromEntries(profiles.map(p => [p.user_id, p]));
      const list = (rows || []).map(row => {
        const p = profileMap[row.requester_id];
        return {
          request_id: row.id,
          requester_id: row.requester_id,
          requester_name: p?.display_name || p?.email?.split('@')[0] || '用户',
          requester_email: p?.email || '',
          requester_avatar: p?.avatar_url,
          requester_short_id: p?.short_id,
          status: row.status,
          created_at: row.created_at,
        };
      });
      res.json(list);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/friends/requests/all — 收到+发出的所有好友申请（含 pending/accepted/rejected） */
  app.get('/api/friends/requests/all', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: rows, error } = await sb.from('friend_requests').select('*')
        .or(`requester_id.eq.${uid},receiver_id.eq.${uid}`)
        .order('created_at', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      const userIds = [...new Set((rows || []).flatMap(r => [r.requester_id, r.receiver_id]).filter(Boolean))];
      let profiles = [];
      if (userIds.length > 0) {
        const { data: p } = await sb.from('user_profiles').select('user_id, display_name, email, avatar_url, short_id').in('user_id', userIds);
        profiles = p || [];
      }
      const profileMap = Object.fromEntries(profiles.map(p => [p.user_id, p]));
      const list = (rows || []).map(row => {
        const isOutgoing = row.requester_id === uid;
        const otherId = isOutgoing ? row.receiver_id : row.requester_id;
        const p = profileMap[otherId];
        const name = p?.display_name || p?.email?.split('@')[0] || '用户';
        return {
          request_id: row.id,
          requester_id: row.requester_id,
          receiver_id: row.receiver_id,
          requester_name: isOutgoing ? '' : name,
          requester_email: isOutgoing ? '' : (p?.email || ''),
          requester_avatar: isOutgoing ? null : (p?.avatar_url),
          requester_short_id: isOutgoing ? null : (p?.short_id),
          receiver_name: isOutgoing ? name : '',
          receiver_email: isOutgoing ? (p?.email || '') : '',
          receiver_avatar: isOutgoing ? (p?.avatar_url) : null,
          receiver_short_id: isOutgoing ? (p?.short_id) : null,
          status: row.status,
          created_at: row.created_at,
          is_outgoing: isOutgoing,
        };
      });
      res.json(list);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/friends/requests/incoming/count — 待处理申请数量 */
  app.get('/api/friends/requests/incoming/count', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('friend_requests').select('id').eq('receiver_id', uid).eq('status', 'pending');
      if (error) return res.status(502).json({ error: error.message });
      res.json({ count: (data || []).length });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/friends/requests — 发送好友申请 */
  app.post('/api/friends/requests', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { receiver_id } = req.body || {};
    if (!receiver_id) return res.status(400).json({ error: 'missing receiver_id' });
    if (uid === receiver_id) return res.status(400).json({ error: 'cannot_add_self' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: existing } = await sb.from('friend_requests').select('*').eq('requester_id', uid).eq('receiver_id', receiver_id).maybeSingle();
      if (existing) {
        if (existing.status === 'accepted') return res.status(400).json({ error: 'already_friends' });
        if (existing.status === 'pending') return res.status(400).json({ error: 'already_pending' });
        if (existing.status === 'rejected') {
          await sb.from('friend_requests').update({ status: 'pending', created_at: new Date().toISOString() }).eq('id', existing.id);
          return res.json({ ok: true });
        }
      }
      await sb.from('friend_requests').insert({ requester_id: uid, receiver_id, status: 'pending' });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/friends/requests/:requestId/accept — 接受好友申请 */
  app.post('/api/friends/requests/:requestId/accept', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { requestId } = req.params;
    const { requester_id, receiver_id } = req.body || {};
    if (!requestId) return res.status(400).json({ error: 'missing requestId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: reqRow } = await sb.from('friend_requests').select('requester_id, receiver_id').eq('id', requestId).maybeSingle();
      if (!reqRow) return res.status(404).json({ error: 'request not found' });
      const rid = reqRow.requester_id;
      const rec = reqRow.receiver_id;
      if (rec !== uid) return res.status(403).json({ error: 'not receiver' });
      await sb.from('friend_requests').update({ status: 'accepted' }).eq('id', requestId);
      await sb.from('friends').insert([{ user_id: rid, friend_id: rec }, { user_id: rec, friend_id: rid }]);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/friends/requests/:requestId/reject — 拒绝好友申请 */
  app.post('/api/friends/requests/:requestId/reject', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { requestId } = req.params;
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: reqRow } = await sb.from('friend_requests').select('receiver_id').eq('id', requestId).maybeSingle();
      if (!reqRow) return res.status(404).json({ error: 'request not found' });
      if (reqRow.receiver_id !== uid) return res.status(403).json({ error: 'not receiver' });
      await sb.from('friend_requests').update({ status: 'rejected' }).eq('id', requestId);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/friends/:friendId — 删除好友 */
  app.delete('/api/friends/:friendId', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { friendId } = req.params;
    if (!friendId) return res.status(400).json({ error: 'missing friendId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await sb.from('friends').delete().eq('user_id', uid).eq('friend_id', friendId);
      await sb.from('friends').delete().eq('user_id', friendId).eq('friend_id', uid);
      await sb.from('friend_requests').delete().eq('requester_id', uid).eq('receiver_id', friendId);
      await sb.from('friend_requests').delete().eq('requester_id', friendId).eq('receiver_id', uid);
      await sb.from('friend_remarks').delete().eq('user_id', uid).eq('friend_id', friendId);
      await sb.from('friend_remarks').delete().eq('user_id', friendId).eq('friend_id', uid);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/friends/search — 按 email/short_id 查找用户 */
  app.get('/api/friends/search', requireAuth, async (req, res) => {
    const { by, value } = req.query || {};
    if (!by || !value) return res.status(400).json({ error: 'missing by or value' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      let query = sb.from('user_profiles').select('user_id, display_name, email, avatar_url, status, short_id, role, level, teacher_status, last_online_at');
      if (by === 'email') query = query.eq('email', value.trim());
      else if (by === 'short_id') query = query.eq('short_id', value.trim());
      else return res.status(400).json({ error: 'by must be email or short_id' });
      const { data: row, error } = await query.maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      if (!row) return res.json(null);
      const { data: tp } = await sb.from('teacher_profiles').select('status').eq('user_id', row.user_id).maybeSingle();
      const out = { ...row };
      if (tp?.status) out.teacher_status = tp.status;
      res.json(out);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/friends/check/:friendId — 是否已是好友 */
  app.get('/api/friends/check/:friendId', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { friendId } = req.params;
    if (!friendId) return res.status(400).json({ error: 'missing friendId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: fr } = await sb.from('friends').select('user_id').eq('user_id', uid).eq('friend_id', friendId).maybeSingle();
      if (fr) return res.json({ is_friend: true });
      const { data: req1 } = await sb.from('friend_requests').select('status').eq('requester_id', uid).eq('receiver_id', friendId).maybeSingle();
      if (req1?.status === 'accepted') return res.json({ is_friend: true });
      const { data: req2 } = await sb.from('friend_requests').select('status').eq('requester_id', friendId).eq('receiver_id', uid).maybeSingle();
      if (req2?.status === 'accepted') return res.json({ is_friend: true });
      res.json({ is_friend: false });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/friends/ensure-customer-service — 确保已添加客服为好友 */
  app.post('/api/friends/ensure-customer-service', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
      const csId = csRow?.value?.trim();
      if (!csId || csId === uid) return res.json({ ok: true });
      const { data: existing } = await sb.from('friends').select('user_id').eq('user_id', uid).eq('friend_id', csId).maybeSingle();
      if (existing) return res.json({ ok: true });
      await sb.from('friends').insert([{ user_id: uid, friend_id: csId }, { user_id: csId, friend_id: uid }]);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerFriendRoutes };
