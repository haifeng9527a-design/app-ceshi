/**
 * 后台管理员认证与账号管理
 * - POST /api/admin/auth/login：登录校验，密码错误 5 次锁定
 * - GET/POST/PATCH/DELETE /api/admin/accounts：管理员 CRUD
 * 所有接口需 x-admin-key 鉴权
 * 密码使用 bcrypt 哈希存储
 */
const bcrypt = require('bcrypt');
const supabaseClient = require('./supabaseClient');

const BCRYPT_ROUNDS = 10;
const MAX_FAILED_ATTEMPTS = 5;
const LOCK_DURATION_MS = 30 * 60 * 1000; // 30 分钟

function hashPassword(plainPassword) {
  return bcrypt.hashSync(plainPassword, BCRYPT_ROUNDS);
}

function verifyPassword(plainPassword, storedHash) {
  if (!storedHash || typeof storedHash !== 'string') return false;
  try {
    return bcrypt.compareSync(plainPassword, storedHash);
  } catch (_) {
    return false;
  }
}

function requireAdminKey(req, res, next) {
  const adminKey = process.env.ADMIN_API_KEY?.trim();
  const requestKey = (req.headers['x-admin-key'] || '').toString().trim();
  if (!adminKey || !requestKey || requestKey !== adminKey) {
    return res.status(401).json({ error: '缺少或无效的 x-admin-key' });
  }
  req.isAdminByKey = true;
  next();
}

