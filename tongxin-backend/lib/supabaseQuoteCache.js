/**
 * Supabase 股票报价缓存：读/写 stock_quote_cache 表（平铺列：序列号、代码、名称、最新价、开盘价等）
 * 环境变量：SUPABASE_URL、SUPABASE_ANON_KEY（或 SUPABASE_SERVICE_ROLE_KEY）
 */
const { createClient } = require('@supabase/supabase-js');

const TABLE = 'stock_quote_cache';
let _client = null;

function getClient() {
  if (_client) return _client;
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() || process.env.SUPABASE_ANON_KEY?.trim();
  if (!url || !key) return null;
  _client = createClient(url, key);
  return _client;
}

function isConfigured() {
  return !!(process.env.SUPABASE_URL?.trim() && (process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() || process.env.SUPABASE_ANON_KEY?.trim()));
}

/** 把表的一行转成前端用的 payload（与 toQuoteSnapshot 结构一致） */
function rowToPayload(row) {
  return {
    symbol: row.symbol,
    close: row.close != null ? Number(row.close) : null,
    change: row.change != null ? Number(row.change) : null,
    percent_change: row.percent_change != null ? Number(row.percent_change) : null,
    open: row.open != null ? Number(row.open) : null,
    high: row.high != null ? Number(row.high) : null,
    low: row.low != null ? Number(row.low) : null,
    volume: row.volume != null ? Number(row.volume) : null,
    ...(row.error_reason && { error_reason: row.error_reason }),
  };
}

/**
 * 批量读缓存：返回 Map<symbol, { payload, updated_at_ms }>，仅返回在 maxAgeMs 内更新过的
 */
async function getBySymbols(symbols, maxAgeMs = 120000) {
  const supabase = getClient();
  if (!supabase || !symbols.length) return new Map();
  const since = new Date(Date.now() - maxAgeMs).toISOString();
  const { data, error } = await supabase
    .from(TABLE)
    .select('id, symbol, name, close, change, percent_change, open, high, low, volume, prev_close, error_reason, updated_at')
    .in('symbol', symbols)
    .gte('updated_at', since);
  if (error) return new Map();
  const out = new Map();
  for (const row of data || []) {
    out.set(row.symbol, {
      payload: rowToPayload(row),
      updated_at_ms: row.updated_at ? new Date(row.updated_at).getTime() : 0,
    });
  }
  return out;
}

/**
 * 批量写缓存：把 payload 拆成列写入（symbol, name, close, change, percent_change, open, high, low, volume, prev_close, error_reason）
 */
async function setBatch(entries) {
  const supabase = getClient();
  if (!supabase || !entries.length) return;
  const now = new Date().toISOString();
  const rows = entries
    .map(({ symbol, payload }) => {
      const p = payload || {};
      const close = p.close != null ? p.close : null;
      const change = p.change != null ? p.change : null;
      const hasValidClose = close != null && Number(close) > 0;
      const hasError = p.error_reason && String(p.error_reason).trim().length > 0;
      // 只写入有有效价格或有错误原因的行情，不写入「静默全 0」行，避免表里一堆空数据
      if (!hasValidClose && !hasError) return null;
      return {
        symbol: (symbol || p.symbol || '').toUpperCase(),
        name: p.name ?? null,
        close,
        change,
        percent_change: p.percent_change != null ? p.percent_change : null,
        open: p.open != null ? p.open : null,
        high: p.high != null ? p.high : null,
        low: p.low != null ? p.low : null,
        volume: p.volume != null ? p.volume : null,
        prev_close: close != null && change != null ? close - change : null,
        error_reason: p.error_reason || null,
        updated_at: now,
      };
    })
    .filter(Boolean);
  if (rows.length > 0) {
    await supabase.from(TABLE).upsert(rows, { onConflict: 'symbol' });
  }
}

/**
 * 获取 stock_quote_cache 表中所有 symbol+name（24 小时内更新过的），用于美股列表秒开
 * 返回 [{ symbol, name }, ...]，按 symbol 排序
 */
async function getAllSymbolsAndNames(maxAgeMs = 24 * 60 * 60 * 1000) {
  const supabase = getClient();
  if (!supabase) return [];
  const since = new Date(Date.now() - maxAgeMs).toISOString();
  const { data, error } = await supabase
    .from(TABLE)
    .select('symbol, name')
    .gte('updated_at', since)
    .order('symbol');
  if (error) return [];
  return (data || []).map((row) => ({ symbol: row.symbol || '', name: row.name || row.symbol || '' }));
}

module.exports = {
  isConfigured,
  getBySymbols,
  setBatch,
  getAllSymbolsAndNames,
};
