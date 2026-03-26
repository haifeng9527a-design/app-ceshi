const twelveData = require('./twelveData');
const supabaseForexCache = require('./supabaseForexCache');

const FOREX_METADATA_REFRESH_MS = Math.max(
  5 * 60 * 1000,
  parseInt(process.env.FOREX_METADATA_REFRESH_MS || `${60 * 60 * 1000}`, 10),
);
const FOREX_QUOTES_REFRESH_MS = Math.max(
  5 * 60 * 1000,
  parseInt(process.env.FOREX_QUOTES_REFRESH_MS || `${60 * 60 * 1000}`, 10),
);
const FOREX_QUOTES_BATCH_SIZE = Math.max(1, parseInt(process.env.FOREX_QUOTES_BATCH_SIZE || '80', 10));
const FOREX_CHUNK_DELAY_MS = Math.max(0, parseInt(process.env.FOREX_CHUNK_DELAY_MS || '120', 10));

let pairsTimer = null;
let quotesTimer = null;
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
      console.log(`[forexScheduler] refreshed forex pairs: ${pairs.length}`);
    }
  } catch (e) {
    console.warn('[forexScheduler] refreshForexPairs failed:', String(e?.message || e));
  } finally {
    refreshingPairs = false;
  }
}

async function refreshAllForexQuotes(apiKey) {
  if (!apiKey || refreshingQuotes || !supabaseForexCache.isConfigured()) return;
  refreshingQuotes = true;
  try {
    const total = await supabaseForexCache.getForexPairsCount();
    if (total <= 0) return;
    let offset = 0;
    let written = 0;
    while (offset < total) {
      const symbols = await supabaseForexCache.getForexSymbolsBatch(offset, FOREX_QUOTES_BATCH_SIZE);
      if (symbols.length === 0) break;
      offset += symbols.length;
      const map = await twelveData.getQuotes(apiKey, symbols);
      const entries = [];
      for (const sym of symbols) {
        const q = map[sym];
        if (!q || !(q.close > 0)) continue;
        entries.push({ symbol: sym, payload: toQuoteSnapshot(sym, q) });
      }
      if (entries.length > 0) {
        await supabaseForexCache.setForexQuotesBatch(entries);
        written += entries.length;
      }
      if (offset < total && FOREX_CHUNK_DELAY_MS > 0) {
        await new Promise((resolve) => setTimeout(resolve, FOREX_CHUNK_DELAY_MS));
      }
    }
    console.log(`[forexScheduler] refreshed forex quotes: ${written}/${total}`);
  } catch (e) {
    console.warn('[forexScheduler] refreshAllForexQuotes failed:', String(e?.message || e));
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
    }, FOREX_METADATA_REFRESH_MS);
  }
  if (!quotesTimer) {
    // 启动后立即做一次全量快照，避免缓存全空
    refreshAllForexQuotes(apiKey).catch(() => {});
    quotesTimer = setInterval(() => {
      refreshAllForexQuotes(apiKey).catch(() => {});
    }, FOREX_QUOTES_REFRESH_MS);
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
  refreshForexPairs,
  refreshAllForexQuotes,
};
