/**
 * 文件上传 API：/api/upload/*
 * 由 backend 代理 Supabase Storage，body 传 base64
 */
const supabaseClient = require('./supabaseClient');

function registerUploadRoutes(app, requireAuth) {
  const supabase = () => supabaseClient.getClient();
  if (!supabase()) {
    console.warn('[apiUpload] Supabase 未配置，上传接口不可用');
    return;
  }

  /** POST /api/upload/avatar — 上传头像，body: { content_base64, content_type?, file_name? } */
  app.post('/api/upload/avatar', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { content_base64, content_type, file_name } = req.body || {};
    if (!content_base64) return res.status(400).json({ error: 'missing content_base64' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const buf = Buffer.from(content_base64, 'base64');
      const ext = (file_name || '').split('.').pop()?.toLowerCase() || 'jpg';
      const safeExt = ['jpg', 'jpeg', 'png', 'webp'].includes(ext) ? ext : 'jpg';
      const path = `users/${uid}/${Date.now()}_avatar.${safeExt}`;
      const ct = content_type || `image/${safeExt === 'png' ? 'png' : safeExt === 'webp' ? 'webp' : 'jpeg'}`;
      const { error } = await sb.storage.from('avatars').upload(path, buf, { contentType: ct, upsert: true });
      if (error) return res.status(502).json({ error: error.message });
      const { data: urlData } = sb.storage.from('avatars').getPublicUrl(path);
      const url = urlData?.publicUrl || '';
      await sb.from('user_profiles').upsert({ user_id: uid, avatar_url: url, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
      res.json({ url });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/upload/report-screenshots — 上传举报截图，body: { items: [{ content_base64, content_type?, file_name? }] }，返回 urls 数组 */
  app.post('/api/upload/report-screenshots', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const items = req.body?.items;
    if (!Array.isArray(items) || items.length === 0 || items.length > 5) return res.status(400).json({ error: 'items 需为 1-5 个元素的数组' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const urls = [];
      const prefix = `reports/${uid}`;
      for (let i = 0; i < items.length; i++) {
        const { content_base64, content_type, file_name } = items[i] || {};
        if (!content_base64) continue;
        const buf = Buffer.from(content_base64, 'base64');
        const ext = (file_name || '').split('.').pop()?.toLowerCase() || 'jpg';
        const safeExt = ['jpg', 'jpeg', 'png', 'webp'].includes(ext) ? ext : 'jpg';
        const path = `${prefix}/${Date.now()}_${i}.${safeExt}`;
        const ct = content_type || `image/${safeExt === 'png' ? 'png' : safeExt === 'webp' ? 'webp' : 'jpeg'}`;
        const { error } = await sb.storage.from('avatars').upload(path, buf, { contentType: ct, upsert: true });
        if (error) continue;
        const { data: urlData } = sb.storage.from('avatars').getPublicUrl(path);
        urls.push(urlData?.publicUrl || '');
      }
      res.json({ urls });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/upload/group-avatar — 上传群头像，body: { conversation_id, content_base64, content_type? } */
  app.post('/api/upload/group-avatar', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { conversation_id, content_base64, content_type } = req.body || {};
    if (!conversation_id || !content_base64) return res.status(400).json({ error: 'missing conversation_id or content_base64' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const buf = Buffer.from(content_base64, 'base64');
      const path = `chat/${conversation_id}/group_avatar_${Date.now()}.jpg`;
      const ct = content_type || 'image/jpeg';
      const { error } = await sb.storage.from('chat-media').upload(path, buf, { contentType: ct, upsert: true });
      if (error) return res.status(502).json({ error: error.message });
      const { data: urlData } = sb.storage.from('chat-media').getPublicUrl(path);
      await sb.from('chat_conversations').update({ avatar_url: urlData?.publicUrl || '', updated_at: new Date().toISOString() }).eq('id', conversation_id);
      res.json({ url: urlData?.publicUrl || '' });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/upload/chat-media — 上传聊天媒体，body: { conversation_id, content_base64, content_type?, file_name? } */
  app.post('/api/upload/chat-media', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { conversation_id, content_base64, content_type, file_name } = req.body || {};
    if (!conversation_id || !content_base64) return res.status(400).json({ error: 'missing conversation_id or content_base64' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const buf = Buffer.from(content_base64, 'base64');
      const name = (file_name || 'file').replace(/\s/g, '_').replace(/[^\w.-]/g, '') || 'file';
      const path = `chat/${conversation_id}/${uid}/${Date.now()}_${name}`;
      const { error } = await sb.storage.from('chat-media').upload(path, buf, { contentType: content_type || 'application/octet-stream', upsert: true });
      if (error) return res.status(502).json({ error: error.message });
      const { data: urlData } = sb.storage.from('chat-media').getPublicUrl(path);
      res.json({ url: urlData?.publicUrl || '' });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerUploadRoutes };
