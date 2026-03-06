/**
 * SQLite：通用 key-value 表 + 列表用 quote_snapshot(symbol) + 调度用 meta_symbol
 */
const Database = require('better-sqlite3');
const { TTL_MS_BY_PRIORITY } = require('./config');
const path = require('path');
const fs = require('fs');

const dbPath = path.join(__dirname, '..', 'data', 'cache.db');
let db = null;

function getDb() {
  if (db) return db;
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.exec(`
    CREATE TABLE IF NOT EXISTS cache_store (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS quote_snapshot (
      symbol TEXT PRIMARY KEY,
      payload_json TEXT NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      market_ts_ms INTEGER,
      source TEXT DEFAULT 'polygon'
    );
    CREATE TABLE IF NOT EXISTS meta_symbol (
      symbol TEXT PRIMARY KEY,
      last_requested_at_ms INTEGER NOT NULL,
      priority INTEGER NOT NULL DEFAULT 3,
      last_refresh_at_ms INTEGER NOT NULL,
      fail_count INTEGER NOT NULL DEFAULT 0,
      next_eligible_refresh_ms INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS forex_pair_cache (
      symbol TEXT PRIMARY KEY,
      name TEXT,
      market TEXT DEFAULT 'forex',
      updated_at_ms INTEGER NOT NULL,
      last_quote_at_ms INTEGER
    );
    CREATE TABLE IF NOT EXISTS forex_quote_cache (
      symbol TEXT PRIMARY KEY,
      payload_json TEXT NOT NULL,
      updated_at_ms INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_forex_pair_updated ON forex_pair_cache(updated_at_ms);
    CREATE INDEX IF NOT EXISTS idx_forex_quote_updated ON forex_quote_cache(updated_at_ms);
  `);
  return db;
}

// ---------- 旧版通用缓存（gainers/losers/candles/search/ratios 等仍用） ----------
function getStale(key) {
  try {
    const row = getDb().prepare('SELECT value FROM cache_store WHERE key = ?').get(key);
    if (!row || !row.value) return undefined;
    return JSON.parse(row.value);
  } catch (e) {
    return undefined;
  }
}

function setStale(key, value) {
  try {
    const stmt = getDb().prepare('INSERT OR REPLACE INTO cache_store (key, value, updated_at) VALUES (?, ?, ?)');
    stmt.run(key, JSON.stringify(value), Date.now());
  } catch (e) {}
}

// ---------- 列表用：按 symbol 批量读 / 批量写 ----------
/** 批量查 quote_snapshot，返回 Map<symbol, { payload, updated_at_ms }> */
function getQuoteSnapshotsBySymbols(symbols) {
  if (!symbols.length) return new Map();
  try {
    const db = getDb();
    const placeholders = symbols.map(() => '?').join(',');
    const rows = db.prepare(
      `SELECT symbol, payload_json, updated_at_ms FROM quote_snapshot WHERE symbol IN (${placeholders})`
    ).all(...symbols);
    const out = new Map();
    for (const r of rows) {
      let payload;
      try {
        payload = JSON.parse(r.payload_json);
      } catch (_) {
        continue;
      }
      out.set(r.symbol, { payload, updated_at_ms: r.updated_at_ms });
    }
    return out;
  } catch (e) {
    return new Map();
  }
}