function registerAdminAuthRoutes(app) {
  /** POST /api/admin/auth/bootstrap — 首次部署：若表为空则从 env 创建默认管理员 */
  app.post('/api/admin/auth/bootstrap', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const { count, error: countErr } = await sb.from('admin_users').select('*', { count: 'exact', head: true });
    if (countErr) return res.status(502).json({ error: countErr.message });
    if (count > 0) return res.json({ success: true, message: '已有管理员，跳过' });

    const username = (process.env.ADMIN_USERNAME || 'admin').toString().trim();
    const password = (process.env.ADMIN_PASSWORD || 'admin123').toString();
    if (!username || !password) return res.status(400).json({ error: '请配置 ADMIN_USERNAME 和 ADMIN_PASSWORD' });

    const passwordHash = hashPassword(password);
    const { data, error } = await sb
      .from('admin_users')
      .insert({ username, password_hash: passwordHash })
      .select('id, username')
      .single();

    if (error) return res.status(502).json({ error: error.message });
    return res.status(201).json({ success: true, admin: data });
  });

  /** POST /api/admin/auth/login — 管理员登录 */
  app.post('/api/admin/auth/login', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const username = (req.body?.username ?? '').toString().trim();
    const password = req.body?.password;
    if (!username || typeof password !== 'string') {
      return res.status(400).json({ error: '请提供账号和密码' });
    }

    const { data: row, error: fetchErr } = await sb
      .from('admin_users')
      .select('id, username, password_hash, failed_attempts, locked_until, permanently_locked')
      .eq('username', username)
      .maybeSingle();

    if (fetchErr) {
      return res.status(502).json({ error: fetchErr.message });
    }

    if (!row) {
      return res.status(401).json({ error: '账号或密码错误' });
    }

    if (row.permanently_locked === true) {
      return res.status(403).json({ error: '账户已被后台永久锁定' });
    }

    const now = new Date();
    const lockedUntil = row.locked_until ? new Date(row.locked_until) : null;
    if (lockedUntil && lockedUntil > now) {
      return res.status(403).json({
        error: '账户已锁定',
        locked_until: lockedUntil.toISOString(),
      });
    }

    if (!verifyPassword(password, row.password_hash)) {
      const failed = (row.failed_attempts || 0) + 1;
      const newLockedUntil = failed >= MAX_FAILED_ATTEMPTS ? new Date(now.getTime() + LOCK_DURATION_MS) : null;
      await sb
        .from('admin_users')
        .update({
          failed_attempts: failed,
          locked_until: newLockedUntil?.toISOString() ?? null,
          updated_at: now.toISOString(),
        })
        .eq('id', row.id);

      if (failed >= MAX_FAILED_ATTEMPTS) {
        return res.status(403).json({
          error: '密码错误次数过多，账户已锁定',
          locked_until: newLockedUntil.toISOString(),
        });
      }
      const remaining = MAX_FAILED_ATTEMPTS - failed;
      return res.status(401).json({ error: `账号或密码错误，剩余 ${remaining} 次尝试` });
    }

    // 登录成功：清除失败次数和锁定
    await sb
      .from('admin_users')
      .update({
        failed_attempts: 0,
        locked_until: null,
        updated_at: now.toISOString(),
      })
      .eq('id', row.id);

    return res.json({ success: true, username: row.username });
  });

  /** GET /api/admin/accounts — 管理员列表（不含密码） */
  app.get('/api/admin/accounts', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const { data, error } = await sb
      .from('admin_users')
      .select('id, username, failed_attempts, locked_until, permanently_locked, created_at, updated_at')
      .order('created_at', { ascending: false });

    if (error) return res.status(502).json({ error: error.message });
    return res.json(data || []);
  });

  /** POST /api/admin/accounts — 新增管理员 */
  app.post('/api/admin/accounts', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const username = (req.body?.username ?? '').toString().trim();
    const password = req.body?.password;
    if (!username || typeof password !== 'string' || password.length < 6) {
      return res.status(400).json({ error: '账号不能为空，密码至少 6 位' });
    }

    const passwordHash = hashPassword(password);
    const { data, error } = await sb
      .from('admin_users')
      .insert({
        username,
        password_hash: passwordHash,
        failed_attempts: 0,
        locked_until: null,
        permanently_locked: false,
      })
      .select('id, username, created_at')
      .single();

    if (error) {
      if (error.code === '23505') return res.status(409).json({ error: '该账号已存在' });
      return res.status(502).json({ error: error.message });
    }
    return res.status(201).json(data);
  });

  /** PATCH /api/admin/accounts/:id — 更新管理员（改密码、解锁） */
  app.patch('/api/admin/accounts/:id', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const id = req.params.id;
    if (!id) return res.status(400).json({ error: '缺少 id' });

    const updates = { updated_at: new Date().toISOString() };
    if (typeof req.body?.password === 'string' && req.body.password.length >= 6) {
      updates.password_hash = hashPassword(req.body.password);
    }
    if (req.body?.unlock === true) {
      updates.failed_attempts = 0;
      updates.locked_until = null;
    }
    const lockedVal = req.body?.locked;
    if (lockedVal === true || lockedVal === 'true') {
      updates.permanently_locked = true;
    } else if (lockedVal === false || lockedVal === 'false') {
      updates.permanently_locked = false;
    }

    if (Object.keys(updates).length <= 1) {
      return res.status(400).json({ error: '请提供 password、unlock: true 或 locked: true/false' });
    }

    const { data, error } = await sb
      .from('admin_users')
      .update(updates)
      .eq('id', id)
      .select('id, username, failed_attempts, locked_until, permanently_locked, updated_at')
      .single();

    if (error) return res.status(502).json({ error: error.message });
    if (!data) return res.status(404).json({ error: '管理员不存在' });
    return res.json(data);
  });

  /** DELETE /api/admin/accounts/:id — 删除管理员 */
  app.delete('/api/admin/accounts/:id', requireAdminKey, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: '数据库未配置' });

    const id = req.params.id;
    if (!id) return res.status(400).json({ error: '缺少 id' });

    const { error } = await sb.from('admin_users').delete().eq('id', id);
    if (error) return res.status(502).json({ error: error.message });
    return res.status(204).send();
  });
}

module.exports = { registerAdminAuthRoutes, hashPassword, verifyPassword };
