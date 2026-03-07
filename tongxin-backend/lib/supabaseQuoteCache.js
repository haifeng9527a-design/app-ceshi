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
  const close = row.close != null ? Number(row.close) : null;
  const prevClose = row.prev_close != null ? Number(row.prev_close) : null;
  const changeByPrev =
    close != null && prevClose != null && prevClose > 0 ? close - prevClose : null;
  const pctByPrev =
    changeByPrev != null && prevClose != null && prevClose > 0
      ? (changeByPrev / prevClose) * 100
      : null;
  return {
    symbol: row.symbol,
    close,
    change: changeByPrev ?? (row.change != null ? Number(row.change) : null),
    percent_change: pctByPrev ?? (row.percent_change != null ? Number(row.percent_change) : null),
    prev_close: prevClose,
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
        prev_close:
          p.prev_close != null
            ? p.prev_close
            : (close != null && change != null ? close - change : null),
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
 * 批量写入 symbol+name（无报价时也可写入，用于预填股票列表）
 * entries: [{ symbol, name }, ...]
 */
async function upsertSymbolsAndNames(entries) {
  const supabase = getClient();
  if (!supabase || !entries.length) return;
  const now = new Date().toISOString();
  const rows = entries
    .map((e) => {
      const symbol = (e.symbol || '').toUpperCase().trim();
      if (!symbol) return null;
      return {
        symbol,
        name: e.name ?? symbol,
        updated_at: now,
      };
    })
    .filter(Boolean);
  if (rows.length > 0) {
    await supabase.from(TABLE).upsert(rows, { onConflict: 'symbol' });
  }
}

/**
 * 批量写入实时成交价（仅更新 symbol/close/updated_at），避免覆盖 prev_close 等基准字段。
 * trades: [{ symbol, price }]
 */
async function setRealtimeTradesBatch(trades) {
  const supabase = getClient();
  if (!supabase || !Array.isArray(trades) || trades.length === 0) return;
  const now = new Date().toISOString();
  const rows = trades
    .map((t) => {
      const symbol = String(t.symbol || '').trim().toUpperCase();
      const price = Number(t.price);
      if (!symbol || !Number.isFinite(price) || price <= 0) return null;
      return {
        symbol,
        close: price,
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

function mapSortColumn(sortColumn) {
  switch (String(sortColumn || '').toLowerCase()) {
    case 'code':
      return 'symbol';
    case 'name':
      return 'name';
    case 'pct':
      return 'percent_change';
    case 'price':
      return 'close';
    case 'change':
      return 'change';
    case 'open':
      return 'open';
    case 'prev':
      return 'prev_close';
    case 'high':
      return 'high';
    case 'low':
      return 'low';
    case 'vol':
      return 'volume';
    default:
      return 'percent_change';
  }
}

/**
 * 分页读取 stock_quote_cache（含报价字段），支持排序和时效过滤。
 */
async function getTickersPageWithQuotes({
  page = 1,
  pageSize = 30,
  sortColumn = 'pct',
  sortAscending = false,
  maxAgeMs = 0,
} = {}) {
  const supabase = getClient();
  if (!supabase) {
    return { rows: [], total: 0, page: 1, pageSize: 30, hasMore: false };
  }
  const p = Math.max(1, Number(page || 1));
  const ps = Math.max(1, Math.min(200, Number(pageSize || 30)));
  const offset = (p - 1) * ps;
  const to = offset + ps - 1;
  const useAgeFilter = Number(maxAgeMs || 0) > 0;
  const since = useAgeFilter
    ? new Date(Date.now() - Math.max(1000, Number(maxAgeMs || 0))).toISOString()
    : null;
  const orderCol = mapSortColumn(sortColumn);
  const ascending = !!sortAscending;

  let baseQuery = supabase
    .from(TABLE)
    .select('id', { count: 'exact', head: true });
  if (useAgeFilter && since) {
    baseQuery = baseQuery.gte('updated_at', since);
  }
  const { count, error: countError } = await baseQuery;
  if (countError) {
    return { rows: [], total: 0, page: p, pageSize: ps, hasMore: false };
  }
  const total = Number(count || 0);
  if (total <= 0) {
    return { rows: [], total: 0, page: p, pageSize: ps, hasMore: false };
  }

  let dataQuery = supabase
    .from(TABLE)
    .select('symbol, name, close, change, percent_change, open, high, low, volume, prev_close, updated_at')
    .order(orderCol, { ascending, nullsFirst: false })
    .order('symbol', { ascending: true })
    .range(offset, to);
  if (useAgeFilter && since) {
    dataQuery = dataQuery.gte('updated_at', since);
  }
  const { data, error } = await dataQuery;
  if (error) {
    return { rows: [], total: 0, page: p, pageSize: ps, hasMore: false };
  }
  return {
    rows: data || [],
    total,
    page: p,
    pageSize: ps,
    hasMore: offset + (data?.length || 0) < total,
  };
}

module.exports = {
  isConfigured,
  getBySymbols,
  setBatch,
  setRealtimeTradesBatch,
  upsertSymbolsAndNames,
  getAllSymbolsAndNames,
  getTickersPageWithQuotes,
};