/** 批量 upsert quote_snapshot + 更新 meta_symbol（事务） */
function setQuoteSnapshotsBatch(entries) {
  if (!entries.length) return;
  try {
    const db = getDb();
    const now = Date.now();
    const insQuote = db.prepare(
      `INSERT INTO quote_snapshot (symbol, payload_json, updated_at_ms, market_ts_ms, source) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(symbol) DO UPDATE SET payload_json=excluded.payload_json, updated_at_ms=excluded.updated_at_ms, market_ts_ms=excluded.market_ts_ms, source=excluded.source`
    );
    const defaultTtl = TTL_MS_BY_PRIORITY[3] ?? 120000;
    const insMeta = db.prepare(`
      INSERT INTO meta_symbol (symbol, last_requested_at_ms, priority, last_refresh_at_ms, fail_count, next_eligible_refresh_ms)
      VALUES (?, ?, ?, ?, 0, ?)
      ON CONFLICT(symbol) DO UPDATE SET last_refresh_at_ms=excluded.last_refresh_at_ms, fail_count=0, next_eligible_refresh_ms=excluded.next_eligible_refresh_ms
    `);
    const trans = db.transaction(() => {
      for (const { symbol, payload, priority = 3 } of entries) {
        insQuote.run(symbol, JSON.stringify(payload), now, null, 'polygon');
        const ttl = TTL_MS_BY_PRIORITY[priority] ?? defaultTtl;
        insMeta.run(symbol, now, priority, now, now + ttl);
      }
    });
    trans();
  } catch (e) {}
}

/** 记录请求过的 symbol（last_requested_at + priority 至少为给定值） */
function touchMetaSymbols(symbols, priority = 2) {
  if (!symbols.length) return;
  try {
    const db = getDb();
    const now = Date.now();
    const stmt = db.prepare(`
      INSERT INTO meta_symbol (symbol, last_requested_at_ms, priority, last_refresh_at_ms, fail_count, next_eligible_refresh_ms)
      VALUES (?, ?, ?, ?, 0, ?)
      ON CONFLICT(symbol) DO UPDATE SET
        last_requested_at_ms = excluded.last_requested_at_ms,
        priority = MIN(meta_symbol.priority, excluded.priority)
    `);
    const trans = db.transaction(() => {
      for (const s of symbols) {
        stmt.run(s, now, priority, now, now);
      }
    });
    trans();
  } catch (e) {}
}

/** 查 meta 的 priority / last_refresh，用于 TTL 判定 */
function getMetaBySymbols(symbols) {
  if (!symbols.length) return new Map();
  try {
    const placeholders = symbols.map(() => '?').join(',');
    const rows = getDb().prepare(
      `SELECT symbol, priority, last_refresh_at_ms FROM meta_symbol WHERE symbol IN (${placeholders})`
    ).all(...symbols);
    const out = new Map();
    for (const r of rows) out.set(r.symbol, { priority: r.priority, last_refresh_at_ms: r.last_refresh_at_ms });
    return out;
  } catch (e) {
    return new Map();
  }
}

/** 调度用：取到期的 symbol，按 priority 升序、最近请求优先，limit 个 */
function getEligibleSymbolsForRefresh(limit) {
  try {
    const now = Date.now();
    const rows = getDb()
      .prepare(
        `SELECT symbol FROM meta_symbol WHERE next_eligible_refresh_ms <= ? ORDER BY priority ASC, last_requested_at_ms DESC LIMIT ?`
      )
      .all(now, limit);
    return rows.map((r) => r.symbol);
  } catch (e) {
    return [];
  }
}

/** 失败退避：更新 fail_count 与 next_eligible_refresh_ms */
function recordQuoteFetchFailure(symbol) {
  try {
    const d = getDb();
    const row = d.prepare('SELECT fail_count FROM meta_symbol WHERE symbol = ?').get(symbol);
    const failCount = (row?.fail_count ?? 0) + 1;
    const backoffMs = Math.min(1000 * Math.pow(2, failCount), 5 * 60 * 1000);
    const now = Date.now();
    const next = now + backoffMs;
    d.prepare(`
      INSERT INTO meta_symbol (symbol, last_requested_at_ms, priority, last_refresh_at_ms, fail_count, next_eligible_refresh_ms)
      VALUES (?, ?, 3, ?, ?, ?)
      ON CONFLICT(symbol) DO UPDATE SET fail_count=?, next_eligible_refresh_ms=?
    `).run(symbol, now, now, 0, failCount, next, failCount, next);
  } catch (e) {}
}

