/**
 * 应用配置 app_config 管理 API
 * - GET /api/admin/config：列表
 * - POST /api/admin/config：新增/更新
 * - DELETE /api/admin/config/:key：删除
 * 所有接口需 x-admin-key 鉴权
 */
const supabaseClient = require('./supabaseClient');

function requireAdminKey(req, res, next) {
  const adminKey = process.env.ADMIN_API_KEY?.trim();
  const requestKey = (req.headers['x-admin-key'] || '').toString().trim();
  if (!adminKey || !requestKey || requestKey !== adminKey) {
    return res.status(401).json({ error: '缺少或无效的 x-admin-key' });
  }
  req.isAdminByKey = true;
  next();
}

function registerAdminConfigRoutes(app) {
  /** GET /api/admin/config — 获取全部 app_config */
  app.get('/api/admin/config', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const { data, error } = await sb
      .from('app_config')
      .select('key, value, remark, updated_at')
      .order('key', { ascending: true });

    if (error) return res.status(502).json({ error: error.message });
    return res.json(data || []);
  });

  /** POST /api/admin/config — 新增或更新配置 */
  app.post('/api/admin/config', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const key = (req.body?.key ?? '').toString().trim();
    const value = req.body?.value;
    if (!key) return res.status(400).json({ error: 'key 不能为空' });

    const val = value != null ? String(value) : null;
    const now = new Date().toISOString();

    const { data, error } = await sb
      .from('app_config')
      .upsert({ key, value: val, updated_at: now }, { onConflict: 'key' })
      .select('key, value, updated_at')
      .single();

    if (error) return res.status(502).json({ error: error.message });
    return res.json(data);
  });

  /** PATCH /api/admin/config/:key — 更新配置值 */
  app.patch('/api/admin/config/:key', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const key = (req.params.key ?? '').toString().trim();
    const value = req.body?.value;
    const remark = req.body?.remark;
    if (!key) return res.status(400).json({ error: 'key 不能为空' });

    const val = value != null ? String(value) : null;
    const remarkVal = remark != null ? String(remark).trim() || null : null;
    const now = new Date().toISOString();

    const updates = { key, value: val, updated_at: now };
    if (remark !== undefined) updates.remark = remarkVal;

    const { data, error } = await sb
      .from('app_config')
      .upsert(updates, { onConflict: 'key' })
      .select('key, value, remark, updated_at')
      .single();

    if (error) return res.status(502).json({ error: error.message });
    return res.json(data);
  });

  /** DELETE /api/admin/config/:key — 删除配置 */
  app.delete('/api/admin/config/:key', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const key = (req.params.key ?? '').toString().trim();
    if (!key) return res.status(400).json({ error: 'key 不能为空' });

    const { error } = await sb.from('app_config').delete().eq('key', key);
    if (error) return res.status(502).json({ error: error.message });
    return res.status(204).send();
  });
}

module.exports = { registerAdminConfigRoutes };
