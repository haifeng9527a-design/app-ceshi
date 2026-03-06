/**
 * Supabase 外汇缓存：写入 forex_pair_cache / forex_quote_cache
 * 环境变量：SUPABASE_URL、SUPABASE_SERVICE_ROLE_KEY（或 SUPABASE_ANON_KEY）
 */
const supabaseClient = require('./supabaseClient');

const PAIRS_TABLE = 'forex_pair_cache';
const QUOTES_TABLE = 'forex_quote_cache';
const UPSERT_CHUNK = 500;

function isConfigured() {
  return supabaseClient.isConfigured();
}

async function upsertForexPairs(pairs) {
  const sb = supabaseClient.getClient();
  if (!sb || !pairs?.length) return;
  const now = Date.now();
  const rows = [];
  for (const p of pairs) {
    const symbol = String(p?.symbol || '').trim();
    if (!symbol) continue;
    rows.push({
      symbol,
      name: String(p?.name || symbol).trim() || symbol,
      market: 'forex',
      updated_at_ms: now,
    });
  }
  if (!rows.length) return;
  for (let i = 0; i < rows.length; i += UPSERT_CHUNK) {
    const chunk = rows.slice(i, i + UPSERT_CHUNK);
    await sb.from(PAIRS_TABLE).upsert(chunk, { onConflict: 'symbol' });
  }
}

async function setForexQuotesBatch(entries) {
  const sb = supabaseClient.getClient();
  if (!sb || !entries?.length) return;
  const now = Date.now();
  const quoteRows = [];
  const touchRows = [];
  for (const e of entries) {
    const symbol = String(e?.symbol || '').trim();
    const payload = e?.payload;
    if (!symbol || !payload || typeof payload !== 'object') continue;
    quoteRows.push({
      symbol,
      payload_json: payload,
      updated_at_ms: now,
    });
    touchRows.push({
      symbol,
      last_quote_at_ms: now,
      updated_at_ms: now,
      market: 'forex',
      name: symbol,
    });
  }
  if (!quoteRows.length) return;
  for (let i = 0; i < quoteRows.length; i += UPSERT_CHUNK) {
    const chunk = quoteRows.slice(i, i + UPSERT_CHUNK);
    await sb.from(QUOTES_TABLE).upsert(chunk, { onConflict: 'symbol' });
  }
  for (let i = 0; i < touchRows.length; i += UPSERT_CHUNK) {
    const chunk = touchRows.slice(i, i + UPSERT_CHUNK);
    await sb.from(PAIRS_TABLE).upsert(chunk, { onConflict: 'symbol' });
  }
}

async function getForexPairsCount() {
  const sb = supabaseClient.getClient();
  if (!sb) return 0;
  const { count, error } = await sb
    .from(PAIRS_TABLE)
    .select('symbol', { count: 'exact', head: true });
  if (error) return 0;
  return Number(count || 0);
}

async function getForexSymbolsBatch(offset, limit) {
  const sb = supabaseClient.getClient();
  if (!sb) return [];
  const start = Math.max(0, Number(offset || 0));
  const size = Math.max(0, Number(limit || 0));
  if (size <= 0) return [];
  const end = start + size - 1;
  const { data, error } = await sb
    .from(PAIRS_TABLE)
    .select('symbol')
    .order('symbol', { ascending: true })
    .range(start, end);
  if (error || !Array.isArray(data)) return [];
  return data
    .map((r) => String(r?.symbol || '').trim())
    .filter(Boolean);
}

async function getForexPairsPage(page, pageSize) {
  const sb = supabaseClient.getClient();
  const p = Math.max(1, Number(page || 1));
  const ps = Math.max(1, Number(pageSize || 30));
  if (!sb) {
    return { rows: [], total: 0, page: p, pageSize: ps, hasMore: false };
  }
  const from = (p - 1) * ps;
  const to = from + ps - 1;
  const { data, count, error } = await sb
    .from(PAIRS_TABLE)
    .select('symbol,name,market', { count: 'exact' })
    .order('symbol', { ascending: true })
    .range(from, to);
  if (error) {
    return { rows: [], total: 0, page: p, pageSize: ps, hasMore: false };
  }
  const rows = Array.isArray(data) ? data : [];
  const total = Number(count || 0);
  return {
    rows,
    total,
    page: p,
    pageSize: ps,
    hasMore: from + rows.length < total,
  };
}

async function getForexQuotesBySymbols(symbols) {
  const sb = supabaseClient.getClient();
  const list = [...new Set((symbols || []).map((s) => String(s || '').trim()).filter(Boolean))];
  if (!sb || list.length === 0) return new Map();
  const { data, error } = await sb
    .from(QUOTES_TABLE)
    .select('symbol,payload_json,updated_at_ms')
    .in('symbol', list);
  if (error || !Array.isArray(data)) return new Map();
  const out = new Map();
  for (const row of data) {
    const symbol = String(row?.symbol || '').trim();
    if (!symbol) continue;
    out.set(symbol, {
      payload: row?.payload_json && typeof row.payload_json === 'object'
        ? row.payload_json
        : null,
      updated_at_ms: Number(row?.updated_at_ms || 0),
    });
  }
  return out;
}

module.exports = {
  isConfigured,
  upsertForexPairs,
  setForexQuotesBatch,
  getForexPairsCount,
  getForexSymbolsBatch,
  getForexPairsPage,
  getForexQuotesBySymbols,
};
