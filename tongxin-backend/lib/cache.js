/**
 * 内存 + SQLite 双层缓存：内存命中即返；未命中时可用 DB 中的旧数据先返，再异步刷新
 */
const db = require('./db');
const cache = new Map();

const DEFAULT_TTL_MS = {
  quote: 15 * 1000,      // 15s
  candles: 2 * 60 * 1000, // 2min
  gainers: 5 * 60 * 1000, // 5min
  losers: 5 * 60 * 1000,
  search: 5 * 60 * 1000,
  ratios: 10 * 60 * 1000,   // 10min
  dividends: 60 * 60 * 1000, // 1h
  splits: 60 * 60 * 1000,   // 1h
  news: 5 * 60 * 1000,      // 5min
};

function get(key) {
  const ent = cache.get(key);
  if (!ent || Date.now() > ent.expires) return undefined;
  return ent.value;
}

/** 先查内存，再查 DB（不校验 TTL），用于启动时无空白：有旧数据先展示 */
function getOrStale(key) {
  const mem = get(key);
  if (mem !== undefined) return mem;
  return db.getStale(key);
}

function set(key, value, ttlMs = DEFAULT_TTL_MS.quote) {
  cache.set(key, { value, expires: Date.now() + ttlMs });
  db.setStale(key, value);
}

module.exports = { get, getOrStale, set, DEFAULT_TTL_MS };
