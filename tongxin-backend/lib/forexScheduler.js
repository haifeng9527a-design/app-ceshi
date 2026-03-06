const twelveData = require('./twelveData');
const supabaseForexCache = require('./supabaseForexCache');

const FOREX_PAIRS_REFRESH_MS = 6 * 60 * 60 * 1000; // 6h
const FOREX_ROTATION_TICK_MS = 3000; // 3s
const FOREX_ROTATION_BATCH_SIZE = 80;

let pairsTimer = null;
let quotesTimer = null;
let cursor = 0;
let refreshingPairs = false;
let refreshingQuotes = false;

function toQuoteSnapshot(symbol, q) {
  return {
    symbol,
    close: q.close ?? 0,
    change: q.change ?? 0,
    percent_change: q.percent_change ?? 0,
    open: q.open ?? null,
    high: q.high ?? null,
    low: q.low ?? null,
    volume: q.volume ?? null,
  };
}

async function refreshForexPairs(apiKey) {
  if (!apiKey || refreshingPairs || !supabaseForexCache.isConfigured()) return;
  refreshingPairs = true;
  try {
    const pairs = await twelveData.getForexPairs(apiKey);
    if (pairs.length > 0) {
      await supabaseForexCache.upsertForexPairs(pairs);
      // 列表更新后避免游标越界
      const total = await supabaseForexCache.getForexPairsCount();
      if (cursor >= total) cursor = 0;
    }
  } catch (e) {
    console.warn('[forexScheduler] refreshForexPairs failed:', String(e?.message || e));
  } finally {
    refreshingPairs = false;
  }
}

async function refreshForexQuotesTick(apiKey) {
  if (!apiKey || refreshingQuotes || !supabaseForexCache.isConfigured()) return;
  refreshingQuotes = true;
  try {
    const total = await supabaseForexCache.getForexPairsCount();
    if (total <= 0) return;
    if (cursor >= total) cursor = 0;
    const symbols = await supabaseForexCache.getForexSymbolsBatch(
      cursor,
      FOREX_ROTATION_BATCH_SIZE,
    );
    cursor += symbols.length;
    if (cursor >= total) cursor = 0;
    if (symbols.length === 0) return;
    const map = await twelveData.getQuotes(apiKey, symbols);
    const entries = [];
    for (const sym of symbols) {
      const q = map[sym];
      if (!q || !(q.close > 0)) continue;
      entries.push({ symbol: sym, payload: toQuoteSnapshot(sym, q) });
    }
    if (entries.length > 0) {
      await supabaseForexCache.setForexQuotesBatch(entries);
    }
  } catch (e) {
    console.warn('[forexScheduler] refreshForexQuotesTick failed:', String(e?.message || e));
  } finally {
    refreshingQuotes = false;
  }
}

async function getForexQuotesFromCache(symbols) {
  const normalized = [...new Set((symbols || []).map((s) => String(s || '').trim()).filter(Boolean))];
  if (normalized.length === 0) return {};
  if (!supabaseForexCache.isConfigured()) return {};

  const fromDb = await supabaseForexCache.getForexQuotesBySymbols(normalized);
  const out = {};
  for (const s of normalized) {
    const row = fromDb.get(s);
    if (row?.payload) out[s] = row.payload;
  }
  return out;
}

function startForexScheduler(apiKey) {
  if (!apiKey) return;
  if (!supabaseForexCache.isConfigured()) {
    console.warn('[forexScheduler] Supabase 未配置，外汇调度器未启动');
    return;
  }
  if (!pairsTimer) {
    refreshForexPairs(apiKey).catch(() => {});
    pairsTimer = setInterval(() => {
      refreshForexPairs(apiKey).catch(() => {});
    }, FOREX_PAIRS_REFRESH_MS);
  }
  if (!quotesTimer) {
    // 先预热一批，避免服务刚启动全空
    refreshForexQuotesTick(apiKey).catch(() => {});
    quotesTimer = setInterval(() => {
      refreshForexQuotesTick(apiKey).catch(() => {});
    }, FOREX_ROTATION_TICK_MS);
  }
}

function stopForexScheduler() {
  if (pairsTimer) {
    clearInterval(pairsTimer);
    pairsTimer = null;
  }
  if (quotesTimer) {
    clearInterval(quotesTimer);
    quotesTimer = null;
  }
}

module.exports = {
  startForexScheduler,
  stopForexScheduler,
  getForexQuotesFromCache,
};
