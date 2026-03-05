/**
 * 自选股 API：登录用户维度的持久化存储
 * 存在 Supabase 表 public.user_watchlists（独立表，不再复用 app_config）
 */
const supabaseClient = require('./supabaseClient');

const WATCHLIST_TABLE = 'user_watchlists';
const MAX_WATCHLIST_SIZE = 500;

function normalizeSymbols(input) {
  if (!Array.isArray(input)) return [];
  const out = [];
  const seen = new Set();
  for (const item of input) {
    const s = String(item || '').trim().toUpperCase();
    if (!s || seen.has(s)) continue;
    seen.add(s);
    out.push(s);
    if (out.length >= MAX_WATCHLIST_SIZE) break;
  }
  return out;
}

async function getSymbols(sb, uid) {
  const { data, error } = await sb
    .from(WATCHLIST_TABLE)
    .select('symbol, sort_order, created_at')
    .eq('user_id', uid)
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: true });
  if (error) throw new Error(error.message || 'query failed');
  const list = (data || []).map((r) => String(r.symbol || '').trim().toUpperCase());
  return normalizeSymbols(list);
}

async function saveSymbols(sb, uid, symbols) {
  const list = normalizeSymbols(symbols);
  const { error: deleteError } = await sb
    .from(WATCHLIST_TABLE)
    .delete()
    .eq('user_id', uid);
  if (deleteError) throw new Error(deleteError.message || 'clear failed');
  if (list.length > 0) {
    const nowIso = new Date().toISOString();
    const rows = list.map((symbol, index) => ({
      user_id: uid,
      symbol,
      sort_order: index + 1,
      created_at: nowIso,
      updated_at: nowIso,
    }));
    const { error: insertError } = await sb
      .from(WATCHLIST_TABLE)
      .insert(rows);
    if (insertError) throw new Error(insertError.message || 'insert failed');
  }
  return list;
}

function registerWatchlistRoutes(app, requireAuth) {
  /** GET /api/watchlist */
  app.get('/api/watchlist', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const symbols = await getSymbols(sb, uid);
      return res.json({ symbols });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** PUT /api/watchlist body: { symbols: string[] } */
  app.put('/api/watchlist', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const symbols = req.body?.symbols;
    if (!Array.isArray(symbols)) {
      return res.status(400).json({ error: 'symbols must be an array' });
    }
    try {
      const saved = await saveSymbols(sb, uid, symbols);
      return res.json({ ok: true, symbols: saved });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** POST /api/watchlist body: { symbol: string } */
  app.post('/api/watchlist', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const symbol = String(req.body?.symbol || '').trim().toUpperCase();
    if (!symbol) return res.status(400).json({ error: 'missing symbol' });
    try {
      const list = await getSymbols(sb, uid);
      if (!list.includes(symbol)) list.push(symbol);
      const saved = await saveSymbols(sb, uid, list);
      return res.json({ ok: true, symbols: saved });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  /** DELETE /api/watchlist/:symbol */
  app.delete('/api/watchlist/:symbol', requireAuth, async (req, res) => {
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const symbol = String(req.params?.symbol || '').trim().toUpperCase();
    if (!symbol) return res.status(400).json({ error: 'missing symbol' });
    try {
      const list = await getSymbols(sb, uid);
      const next = list.filter((s) => s !== symbol);
      const saved = await saveSymbols(sb, uid, next);
      return res.json({ ok: true, symbols: saved });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerWatchlistRoutes };

