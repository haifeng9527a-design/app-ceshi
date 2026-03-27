/**
 * 列表报价缓存：内存 -> Supabase（若配置）-> SQLite；写回同时写内存 + SQLite + Supabase
 */
const db = require('./db');
const supabaseQuoteCache = require('./supabaseQuoteCache');
const { TTL_MS_BY_PRIORITY } = require('./config');

const MAX_AGE_FOR_SUPABASE_MS = 120000; // 与 P3 TTL 一致，Supabase 只拉 2 分钟内更新过的

/** 内存：symbol -> { payload, updatedAtMs } */
const memQuote = new Map();

/** 判定是否已过期（按 priority 对应 TTL） */
function isExpired(updatedAtMs, priority) {
  const ttl = TTL_MS_BY_PRIORITY[priority] ?? TTL_MS_BY_PRIORITY[3];
  return Date.now() - updatedAtMs > ttl;
}

/**
 * 批量取报价：先内存，再 Supabase（若配置），再 SQLite；返回 { hit: Map<symbol, payload>, miss: symbol[] }
 */
async function getQuotesBatch(symbols, metaMap) {
  const hit = new Map();
  const memMiss = [];
  for (const s of symbols) {
    const mem = memQuote.get(s);
    if (mem) {
      const pri = metaMap.get(s)?.priority ?? 3;
      if (!isExpired(mem.updatedAtMs, pri)) {
        hit.set(s, mem.payload);
        continue;
      }
    }
    memMiss.push(s);
  }
  if (memMiss.length === 0) return { hit, miss: [] };

  let remaining = memMiss;
  if (supabaseQuoteCache.isConfigured()) {
    const fromSupabase = await supabaseQuoteCache.getBySymbols(memMiss, MAX_AGE_FOR_SUPABASE_MS);
    for (const s of memMiss) {
      const row = fromSupabase.get(s);
      if (row) {
        const pri = metaMap.get(s)?.priority ?? 3;
        if (!isExpired(row.updated_at_ms, pri)) {
          hit.set(s, row.payload);
          memQuote.set(s, { payload: row.payload, updatedAtMs: row.updated_at_ms });
        }
      }
    }
    remaining = memMiss.filter((s) => !hit.has(s));
  }

  if (remaining.length > 0) {
    const fromDb = db.getQuoteSnapshotsBySymbols(remaining);
    for (const s of remaining) {
      const row = fromDb.get(s);
      if (row) {
        const pri = metaMap.get(s)?.priority ?? 3;
        if (!isExpired(row.updated_at_ms, pri)) {
          hit.set(s, row.payload);
          memQuote.set(s, { payload: row.payload, updatedAtMs: row.updated_at_ms });
        }
      }
    }
  }

  const miss = memMiss.filter((s) => !hit.has(s));
  return { hit, miss };
}

/**
 * 批量写回：更新内存 + SQLite + Supabase（若配置）
 * entries: { symbol, payload, priority? }[]
 */
function setQuotesBatch(entries) {
  const now = Date.now();
  for (const { symbol, payload, priority = 3 } of entries) {
    memQuote.set(symbol, { payload, updatedAtMs: now });
  }
  db.setQuoteSnapshotsBatch(entries);
  if (supabaseQuoteCache.isConfigured()) {
    supabaseQuoteCache.setBatch(entries).catch(() => {});
  }
}

/** 单条写（详情页 snapshot 写入后列表可复用） */
function setQuote(symbol, payload, priority = 0) {
  setQuotesBatch([{ symbol, payload, priority }]);
}

module.exports = {
  getQuotesBatch,
  setQuotesBatch,
  setQuote,
  isExpired,
};