// ---------- Forex 缓存（服务端轮询） ----------
function upsertForexPairs(pairs) {
  if (!pairs?.length) return;
  try {
    const d = getDb();
    const now = Date.now();
    const stmt = d.prepare(`
      INSERT INTO forex_pair_cache (symbol, name, market, updated_at_ms, last_quote_at_ms)
      VALUES (?, ?, 'forex', ?, NULL)
      ON CONFLICT(symbol) DO UPDATE SET
        name=excluded.name,
        market='forex',
        updated_at_ms=excluded.updated_at_ms
    `);
    const trans = d.transaction(() => {
      for (const p of pairs) {
        const symbol = String(p.symbol || '').trim();
        if (!symbol) continue;
        const name = String(p.name || symbol).trim() || symbol;
        stmt.run(symbol, name, now);
      }
    });
    trans();
  } catch (_) {}
}

function getForexPairsPage(page = 1, pageSize = 120) {
  try {
    const d = getDb();
    const p = Math.max(1, parseInt(page, 10) || 1);
    const ps = Math.min(500, Math.max(1, parseInt(pageSize, 10) || 120));
    const offset = (p - 1) * ps;
    const totalRow = d.prepare('SELECT COUNT(*) AS c FROM forex_pair_cache').get();
    const total = Number(totalRow?.c || 0);
    const rows = d
      .prepare('SELECT symbol, name, market FROM forex_pair_cache ORDER BY symbol ASC LIMIT ? OFFSET ?')
      .all(ps, offset);
    return { rows, total, page: p, pageSize: ps, hasMore: offset + rows.length < total };
  } catch (_) {
    return { rows: [], total: 0, page: 1, pageSize: 120, hasMore: false };
  }
}

function getForexSymbolsBatch(offset = 0, limit = 120) {
  try {
    const d = getDb();
    const rows = d
      .prepare('SELECT symbol FROM forex_pair_cache ORDER BY symbol ASC LIMIT ? OFFSET ?')
      .all(Math.max(1, limit), Math.max(0, offset));
    return rows.map((r) => r.symbol).filter(Boolean);
  } catch (_) {
    return [];
  }
}

function getForexPairsCount() {
  try {
    const row = getDb().prepare('SELECT COUNT(*) AS c FROM forex_pair_cache').get();
    return Number(row?.c || 0);
  } catch (_) {
    return 0;
  }
}

function setForexQuotesBatch(entries) {
  if (!entries?.length) return;
  try {
    const d = getDb();
    const now = Date.now();
    const insQuote = d.prepare(`
      INSERT INTO forex_quote_cache (symbol, payload_json, updated_at_ms)
      VALUES (?, ?, ?)
      ON CONFLICT(symbol) DO UPDATE SET
        payload_json=excluded.payload_json,
        updated_at_ms=excluded.updated_at_ms
    `);
    const touchPair = d.prepare(`
      UPDATE forex_pair_cache
      SET last_quote_at_ms = ?
      WHERE symbol = ?
    `);
    const trans = d.transaction(() => {
      for (const { symbol, payload } of entries) {
        if (!symbol || !payload) continue;
        insQuote.run(symbol, JSON.stringify(payload), now);
        touchPair.run(now, symbol);
      }
    });
    trans();
  } catch (_) {}
}

function getForexQuotesBySymbols(symbols) {
  if (!symbols?.length) return new Map();
  try {
    const d = getDb();
    const placeholders = symbols.map(() => '?').join(',');
    const rows = d
      .prepare(`SELECT symbol, payload_json, updated_at_ms FROM forex_quote_cache WHERE symbol IN (${placeholders})`)
      .all(...symbols);
    const out = new Map();
    for (const r of rows) {
      try {
        out.set(r.symbol, { payload: JSON.parse(r.payload_json), updated_at_ms: r.updated_at_ms });
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return new Map();
  }
}

module.exports = {
  getDb,
  getStale,
  setStale,
  getQuoteSnapshotsBySymbols,
  setQuoteSnapshotsBatch,
  touchMetaSymbols,
  getMetaBySymbols,
  getEligibleSymbolsForRefresh,
  recordQuoteFetchFailure,
  upsertForexPairs,
  getForexPairsPage,
  getForexSymbolsBatch,
  getForexPairsCount,
  setForexQuotesBatch,
  getForexQuotesBySymbols,
};
