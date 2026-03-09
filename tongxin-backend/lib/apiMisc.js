/**
 * 杂项 API：客服配置、通话邀请、举报等
 */
const crypto = require('crypto');
const supabaseClient = require('./supabaseClient');
const { sendToUser } = require('./chatWebSocket');

const AGORA_TOKEN_VERSION = '006';
const AGORA_APP_ID_LENGTH = 32;

const crcTable = (() => {
  const table = [];
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32Str(value) {
  let crc = 0 ^ -1;
  for (let i = 0; i < value.length; i += 1) {
    crc = (crc >>> 8) ^ crcTable[(crc ^ value.charCodeAt(i)) & 0xff];
  }
  return (crc ^ -1) >>> 0;
}

function packMessages(salt, ts, messages) {
  const keys = Object.keys(messages).map(Number);
  const buf = Buffer.alloc(4 + 4 + 2 + (keys.length * 6));
  let offset = 0;
  buf.writeUInt32LE(salt >>> 0, offset);
  offset += 4;
  buf.writeUInt32LE(ts >>> 0, offset);
  offset += 4;
  buf.writeUInt16LE(keys.length, offset);
  offset += 2;
  for (const key of keys) {
    buf.writeUInt16LE(key, offset);
    offset += 2;
    buf.writeUInt32LE(messages[key] >>> 0, offset);
    offset += 4;
  }
  return buf;
}

function packWithLength(data) {
  const payload = Buffer.isBuffer(data) ? data : Buffer.from(data);
  const out = Buffer.alloc(2 + payload.length);
  out.writeUInt16LE(payload.length, 0);
  payload.copy(out, 2);
  return out;
}

function buildRtcTokenV1(appId, appCertificate, channelName, uid, privilegeExpiredTs) {
  const uidStr = uid === 0 ? '' : String(uid);
  const salt = Math.floor(Math.random() * 0xffffffff) >>> 0;
  const ts = Math.floor(Date.now() / 1000) + (24 * 3600);
  const messages = {
    1: privilegeExpiredTs,
    2: privilegeExpiredTs,
    3: privilegeExpiredTs,
    4: privilegeExpiredTs,
  };
  const packedMessages = packMessages(salt, ts, messages);
  const toSign = Buffer.concat([
    Buffer.from(appId),
    Buffer.from(channelName),
    Buffer.from(uidStr),
    packedMessages,
  ]);
  const signature = crypto.createHmac('sha256', appCertificate).update(toSign).digest();
  const contentSig = packWithLength(signature);
  const contentMessages = packWithLength(packedMessages);
  const content = Buffer.alloc(contentSig.length + 4 + 4 + contentMessages.length);
  let offset = 0;
  contentSig.copy(content, offset);
  offset += contentSig.length;
  content.writeUInt32LE(crc32Str(channelName) >>> 0, offset);
  offset += 4;
  content.writeUInt32LE(crc32Str(uidStr) >>> 0, offset);
  offset += 4;
  contentMessages.copy(content, offset);
  return `${AGORA_TOKEN_VERSION}${appId}${content.toString('base64')}`;
}

function buildAgoraRtcToken(channelId, uid, expireSeconds) {
  const appId = String(process.env.AGORA_APP_ID || '').trim();
  const appCertificate = String(process.env.AGORA_APP_CERTIFICATE || '').trim();
  if (!appId || !appCertificate) {
    return { error: 'Missing AGORA_APP_ID or AGORA_APP_CERTIFICATE', status: 503 };
  }
  if (appId.length !== AGORA_APP_ID_LENGTH) {
    return { error: 'Invalid AGORA_APP_ID length', status: 503 };
  }
  const privilegeExpiredTs = Math.floor(Date.now() / 1000) + expireSeconds;
  try {
    return { token: buildRtcTokenV1(appId, appCertificate, channelId, uid, privilegeExpiredTs) };
  } catch (e) {
    console.error('[api/call-invitations/agora-token] build error:', e);
    return { error: 'Failed to build Agora token', status: 500 };
  }
}

async function getUserRole(sb, uid) {
  const { data, error } = await sb.from('user_profiles').select('role').eq('user_id', uid).maybeSingle();
  if (error) throw new Error(error.message);
  return String(data?.role || '').toLowerCase();
}

function createRoleGuard(allowedRoles) {
  const normalized = new Set(allowedRoles.map((r) => String(r).toLowerCase()));
  return async (req, res, next) => {
    if (req.isAdminByKey === true) return next();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const role = await getUserRole(sb, uid);
      if (!normalized.has(role)) return res.status(403).json({ error: 'forbidden' });
      return next();
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  };
}

function registerMiscRoutes(app, requireAuth) {
  const requireAdminRole = createRoleGuard(['admin', 'customer_service_admin']);
  const supabase = () => supabaseClient.getClient();

  /** GET /api/call-invitations/agora-token — 统一由后端签发 Agora RTC Token */
  app.get('/api/call-invitations/agora-token', requireAuth, async (req, res) => {
    const channelId = String(req.query?.channel_id || req.query?.channelId || '').trim();
    const rawUid = Number.parseInt(String(req.query?.uid || '0'), 10);
    const uid = Number.isFinite(rawUid) && rawUid > 0 ? rawUid : 0;
    if (!channelId) return res.status(400).json({ error: 'Missing channel_id' });
    const expireSeconds = 3600;
    const result = buildAgoraRtcToken(channelId, uid, expireSeconds);
    if (!result.token) {
      return res.status(result.status || 500).json({ error: result.error || 'Failed to build Agora token' });
    }
    return res.json({ token: result.token, expireSeconds });
  });

  if (!supabase()) {
    console.warn('[apiMisc] Supabase 未配置');
    return;
  }

  /** GET /api/config/app — 获取 App 客户端配置（无需鉴权，供启动时拉取） */
  app.get('/api/config/app', async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const keys = [
        'user_trading_center_hidden_versions',
        'webview_user_page_url',
        'user_trading_center_menu_title',
        'user_trading_center_menu_subtitle',
        'user_trading_center_hidden_menu_title',
        'user_trading_center_hidden_menu_subtitle',
      ];
      const { data: rows, error } = await sb
        .from('app_config')
        .select('key, value')
        .in('key', keys);
      if (error) return res.status(502).json({ error: error.message });
      const map = {};
      for (const r of rows || []) {
        map[r.key] = r.value != null ? String(r.value).trim() : null;
      }
      res.json({
        user_trading_center_hidden_versions: map.user_trading_center_hidden_versions || null,
        webview_user_page_url: map.webview_user_page_url || null,
        user_trading_center_menu_title: map.user_trading_center_menu_title || null,
        user_trading_center_menu_subtitle: map.user_trading_center_menu_subtitle || null,
        user_trading_center_hidden_menu_title: map.user_trading_center_hidden_menu_title || null,
        user_trading_center_hidden_menu_subtitle: map.user_trading_center_hidden_menu_subtitle || null,
      });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

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
  app.patch('/api/config/:key', requireAuth, requireAdminRole, async (req, res) => {
    const { key } = req.params;
    const { value } = req.body || {};
    if (!key) return res.status(400).json({ error: 'missing key' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const val = value != null ? String(value).trim() : null;
      const { error: upsertErr } = await sb.from('app_config').upsert({
        key,
        value: val,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'key' });
      if (upsertErr) return res.status(502).json({ error: upsertErr.message });
      if (key === 'customer_service_avatar_url' && val) {
        const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
        const csId = csRow?.value?.trim();
        if (csId) {
          const { error: profileErr } = await sb
            .from('user_profiles')
            .update({ avatar_url: val, updated_at: new Date().toISOString() })
            .eq('user_id', csId);
          if (profileErr) return res.status(502).json({ error: profileErr.message });
        }
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

  /** GET /api/customer-service/stats — 客服运行态统计 */
  app.get('/api/customer-service/stats', requireAuth, requireAdminRole, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: csRow } = await sb.from('app_config').select('value').eq('key', 'customer_service_user_id').maybeSingle();
      const csId = csRow?.value?.trim() || null;
      const { data: staffRows } = await sb.from('user_profiles').select('user_id').eq('role', 'customer_service');
      const staffIds = (staffRows || []).map((r) => r.user_id).filter(Boolean);
      const { data: assignRows } = await sb.from('customer_service_assignments').select('staff_id');
      const assignmentByStaff = {};
      for (const r of assignRows || []) {
        const sid = r.staff_id;
        if (!sid) continue;
        assignmentByStaff[sid] = (assignmentByStaff[sid] || 0) + 1;
      }
      res.json({
        system_cs_user_id: csId,
        staff_count: staffIds.length,
        assignment_by_staff: assignmentByStaff,
      });
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
  app.put('/api/customer-service/assignments', requireAuth, requireAdminRole, async (req, res) => {
    const { user_id, staff_id } = req.body || {};
    if (!user_id || !staff_id) return res.status(400).json({ error: 'missing user_id or staff_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { error } = await sb
        .from('customer_service_assignments')
        .upsert({ user_id, staff_id, assigned_at: new Date().toISOString() }, { onConflict: 'user_id' });
      if (error) return res.status(502).json({ error: error.message });
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
  app.post('/api/customer-service/broadcast', requireAuth, requireAdminRole, async (req, res) => {
    const { message } = req.body || {};
    if (!message?.trim()) return res.status(400).json({ error: 'missing message' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const msg = String(message).trim();
      const { data: csRow, error: csErr } = await sb
        .from('app_config')
        .select('value')
        .eq('key', 'customer_service_user_id')
        .maybeSingle();
      if (csErr) return res.status(502).json({ error: csErr.message, ok: false, count: 0 });
      const csId = (csRow?.value || '').toString().trim();
      if (!csId) return res.status(400).json({ error: '未配置系统客服', ok: false, count: 0 });

      const { data: profile, error: profileErr } = await sb
        .from('user_profiles')
        .select('display_name')
        .eq('user_id', csId)
        .maybeSingle();
      if (profileErr) return res.status(502).json({ error: profileErr.message, ok: false, count: 0 });
      const csName = (profile?.display_name || '').toString().trim() || '客服';

      const { data: convRows, error: convErr } = await sb
        .from('chat_members')
        .select('conversation_id')
        .eq('user_id', csId);
      if (convErr) return res.status(502).json({ error: convErr.message, ok: false, count: 0 });

      const convIds = Array.from(new Set((convRows || []).map((r) => r.conversation_id).filter(Boolean)));
      if (convIds.length === 0) return res.json({ ok: true, count: 0 });

      const { data: directRows, error: directErr } = await sb
        .from('chat_conversations')
        .select('id')
        .in('id', convIds)
        .eq('type', 'direct');
      if (directErr) return res.status(502).json({ error: directErr.message, ok: false, count: 0 });

      const directIds = (directRows || []).map((r) => r.id).filter(Boolean);
      if (directIds.length === 0) return res.json({ ok: true, count: 0 });

      const rows = directIds.map((conversationId) => ({
        conversation_id: conversationId,
        sender_id: csId,
        sender_name: csName,
        content: msg,
        message_type: 'text',
      }));
      const { error: insertErr } = await sb.from('chat_messages').insert(rows);
      if (insertErr) return res.status(502).json({ error: insertErr.message, ok: false, count: 0 });

      res.json({ ok: true, count: rows.length });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e), ok: false, count: 0 });
    }
  });

  /** POST /api/admin/notifications/send-push — 管理后台发送推送 */
  app.post('/api/admin/notifications/send-push', requireAuth, requireAdminRole, async (req, res) => {
    const payload = req.body || {};
    const receiverId = (payload.receiverId || '').toString().trim();
    if (!receiverId) return res.status(400).json({ error: 'missing receiverId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.functions.invoke('send_push', { body: payload });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data ?? { ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
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
      const { data: onlineRows } = await sb
        .from('user_profiles')
        .select('user_id, status, last_online_at')
        .eq('role', 'customer_service');
      const now = new Date();
      const threshold = 5 * 60 * 1000;
      const staffList = (onlineRows || [])
        .filter((r) => {
          const id = r.user_id;
          if (!id || id === csId) return false;
          const status = String(r.status || '').toLowerCase();
          if (status === 'online' || status === 'active') return true;
          if (!r.last_online_at) return false;
          const dt = new Date(r.last_online_at);
          if (Number.isNaN(dt.getTime())) return false;
          return now - dt < threshold;
        })
        .map((r) => r.user_id);
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
      const { data, error } = await sb.from('user_profiles').select('user_id, display_name, email, avatar_url, short_id').in('user_id', ids);
      if (error) return res.status(502).json({ error: error.message });
      const out = {};
      for (const row of data || []) {
        const uid = row['user_id'];
        out[uid] = {
          display_name: (row['display_name'] || '').trim() || (row['email'] || '').split('@')[0] || '用户',
          avatar_url: row['avatar_url'] || null,
          email: row['email'] || null,
          short_id: row['short_id'] || null,
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
  app.get('/api/reports', requireAuth, requireAdminRole, async (req, res) => {
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
  app.patch('/api/reports/:id', requireAuth, requireAdminRole, async (req, res) => {
    const { id } = req.params;
    const {
      status,
      admin_notes,
      reported_user_id,
      freeze,
      ban,
      restrict_send_message,
      restrict_add_friend,
      restrict_join_group,
      restrict_create_group,
      duration_days,
    } = req.body || {};
    if (!id || !status) return res.status(400).json({ error: 'missing id or status' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      if (String(status) === 'approved') {
        const actionFlags = {
          freeze: freeze === true,
          ban: ban === true,
          restrict_send_message: restrict_send_message === true,
          restrict_add_friend: restrict_add_friend === true,
          restrict_join_group: restrict_join_group === true,
          restrict_create_group: restrict_create_group === true,
        };
        const hasAnyAction = Object.values(actionFlags).some((v) => v === true);
        if (hasAnyAction) {
          let targetUserId = (reported_user_id || '').toString().trim();
          if (!targetUserId) {
            const { data: reportRow, error: reportErr } = await sb
              .from('user_reports')
              .select('reported_user_id')
              .eq('id', parseInt(id, 10))
              .maybeSingle();
            if (reportErr) return res.status(502).json({ error: reportErr.message });
            targetUserId = (reportRow?.reported_user_id || '').toString().trim();
          }
          if (!targetUserId) return res.status(400).json({ error: 'missing reported_user_id' });
          const now = Date.now();
          const days = Number.isFinite(Number(duration_days)) ? Math.max(0, parseInt(duration_days, 10)) : 30;
          const until = days <= 0 ? new Date('2099-01-01T00:00:00.000Z') : new Date(now + days * 24 * 60 * 60 * 1000);
          const updates = {
            updated_at: new Date().toISOString(),
          };
          if (actionFlags.freeze) updates.frozen_until = until.toISOString();
          if (actionFlags.ban) updates.banned_until = until.toISOString();
          if (actionFlags.restrict_send_message) updates.restrict_send_message = true;
          if (actionFlags.restrict_add_friend) updates.restrict_add_friend = true;
          if (actionFlags.restrict_join_group) updates.restrict_join_group = true;
          if (actionFlags.restrict_create_group) updates.restrict_create_group = true;
          const { error: userErr } = await sb.from('user_profiles').update(updates).eq('user_id', targetUserId);
          if (userErr) return res.status(502).json({ error: userErr.message });
        }
      }
      const { error } = await sb.from('user_reports').update({
        status,
        admin_notes: admin_notes || null,
        reviewed_at: new Date().toISOString(),
        reviewed_by: req.firebaseUid,
        updated_at: new Date().toISOString(),
      }).eq('id', parseInt(id, 10));
      if (error) return res.status(502).json({ error: error.message });
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
      const { error } = await sb.from('user_reports').insert({
        reporter_id: uid,
        reported_user_id,
        reason,
        content: content?.trim() || null,
        screenshot_urls: Array.isArray(screenshot_urls) ? screenshot_urls : [],
        status: 'pending',
        updated_at: new Date().toISOString(),
      });
      if (error) return res.status(502).json({ error: error.message });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/reports/me/received — 当前用户被举报记录（用于申诉） */
  app.get('/api/reports/me/received', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const status = (req.query?.status || '').toString().trim();
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      let q = sb
        .from('user_reports')
        .select('id, reporter_id, reason, content, status, created_at, reviewed_at, admin_notes')
        .eq('reported_user_id', uid)
        .order('created_at', { ascending: false });
      if (status) q = q.eq('status', status);
      const { data, error } = await q;
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/reports/appeals — 被处罚用户提交申诉 */
  app.post('/api/reports/appeals', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { report_id, appeal_content } = req.body || {};
    const reportId = parseInt(report_id, 10);
    const content = (appeal_content || '').toString().trim();
    if (!reportId || !content) return res.status(400).json({ error: 'missing report_id or appeal_content' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: report, error: reportErr } = await sb
        .from('user_reports')
        .select('id, reported_user_id, status')
        .eq('id', reportId)
        .maybeSingle();
      if (reportErr) return res.status(502).json({ error: reportErr.message });
      if (!report) return res.status(404).json({ error: 'report not found' });
      if ((report.reported_user_id || '') !== uid) return res.status(403).json({ error: 'forbidden' });
      if ((report.status || '') !== 'approved') return res.status(400).json({ error: 'only approved report can be appealed' });

      const nowIso = new Date().toISOString();
      const { data: existedPending } = await sb
        .from('user_report_appeals')
        .select('id')
        .eq('report_id', reportId)
        .eq('appellant_id', uid)
        .eq('status', 'pending')
        .limit(1)
        .maybeSingle();
      if (existedPending?.id) {
        return res.status(409).json({ error: 'pending appeal already exists' });
      }

      const { data: inserted, error } = await sb
        .from('user_report_appeals')
        .insert({
          report_id: reportId,
          appellant_id: uid,
          appeal_content: content,
          status: 'pending',
          updated_at: nowIso,
        })
        .select('*')
        .single();
      if (error) return res.status(502).json({ error: error.message });
      res.json(inserted);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/reports/appeals/mine — 当前用户申诉记录 */
  app.get('/api/reports/appeals/mine', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('user_report_appeals')
        .select('*')
        .eq('appellant_id', uid)
        .order('created_at', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/reports/:id/appeals — 管理员查看某举报关联申诉 */
  app.get('/api/reports/:id/appeals', requireAuth, requireAdminRole, async (req, res) => {
    const reportId = parseInt(req.params.id, 10);
    if (!reportId) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('user_report_appeals')
        .select('*')
        .eq('report_id', reportId)
        .order('created_at', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/reports/appeals/:id — 管理员处理申诉，可恢复用户限制 */
  app.patch('/api/reports/appeals/:id', requireAuth, requireAdminRole, async (req, res) => {
    const appealId = parseInt(req.params.id, 10);
    const { status, admin_notes, clear_restrictions } = req.body || {};
    if (!appealId || !status) return res.status(400).json({ error: 'missing id or status' });
    if (!['approved', 'rejected'].includes(status)) return res.status(400).json({ error: 'invalid status' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const nowIso = new Date().toISOString();
      const { data: appeal, error: appealErr } = await sb
        .from('user_report_appeals')
        .select('id, report_id, appellant_id, status')
        .eq('id', appealId)
        .maybeSingle();
      if (appealErr) return res.status(502).json({ error: appealErr.message });
      if (!appeal) return res.status(404).json({ error: 'appeal not found' });
      if (appeal.status !== 'pending') return res.status(409).json({ error: 'appeal already processed' });

      const shouldClear = clear_restrictions === true || (clear_restrictions == null && status === 'approved');
      if (status === 'approved' && shouldClear && appeal.appellant_id) {
        const { error: clearErr } = await sb.from('user_profiles').update({
          banned_until: null,
          frozen_until: null,
          restrict_login: false,
          restrict_send_message: false,
          restrict_add_friend: false,
          restrict_join_group: false,
          restrict_create_group: false,
          updated_at: nowIso,
        }).eq('user_id', appeal.appellant_id);
        if (clearErr) return res.status(502).json({ error: clearErr.message });
      }

      const { error: updateAppealErr } = await sb.from('user_report_appeals').update({
        status,
        admin_notes: admin_notes || null,
        reviewed_at: nowIso,
        reviewed_by: req.firebaseUid,
        updated_at: nowIso,
      }).eq('id', appealId);
      if (updateAppealErr) return res.status(502).json({ error: updateAppealErr.message });

      // 申诉通过时，补充举报备注用于审计追溯
      if (status === 'approved' && appeal.report_id) {
        const { data: reportRow } = await sb.from('user_reports').select('admin_notes').eq('id', appeal.report_id).maybeSingle();
        const oldNotes = (reportRow?.admin_notes || '').toString().trim();
        const appendText = `[appeal-approved ${nowIso}] by ${req.firebaseUid}`;
        const merged = oldNotes ? `${oldNotes}\n${appendText}` : appendText;
        const { error: appendErr } = await sb
          .from('user_reports')
          .update({ admin_notes: merged, updated_at: nowIso })
          .eq('id', appeal.report_id);
        if (appendErr) return res.status(502).json({ error: appendErr.message });
      }

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
      const { data: profile } = await sb.from('user_profiles').select('display_name, avatar_url').eq('user_id', uid).maybeSingle();
      const name = from_user_name || profile?.display_name || '用户';
      const avatarUrl = profile?.avatar_url || null;
      const callType = call_type || 'voice';
      const { data: inserted, error } = await sb.from('call_invitations').insert({
        from_user_id: uid,
        from_user_name: name,
        to_user_id,
        channel_id,
        call_type: callType,
        status: 'ringing',
      }).select('id').single();
      if (error) return res.status(502).json({ error: error.message });
      const invitationId = String(inserted.id);
      const wsDelivered = sendToUser(String(to_user_id), {
        type: 'call_invitation',
        messageType: 'call_invitation',
        invitationId,
        channelId: String(channel_id),
        callType,
        fromUserId: uid,
        fromUserName: name,
        fromAvatarUrl: avatarUrl,
      });
      if (wsDelivered > 0) {
        console.log(`[api/call-invitations] ws delivered uid=${String(to_user_id).slice(0, 12)} sockets=${wsDelivered} invitation=${invitationId.slice(0, 8)}`);
      } else {
        try {
          const { error: pushError } = await sb.functions.invoke('send_push', {
            body: {
              receiverId: String(to_user_id),
              title: callType === 'video' ? '视频通话' : '语音通话',
              body: `${name} 邀请你${callType === 'video' ? '视频' : '语音'}通话`,
              messageType: 'call_invitation',
              invitationId,
              channelId: String(channel_id),
              callType,
              fromUserName: name,
            },
          });
          if (pushError) {
            console.warn(`[api/call-invitations] send_push fallback failed invitation=${invitationId.slice(0, 8)} error=${pushError.message}`);
          } else {
            console.log(`[api/call-invitations] push fallback sent uid=${String(to_user_id).slice(0, 12)} invitation=${invitationId.slice(0, 8)}`);
          }
        } catch (pushError) {
          console.warn(`[api/call-invitations] send_push fallback exception invitation=${invitationId.slice(0, 8)} error=${String(pushError?.message || pushError)}`);
        }
      }
      res.json({ id: inserted.id, ws_delivered: wsDelivered });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/call-invitations/:id — 查询邀请状态 */
  app.get('/api/call-invitations/:id([0-9a-fA-F-]{36})', requireAuth, async (req, res) => {
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
      if (error) {
        console.warn('[api/call-invitations/ringing] query failed:', error.message);
        return res.json(null);
      }
      res.json(data);
    } catch (e) {
      console.warn('[api/call-invitations/ringing] exception:', String(e.message || e));
      res.json(null);
    }
  });

  /** PATCH /api/call-invitations/:id/status — 更新通话状态 */
  app.patch('/api/call-invitations/:id([0-9a-fA-F-]{36})/status', requireAuth, async (req, res) => {
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
