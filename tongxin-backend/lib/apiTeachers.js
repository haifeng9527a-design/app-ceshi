/**
 * 交易员相关 API：/api/teachers/*
 * 由 backend 代理 Supabase teacher_profiles、trade_strategies、teacher_comments、teacher_follows 等
 */
const supabaseClient = require('./supabaseClient');

function registerTeacherRoutes(app, requireAuth, optionalAuth) {
  const supabase = () => supabaseClient.getClient();
  if (!supabase()) {
    console.warn('[apiTeachers] Supabase 未配置，交易员接口不可用');
    return;
  }

  /** GET /api/teachers — 交易员列表（已通过） */
  app.get('/api/teachers', optionalAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('teacher_profiles').select('*').neq('status', 'blocked').order('pnl_month', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/rankings — 排行榜（已通过、按本月盈亏降序） */
  app.get('/api/teachers/rankings', optionalAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('teacher_profiles').select('*').eq('status', 'approved').order('pnl_month', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/rank-one — 排名第一的交易员 */
  app.get('/api/teachers/rank-one', optionalAuth, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('teacher_profiles').select('*').eq('status', 'approved').order('pnl_month', { ascending: false }).limit(1).maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      res.json(data);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId — 单个交易员 profile */
  app.get('/api/teachers/:userId', optionalAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: tp, error: e1 } = await sb.from('teacher_profiles').select('*').eq('user_id', userId).maybeSingle();
      if (e1) return res.status(502).json({ error: e1.message });
      if (!tp) return res.json(null);
      const { data: up } = await sb.from('user_profiles').select('signature').eq('user_id', userId).maybeSingle();
      const out = { ...tp };
      if (up?.signature != null) out.signature = up.signature;
      res.json(out);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId/strategies — 策略列表 */
  app.get('/api/teachers/:userId/strategies', optionalAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('trade_strategies').select('*').eq('teacher_id', userId).order('created_at', { ascending: false });
      if (error) {
        console.warn('[api/teachers/:userId/strategies] trade_strategies 查询失败:', error.message);
        return res.status(502).json({ error: error.message });
      }
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId/comments — 评论列表（strategy_id 可选，不传则查交易员级评论） */
  app.get('/api/teachers/:userId/comments', optionalAuth, async (req, res) => {
    const { userId } = req.params;
    const strategyId = req.query.strategy_id;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      let q = sb.from('teacher_comments').select('*').eq('teacher_id', userId).order('comment_time', { ascending: false });
      if (strategyId) q = q.eq('strategy_id', strategyId);
      else q = q.is('strategy_id', null);
      const { data, error } = await q;
      if (error) return res.status(502).json({ error: error.message });
      res.json(data || []);
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/teachers/:userId/comments — 发表评论 */
  app.post('/api/teachers/:userId/comments', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { userId } = req.params;
    const { content, strategy_id, reply_to_comment_id, reply_to_content } = req.body || {};
    if (!userId || !content?.trim()) return res.status(400).json({ error: 'missing userId or content' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: profile } = await sb.from('user_profiles').select('display_name, avatar_url').eq('user_id', uid).maybeSingle();
      const row = {
        teacher_id: userId,
        user_id: uid,
        user_name: profile?.display_name || '用户',
        avatar_url: profile?.avatar_url || null,
        content: content.trim(),
        strategy_id: strategy_id || null,
        reply_to_comment_id: reply_to_comment_id || null,
        reply_to_content: reply_to_content ? (reply_to_content.length > 50 ? reply_to_content.substring(0, 50) + '…' : reply_to_content) : null,
      };
      const { data: inserted, error } = await sb.from('teacher_comments').insert(row).select('id').single();
      if (error) return res.status(502).json({ error: error.message });
      res.json({ id: inserted.id, user_name: row.user_name });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId/follow-status — 是否已关注 */
  app.get('/api/teachers/:userId/follow-status', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data } = await sb.from('teacher_follows').select('id').eq('teacher_id', userId).eq('user_id', uid).maybeSingle();
      res.json({ is_following: !!data });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/teachers/:userId/follow — 关注 */
  app.post('/api/teachers/:userId/follow', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await sb.from('teacher_follows').insert({ teacher_id: userId, user_id: uid });
      res.json({ ok: true });
    } catch (e) {
      if (String(e.message || e).includes('duplicate') || String(e.message || e).includes('unique')) return res.json({ ok: true });
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/teachers/:userId/follow — 取消关注 */
  app.delete('/api/teachers/:userId/follow', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await sb.from('teacher_follows').delete().eq('teacher_id', userId).eq('user_id', uid);
      res.json({ ok: true });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId/follower-count — 粉丝数 */
  app.get('/api/teachers/:userId/follower-count', optionalAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('teacher_follows').select('id').eq('teacher_id', userId);
      if (error) return res.status(502).json({ error: error.message });
      res.json({ count: (data || []).length });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/users/:userId/followed-teachers — 当前用户关注的交易员 ID 列表 */
  app.get('/api/users/me/followed-teachers', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('teacher_follows').select('teacher_id').eq('user_id', uid).order('created_at', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      res.json((data || []).map(r => r.teacher_id).filter(Boolean));
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerTeacherRoutes };
