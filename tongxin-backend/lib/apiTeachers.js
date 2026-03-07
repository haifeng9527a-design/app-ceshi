/**
 * 交易员相关 API：/api/teachers/*
 * 由 backend 代理 Supabase teacher_profiles、trade_strategies、teacher_comments、teacher_follows 等
 */
const supabaseClient = require('./supabaseClient');

function registerTeacherRoutes(app, requireAuth, optionalAuth) {
  const requireAdminRole = async (req, res, next) => {
    if (req.isAdminByKey === true) return next();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('user_profiles').select('role').eq('user_id', uid).maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      const role = String(data?.role || '').toLowerCase();
      if (role !== 'admin' && role !== 'customer_service_admin') {
        return res.status(403).json({ error: 'forbidden' });
      }
      return next();
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  };

  const supabase = () => supabaseClient.getClient();
  if (!supabase()) {
    console.warn('[apiTeachers] Supabase 未配置，交易员接口不可用');
    return;
  }

  /** GET /api/admin/teachers/profiles — 管理后台交易员资料列表 */
  app.get('/api/admin/teachers/profiles', requireAuth, requireAdminRole, async (req, res) => {
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb.from('teacher_profiles').select('*');
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PUT /api/admin/teachers/:userId/profile — 管理后台保存交易员资料 */
  app.put('/api/admin/teachers/:userId/profile', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const allowed = [
        'display_name', 'real_name', 'title', 'organization', 'bio', 'tags',
        'wins', 'losses', 'rating', 'today_strategy', 'pnl_current', 'pnl_month',
        'pnl_year', 'pnl_total', 'updated_at',
      ];
      const payload = { user_id: userId };
      for (const k of allowed) {
        if (body[k] !== undefined) payload[k] = body[k];
      }
      if (!payload.updated_at) payload.updated_at = new Date().toISOString();
      const { error } = await sb.from('teacher_profiles').upsert(payload, { onConflict: 'user_id' });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/admin/teachers/:userId/status — 管理后台更新交易员状态 */
  app.patch('/api/admin/teachers/:userId/status', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const { status, frozen_until } = req.body || {};
    if (!status) return res.status(400).json({ error: 'missing status' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const updates = {
        status: String(status).trim(),
        updated_at: new Date().toISOString(),
      };
      if (frozen_until !== undefined) updates.frozen_until = frozen_until;
      const { error } = await sb.from('teacher_profiles').update(updates).eq('user_id', userId);
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/admin/teachers/:userId/strategies */
  app.post('/api/admin/teachers/:userId/strategies', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const { title, summary, content, status } = req.body || {};
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { error } = await sb.from('trade_strategies').insert({
        teacher_id: userId,
        title: title || '',
        summary: summary || '',
        content: content || '',
        status: status || 'published',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/admin/teachers/:userId/trade-records */
  app.post('/api/admin/teachers/:userId/trade-records', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const payload = {
        teacher_id: userId,
        asset: body.asset || '',
        buy_time: body.buy_time || null,
        buy_shares: body.buy_shares ?? 0,
        buy_price: body.buy_price ?? 0,
        sell_time: body.sell_time || null,
        sell_shares: body.sell_shares ?? 0,
        sell_price: body.sell_price ?? 0,
        pnl_ratio: body.pnl_ratio ?? 0,
        pnl_amount: body.pnl_amount ?? 0,
        created_at: new Date().toISOString(),
      };
      const { error } = await sb.from('trade_records').insert(payload);
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/admin/teachers/:userId/positions */
  app.post('/api/admin/teachers/:userId/positions', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const payload = {
        teacher_id: userId,
        asset: body.asset || '',
        buy_time: body.buy_time || null,
        buy_shares: body.buy_shares ?? 0,
        buy_price: body.buy_price ?? 0,
        cost_price: body.cost_price ?? 0,
        current_price: body.current_price ?? 0,
        floating_pnl: body.floating_pnl ?? 0,
        pnl_ratio: body.pnl_ratio ?? 0,
        pnl_amount: body.pnl_amount ?? 0,
        is_history: body.is_history === true,
        sell_time: body.sell_time || null,
        sell_price: body.sell_price ?? null,
        created_at: new Date().toISOString(),
      };
      const { error } = await sb.from('teacher_positions').insert(payload);
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/admin/teachers/:userId/comments */
  app.post('/api/admin/teachers/:userId/comments', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const { error } = await sb.from('teacher_comments').insert({
        teacher_id: userId,
        user_name: body.user_name || '用户',
        content: body.content || '',
        comment_time: body.comment_time || null,
        created_at: new Date().toISOString(),
      });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/admin/teachers/:userId/articles */
  app.post('/api/admin/teachers/:userId/articles', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const { error } = await sb.from('teacher_articles').insert({
        teacher_id: userId,
        title: body.title || '',
        summary: body.summary || '',
        article_time: body.article_time || null,
        created_at: new Date().toISOString(),
      });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/admin/teachers/:userId/schedules */
  app.post('/api/admin/teachers/:userId/schedules', requireAuth, requireAdminRole, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const { error } = await sb.from('teacher_schedules').insert({
        teacher_id: userId,
        title: body.title || '',
        schedule_time: body.schedule_time || null,
        location: body.location || '',
        created_at: new Date().toISOString(),
      });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

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

  /** GET /api/teachers/:userId/likes/count — 点赞数 */
  app.get('/api/teachers/:userId/likes/count', optionalAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('teacher_strategy_likes')
        .select('teacher_id')
        .eq('teacher_id', userId);
      if (error) return res.status(502).json({ error: error.message });
      res.json({ count: (data || []).length });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId/likes/me — 当前用户是否已点赞 */
  app.get('/api/teachers/:userId/likes/me', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    const { userId } = req.params;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('teacher_strategy_likes')
        .select('teacher_id')
        .eq('teacher_id', userId)
        .eq('user_id', uid)
        .maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      res.json({ liked: !!data });
    } catch (e) {
      res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/teachers/:userId/likes/toggle — 点赞/取消点赞 */
  app.post('/api/teachers/:userId/likes/toggle', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    const { userId } = req.params;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data: existed, error: qErr } = await sb
        .from('teacher_strategy_likes')
        .select('teacher_id')
        .eq('teacher_id', userId)
        .eq('user_id', uid)
        .maybeSingle();
      if (qErr) return res.status(502).json({ error: qErr.message });
      if (existed) {
        const { error } = await sb
          .from('teacher_strategy_likes')
          .delete()
          .eq('teacher_id', userId)
          .eq('user_id', uid);
        if (error) return res.status(502).json({ error: error.message });
        return res.json({ liked: false });
      }
      const { error } = await sb.from('teacher_strategy_likes').insert({
        teacher_id: userId,
        user_id: uid,
        created_at: new Date().toISOString(),
      });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ liked: true });
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

  /** PUT /api/teachers/me/profile — 当前用户保存交易员资料 */
  app.put('/api/teachers/me/profile', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const allowed = [
        'display_name', 'real_name', 'title', 'organization', 'country', 'city',
        'years_experience', 'markets', 'instruments', 'certifications',
        'license_no', 'broker', 'track_record', 'application_ack', 'id_photo_url',
        'license_photo_url', 'certification_photo_url', 'bio', 'style',
        'risk_level', 'specialties', 'avatar_url', 'status', 'frozen_until',
        'tags', 'wins', 'losses', 'rating', 'today_strategy', 'pnl_current',
        'pnl_month', 'pnl_year', 'pnl_total',
      ];
      const payload = { user_id: uid, updated_at: new Date().toISOString() };
      for (const k of allowed) {
        if (body[k] !== undefined) payload[k] = body[k];
      }
      const { error } = await sb.from('teacher_profiles').upsert(payload, {
        onConflict: 'user_id',
      });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/teachers/me/strategies — 当前用户发布策略 */
  app.post('/api/teachers/me/strategies', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const { data, error } = await sb
        .from('trade_strategies')
        .insert({
          teacher_id: uid,
          title: body.title || '',
          summary: body.summary || '',
          content: body.content || '',
          image_urls: Array.isArray(body.image_urls) && body.image_urls.length > 0
            ? body.image_urls
            : null,
          status: body.status || 'published',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .select('*')
        .single();
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PATCH /api/teachers/strategies/:strategyId/status — 当前用户更新策略状态 */
  app.patch('/api/teachers/strategies/:strategyId/status', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    const { strategyId } = req.params;
    const status = String(req.body?.status || '').trim();
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!strategyId) return res.status(400).json({ error: 'missing strategyId' });
    if (!status) return res.status(400).json({ error: 'missing status' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('trade_strategies')
        .update({
          status,
          updated_at: new Date().toISOString(),
        })
        .eq('id', strategyId)
        .eq('teacher_id', uid)
        .select('*')
        .maybeSingle();
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || { ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId/trade-records — 交易记录 */
  app.get('/api/teachers/:userId/trade-records', optionalAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('trade_records')
        .select('*')
        .eq('teacher_id', userId)
        .order('trade_time', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** GET /api/teachers/:userId/positions — 当前/历史持仓 */
  app.get('/api/teachers/:userId/positions', optionalAuth, async (req, res) => {
    const { userId } = req.params;
    if (!userId) return res.status(400).json({ error: 'missing userId' });
    const history = String(req.query.history || '').trim().toLowerCase() === 'true';
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const { data, error } = await sb
        .from('teacher_positions')
        .select('*')
        .eq('teacher_id', userId)
        .eq('is_history', history)
        .order('created_at', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/teachers/me/trade-records — 当前用户新增交易记录 */
  app.post('/api/teachers/me/trade-records', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabase();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const body = req.body || {};
      const payload = {
        teacher_id: uid,
        symbol: body.symbol || body.asset || '',
        asset: body.asset || body.symbol || '',
        side: body.side || 'buy',
        pnl: body.pnl ?? body.pnl_amount ?? 0,
        pnl_amount: body.pnl_amount ?? body.pnl ?? 0,
        pnl_ratio: body.pnl_ratio ?? 0,
        buy_time: body.buy_time || null,
        buy_shares: body.buy_shares ?? null,
        buy_price: body.buy_price ?? null,
        sell_time: body.sell_time || null,
        sell_shares: body.sell_shares ?? null,
        sell_price: body.sell_price ?? null,
        trade_time: body.trade_time || body.sell_time || new Date().toISOString(),
        attachment_url: body.attachment_url || null,
        created_at: new Date().toISOString(),
      };
      const { data, error } = await sb.from('trade_records').insert(payload).select('*').single();
      if (error) return res.status(502).json({ error: error.message });
      if (payload.attachment_url) {
        await sb.from('trade_record_files').insert({
          teacher_id: uid,
          file_url: payload.attachment_url,
          file_type: 'image',
          created_at: new Date().toISOString(),
        });
      }
      return res.json(data);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
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
