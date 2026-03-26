/**
 * 消息/会话相关 API：/api/conversations/*、/api/messages/*
 * 由 backend 代理 Supabase chat_*
 */
const supabaseClient = require('./supabaseClient');
const restrictionGuard = require('./restrictionGuard');
const { triggerChatMessagePush } = require('./chatPush');
const { broadcastNewMessage } = require('./chatWebSocket');

function registerMessageRoutes(app, requireAuth) {
  const supabase = () => supabaseClient.getClient();
  if (!supabase()) {
    console.warn('[apiMessages] Supabase 未配置，消息接口不可用');
    return;
  }

  async function insertMessageAndBroadcast(sb, row, { push = false } = {}) {
    const { data: inserted, error } = await sb
      .from('chat_messages')
      .insert(row)
      .select('*')
      .single();
    if (error) throw new Error(error.message);
    broadcastNewMessage(inserted);
    if (push) {
      triggerChatMessagePush(sb, inserted).catch((e) => {
        console.warn(
          `[apiMessages] send_push failed conv=${row?.conversation_id?.slice?.(0, 8) || '-'} error=${e?.message || e}`,
        );
      });
    }
    return inserted;
  }

  async function getConversationMemberRole(sb, conversationId, uid) {
    const { data, error } = await sb
      .from('chat_members')
      .select('role')
      .eq('conversation_id', conversationId)
      .eq('user_id', uid)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.role || null;
  }

  async function ensureConversationMember(res, sb, conversationId, uid) {
    const role = await getConversationMemberRole(sb, conversationId, uid);
    if (!role) {
      res.status(403).json({ error: 'not member' });
      return null;
    }
    return role;
  }

  /** GET /api/conversations — 会话列表 */
  app.get('/api/conversations', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) {
      console.warn('[api/conversations] 401 未鉴权');
      return res.status(401).json({ error: '未鉴权' });
    }
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: memberRows, error: e1 } = await sb.from('chat_members').select('conversation_id, unread_count').eq('user_id', uid);
      if (e1) {
        console.warn('[api/conversations] chat_members 查询失败:', e1.message);
        return res.status(502).json({ error: e1.message });
      }
      if (!memberRows?.length) return res.json([]);
      const unreadMap = Object.fromEntries(memberRows.map(r => [r.conversation_id, r.unread_count || 0]));
      const convIds = memberRows.map(r => r.conversation_id).filter(Boolean);
      const { data: allMembers } = await sb.from('chat_members').select('conversation_id, user_id').in('conversation_id', convIds);
      const peerMap = {};
      for (const r of allMembers || []) {
        if (r.user_id !== uid) peerMap[r.conversation_id] = r.user_id;
      }
      const { data: convos, error: e2 } = await sb.from('chat_conversations').select('*').in('id', convIds).order('last_time', { ascending: false });
      if (e2) return res.status(502).json({ error: e2.message });
      const list = (convos || []).map(c => {
        const type = c.type || 'direct';
        return { ...c, unread_count: unreadMap[c.id] || 0, peer_id: type === 'direct' ? peerMap[c.id] : null };
      });
      res.json(list);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/conversations/unread-count — 总未读数 */
  app.get('/api/conversations/unread-count', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('chat_members').select('unread_count').eq('user_id', uid);
      if (error) return res.status(502).json({ error: error.message });
      const total = (data || []).reduce((s, r) => s + (r.unread_count || 0), 0);
      res.json({ count: total });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/conversations/:id — 单个会话详情 */
  app.get('/api/conversations/:id', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const memberRole = await ensureConversationMember(res, sb, id, uid);
      if (!memberRole) return;
      const { data: convo, error: e1 } = await sb.from('chat_conversations').select('*').eq('id', id).maybeSingle();
      if (e1) return res.status(502).json({ error: e1.message });
      if (!convo) return res.json(null);
      const { data: members } = await sb.from('chat_members').select('user_id, unread_count').eq('conversation_id', id);
      let unreadCount = 0;
      let peerId = null;
      for (const m of members || []) {
        if (m.user_id === uid) unreadCount = m.unread_count || 0;
        else peerId = m.user_id;
      }
      res.json({ ...convo, unread_count: unreadCount, peer_id: (convo.type || 'direct') === 'direct' ? peerId : null });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/conversations/:id/messages — 消息列表 */
  app.get('/api/conversations/:id/messages', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
    const before = req.query.before; // 分页游标
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const memberRole = await ensureConversationMember(res, sb, id, uid);
      if (!memberRole) return;
      let query = sb.from('chat_messages').select('*').eq('conversation_id', id).order('created_at', { ascending: false }).limit(limit);
      if (before) query = query.lt('created_at', before);
      const { data, error } = await query;
      if (error) return res.status(502).json({ error: error.message });
      res.json((data || []).reverse());
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/messages — 发送消息 */
  app.post('/api/messages', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const body = req.body || {};
    const { conversation_id, content, message_type, media_url, duration_ms, reply_to_message_id, reply_to_sender_name, reply_to_content } = body;
    if (!conversation_id || content === undefined) return res.status(400).json({ error: 'missing conversation_id or content' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const memberRole = await ensureConversationMember(res, sb, conversation_id, uid);
      if (!memberRole) return;
      // 并行：权限校验 + 获取昵称，减少往返延迟
      const [gate, profileRes] = await Promise.all([
        restrictionGuard.assertActionAllowed(sb, uid, 'send_message'),
        sb.from('user_profiles').select('display_name').eq('user_id', uid).maybeSingle(),
      ]);
      if (!gate.allowed) return res.status(403).json({ error: gate.reason });
      const senderName = String(profileRes?.data?.display_name || '').trim() || '用户';
      const row = {
        conversation_id,
        sender_id: uid,
        sender_name: senderName,
        content: String(content || ''),
        message_type: message_type || 'text',
        media_url: media_url || null,
        duration_ms: duration_ms || null,
        reply_to_message_id: reply_to_message_id || null,
        reply_to_sender_name: reply_to_sender_name || null,
        reply_to_content: reply_to_content || null,
      };
      const inserted = await insertMessageAndBroadcast(sb, row, { push: true });
      res.json({ id: inserted.id, created_at: inserted.created_at });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/messages/:id */
  app.delete('/api/messages/:id', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: msg } = await sb.from('chat_messages').select('sender_id').eq('id', id).maybeSingle();
      if (!msg) return res.status(404).json({ error: 'message not found' });
      if (msg.sender_id !== uid) return res.status(403).json({ error: 'not sender' });
      await sb.from('chat_messages').delete().eq('id', id);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/conversations/:id/read — 标记已读 */
  app.patch('/api/conversations/:id/read', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const memberRole = await ensureConversationMember(res, sb, id, uid);
      if (!memberRole) return;
      await sb.from('chat_members').update({ unread_count: 0, last_read_at: new Date().toISOString() }).eq('conversation_id', id).eq('user_id', uid);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/chat-members/:conversationId — 获取会话成员（用于解析 peer_id） */
  app.get('/api/chat-members/:conversationId', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { conversationId } = req.params;
    if (!conversationId) return res.status(400).json({ error: 'missing conversationId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const memberRole = await ensureConversationMember(res, sb, conversationId, uid);
      if (!memberRole) return;
      const { data, error } = await sb.from('chat_members').select('user_id').eq('conversation_id', conversationId);
      if (error) return res.status(502).json({ error: error.message });
      const peerId = (data || []).find(m => m.user_id !== uid)?.user_id || null;
      res.json({ members: data || [], peer_id: peerId });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/conversations/direct?peer_id=xxx — 查找与某人的单聊会话 id（不创建） */
  app.get('/api/conversations/direct', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const peerId = req.query.peer_id?.trim();
    if (!peerId || peerId === uid) return res.json([]);
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: myRows } = await sb.from('chat_members').select('conversation_id').eq('user_id', uid);
      const myConvIds = (myRows || []).map(r => r.conversation_id).filter(Boolean);
      if (myConvIds.length === 0) return res.json([]);
      const { data: peerRows } = await sb.from('chat_members').select('conversation_id').eq('user_id', peerId).in('conversation_id', myConvIds);
      const shared = (peerRows || []).map(r => r.conversation_id).filter(Boolean);
      if (shared.length === 0) return res.json([]);
      const { data: convos } = await sb.from('chat_conversations').select('id, type').in('id', shared);
      const directIds = (convos || []).filter(c => c.type === 'direct').map(c => c.id);
      res.json(directIds);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/conversations/direct — 创建或获取单聊 */
  app.post('/api/conversations/direct', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { peer_id } = req.body || {};
    if (!peer_id) return res.status(400).json({ error: 'missing peer_id' });
    if (uid === peer_id) return res.status(400).json({ error: 'cannot chat with self' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const gate = await restrictionGuard.assertActionAllowed(sb, uid, 'send_message');
      if (!gate.allowed) return res.status(403).json({ error: gate.reason });
      const { data: myRows } = await sb.from('chat_members').select('conversation_id').eq('user_id', uid);
      const myConvIds = (myRows || []).map(r => r.conversation_id);
      if (myConvIds.length === 0) {
        const { data: conv } = await sb.from('chat_conversations').insert({ type: 'direct' }).select('id').single();
        await sb.from('chat_members').insert([{ conversation_id: conv.id, user_id: uid, role: 'member' }, { conversation_id: conv.id, user_id: peer_id, role: 'member' }]);
        return res.json({ id: conv.id, created: true });
      }
      const { data: peerRows } = await sb.from('chat_members').select('conversation_id').eq('user_id', peer_id).in('conversation_id', myConvIds);
      const shared = (peerRows || []).map(r => r.conversation_id);
      if (shared.length > 0) {
        const { data: conv } = await sb.from('chat_conversations').select('id, type').eq('id', shared[0]).single();
        if (conv?.type === 'direct') return res.json({ id: conv.id, created: false });
      }
      const { data: conv } = await sb.from('chat_conversations').insert({ type: 'direct' }).select('id').single();
      await sb.from('chat_members').insert([{ conversation_id: conv.id, user_id: uid, role: 'member' }, { conversation_id: conv.id, user_id: peer_id, role: 'member' }]);
      res.json({ id: conv.id, created: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/conversations/group — 创建群聊 */
  app.post('/api/conversations/group', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { title, member_user_ids } = req.body || {};
    if (!Array.isArray(member_user_ids) || member_user_ids.length === 0) return res.status(400).json({ error: 'member_user_ids required' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const gate = await restrictionGuard.assertActionAllowed(sb, uid, 'create_group');
      if (!gate.allowed) return res.status(403).json({ error: gate.reason });
      const { data: profile } = await sb.from('user_profiles').select('display_name').eq('user_id', uid).maybeSingle();
      const groupTitle = (title || '').trim() || `Group(${member_user_ids.length + 1})`;
      const allIds = [...new Set([uid, ...member_user_ids])];
      const { data: conv } = await sb.from('chat_conversations').insert({ type: 'group', title: groupTitle }).select('id').single();
      const memberRows = allIds.map(userId => ({ conversation_id: conv.id, user_id: userId, role: userId === uid ? 'owner' : 'member' }));
      await sb.from('chat_members').insert(memberRows);
      res.json({ id: conv.id, title: groupTitle });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/conversations/:id/members/me — 退出会话（群聊时插入退群系统消息） */
  app.delete('/api/conversations/:id/members/me', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    const leaveUserName = req.query.leave_user_name || req.body?.leave_user_name;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const memberRole = await ensureConversationMember(res, sb, id, uid);
      if (!memberRole) return;
      const { data: convo } = await sb.from('chat_conversations').select('type').eq('id', id).maybeSingle();
      if (convo?.type === 'group') {
        const name = (leaveUserName || '某用户').toString().trim();
        const { data: profile } = await sb.from('user_profiles').select('display_name').eq('user_id', uid).maybeSingle();
        const senderName = profile?.display_name || name;
        await insertMessageAndBroadcast(sb, {
          conversation_id: id,
          sender_id: uid,
          sender_name: senderName,
          content: `${name} 退出了群聊`,
          message_type: 'system_leave',
        });
      }
      await sb.from('chat_members').delete().eq('conversation_id', id).eq('user_id', uid);
      const { data: remaining } = await sb.from('chat_members').select('user_id').eq('conversation_id', id);
      if (!remaining?.length) await sb.from('chat_conversations').delete().eq('id', id);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/conversations/:id/messages — 清空会话内所有消息 */
  app.delete('/api/conversations/:id/messages', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: member } = await sb.from('chat_members').select('role').eq('conversation_id', id).eq('user_id', uid).maybeSingle();
      if (!member) return res.status(403).json({ error: 'not member' });
      await sb.from('chat_messages').delete().eq('conversation_id', id);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/conversations/:id/members — 邀请入群 */
  app.post('/api/conversations/:id/members', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    const { user_ids, user_id_to_display_name } = req.body || {};
    if (!id || !Array.isArray(user_ids) || user_ids.length === 0) return res.status(400).json({ error: 'missing id or user_ids' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const myRole = await ensureConversationMember(res, sb, id, uid);
      if (!myRole) return;
      if (!['owner', 'admin'].includes(myRole)) return res.status(403).json({ error: 'forbidden' });
      const gate = await restrictionGuard.assertActionAllowed(sb, uid, 'join_group');
      if (!gate.allowed) return res.status(403).json({ error: gate.reason });
      const { data: existing } = await sb.from('chat_members').select('user_id').eq('conversation_id', id);
      const existingIds = new Set((existing || []).map(r => r.user_id));
      const toAdd = user_ids.filter(uid2 => !existingIds.has(uid2));
      if (toAdd.length === 0) return res.json({ ok: true });
      const nameMap = user_id_to_display_name || {};
      await sb.from('chat_members').insert(toAdd.map(userId => ({ conversation_id: id, user_id: userId, role: 'member' })));
      for (const userId of toAdd) {
        const name = (nameMap[userId] || '新成员').trim();
        const { data: profile } = await sb.from('user_profiles').select('display_name').eq('user_id', userId).maybeSingle();
        const senderName = profile?.display_name || name;
        await insertMessageAndBroadcast(sb, {
          conversation_id: id,
          sender_id: userId,
          sender_name: senderName,
          content: `${name} 加入了群聊`,
          message_type: 'system_join',
        });
      }
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/conversations/:id/members/:userId — 移除群成员 */
  app.delete('/api/conversations/:id/members/:userId', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id, userId } = req.params;
    const leaveUserName = req.query.leave_user_name || req.body?.leave_user_name;
    if (!id || !userId) return res.status(400).json({ error: 'missing id or userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const myRole = await ensureConversationMember(res, sb, id, uid);
      if (!myRole) return;
      if (!['owner', 'admin'].includes(myRole)) return res.status(403).json({ error: 'forbidden' });
      await sb.from('chat_members').delete().eq('conversation_id', id).eq('user_id', userId);
      const name = (leaveUserName || '某用户').toString().trim();
      const { data: profile } = await sb.from('user_profiles').select('display_name').eq('user_id', userId).maybeSingle();
      await insertMessageAndBroadcast(sb, {
        conversation_id: id,
        sender_id: userId,
        sender_name: profile?.display_name || name,
        content: `${name} 退出了群聊`,
        message_type: 'system_leave',
      });
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/conversations/:id/members/:userId/role — 更新成员角色 */
  app.patch('/api/conversations/:id/members/:userId/role', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id, userId } = req.params;
    const { role } = req.body || {};
    if (!id || !userId || !['owner', 'admin', 'member'].includes(role)) return res.status(400).json({ error: 'invalid' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const myRole = await ensureConversationMember(res, sb, id, uid);
      if (!myRole) return;
      if (myRole !== 'owner') return res.status(403).json({ error: 'only owner can change role' });
      await sb.from('chat_members').update({ role }).eq('conversation_id', id).eq('user_id', userId);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/conversations/:id/transfer-ownership — 转让群主 */
  app.post('/api/conversations/:id/transfer-ownership', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    const { target_user_id } = req.body || {};
    if (!id || !target_user_id) return res.status(400).json({ error: 'missing target_user_id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const myRole = await ensureConversationMember(res, sb, id, uid);
      if (!myRole) return;
      if (myRole !== 'owner') return res.status(403).json({ error: 'only owner can transfer ownership' });
      const targetRole = await getConversationMemberRole(sb, id, target_user_id);
      if (!targetRole) return res.status(400).json({ error: 'target is not a member' });
      await sb.from('chat_members').update({ role: 'admin' }).eq('conversation_id', id).eq('user_id', uid);
      await sb.from('chat_members').update({ role: 'owner' }).eq('conversation_id', id).eq('user_id', target_user_id);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/conversations/:id — 解散群聊 */
  app.delete('/api/conversations/:id', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const myRole = await ensureConversationMember(res, sb, id, uid);
      if (!myRole) return;
      if (myRole !== 'owner') return res.status(403).json({ error: 'only owner can delete conversation' });
      await sb.from('chat_conversations').delete().eq('id', id);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/conversations/:id — 更新群资料 */
  app.patch('/api/conversations/:id', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    const { title, announcement, avatar_url } = req.body || {};
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const myRole = await ensureConversationMember(res, sb, id, uid);
      if (!myRole) return;
      if (!['owner', 'admin'].includes(myRole)) return res.status(403).json({ error: 'forbidden' });
      const updates = {};
      if (title != null) updates.title = title;
      if (announcement != null) updates.announcement = announcement;
      if (avatar_url != null) updates.avatar_url = avatar_url;
      if (Object.keys(updates).length === 0) return res.json({ ok: true });
      updates.updated_at = new Date().toISOString();
      await sb.from('chat_conversations').update(updates).eq('id', id);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/conversations/:id/group-info — 群资料与成员 */
  app.get('/api/conversations/:id/group-info', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { id } = req.params;
    if (!id) return res.status(400).json({ error: 'missing id' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const memberRole = await ensureConversationMember(res, sb, id, uid);
      if (!memberRole) return;
      const { data: convo } = await sb.from('chat_conversations').select('*').eq('id', id).maybeSingle();
      if (!convo || convo.type !== 'group') return res.json(null);
      const { data: members } = await sb.from('chat_members').select('user_id, role').eq('conversation_id', id);
      const memberIds = (members || []).map(m => m.user_id).filter(Boolean);
      let profiles = [];
      if (memberIds.length > 0) {
        const { data: p } = await sb.from('user_profiles').select('user_id, display_name, avatar_url, short_id').in('user_id', memberIds);
        profiles = p || [];
      }
      const profileMap = Object.fromEntries(profiles.map(p => [p.user_id, p]));
      const memberList = (members || []).map(m => {
        const p = profileMap[m.user_id];
        return { user_id: m.user_id, role: m.role, display_name: p?.display_name, avatar_url: p?.avatar_url, short_id: p?.short_id };
      });
      const myRole = (members || []).find(m => m.user_id === uid)?.role || 'member';
      res.json({ conversation_id: id, title: convo.title, announcement: convo.announcement, avatar_url: convo.avatar_url, created_by: convo.created_by, member_count: memberList.length, my_role: myRole, members: memberList });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerMessageRoutes };
