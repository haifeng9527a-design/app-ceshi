const twelveData = require('./twelveData');
const supabaseCryptoCache = require('./supabaseCryptoCache');

const CRYPTO_METADATA_REFRESH_MS = Math.max(
  5 * 60 * 1000,
  parseInt(process.env.CRYPTO_METADATA_REFRESH_MS || `${60 * 60 * 1000}`, 10),
);
const CRYPTO_QUOTES_REFRESH_MS = Math.max(
  5 * 60 * 1000,
  parseInt(process.env.CRYPTO_QUOTES_REFRESH_MS || `${60 * 60 * 1000}`, 10),
);
const CRYPTO_QUOTES_BATCH_SIZE = Math.max(1, parseInt(process.env.CRYPTO_QUOTES_BATCH_SIZE || '80', 10));
const CRYPTO_CHUNK_DELAY_MS = Math.max(0, parseInt(process.env.CRYPTO_CHUNK_DELAY_MS || '120', 10));

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

async function refreshCryptoPairs(apiKey) {
  if (!apiKey || refreshingPairs || !supabaseCryptoCache.isConfigured()) return;
  refreshingPairs = true;
  try {
    const pairs = await twelveData.getCryptoPairs(apiKey);
    if (pairs.length > 0) {
      await supabaseCryptoCache.upsertCryptoPairs(pairs);
      console.log(`[cryptoScheduler] refreshed crypto pairs: ${pairs.length}`);
    }
  } catch (e) {
    console.warn('[cryptoScheduler] refreshCryptoPairs failed:', String(e?.message || e));
  } finally {
    refreshingPairs = false;
  }
}

async function refreshAllCryptoQuotes(apiKey) {
  if (!apiKey || refreshingQuotes || !supabaseCryptoCache.isConfigured()) return;
  refreshingQuotes = true;
  try {
    const total = await supabaseCryptoCache.getCryptoPairsCount();
    if (total <= 0) return;
    let offset = 0;
    let written = 0;
    while (offset < total) {
      const symbols = await supabaseCryptoCache.getCryptoSymbolsBatch(offset, CRYPTO_QUOTES_BATCH_SIZE);
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
        await supabaseCryptoCache.setCryptoQuotesBatch(entries);
        written += entries.length;
      }
      if (offset < total && CRYPTO_CHUNK_DELAY_MS > 0) {
        await new Promise((resolve) => setTimeout(resolve, CRYPTO_CHUNK_DELAY_MS));
      }
    }
    console.log(`[cryptoScheduler] refreshed crypto quotes: ${written}/${total}`);
  } catch (e) {
    console.warn('[cryptoScheduler] refreshAllCryptoQuotes failed:', String(e?.message || e));
  } finally {
    refreshingQuotes = false;
  }
}

async function getCryptoQuotesFromCache(symbols) {
  const normalized = [...new Set((symbols || []).map((s) => String(s || '').trim()).filter(Boolean))];
  if (normalized.length === 0) return {};
  if (!supabaseCryptoCache.isConfigured()) return {};
  const fromDb = await supabaseCryptoCache.getCryptoQuotesBySymbols(normalized);
  const out = {};
  for (const s of normalized) {
    const row = fromDb.get(s);
    if (row?.payload) out[s] = row.payload;
  }
  return out;
}

function startCryptoScheduler(apiKey) {
  if (!apiKey) return;
  if (!supabaseCryptoCache.isConfigured()) {
    console.warn('[cryptoScheduler] Supabase 未配置，加密货币调度器未启动');
    return;
  }
  if (!pairsTimer) {
    refreshCryptoPairs(apiKey).catch(() => {});
    pairsTimer = setInterval(() => {
      refreshCryptoPairs(apiKey).catch(() => {});
    }, CRYPTO_METADATA_REFRESH_MS);
  }
  if (!quotesTimer) {
    refreshAllCryptoQuotes(apiKey).catch(() => {});
    quotesTimer = setInterval(() => {
      refreshAllCryptoQuotes(apiKey).catch(() => {});
    }, CRYPTO_QUOTES_REFRESH_MS);
  }
}

function stopCryptoScheduler() {
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
  startCryptoScheduler,
  stopCryptoScheduler,
  getCryptoQuotesFromCache,
  refreshCryptoPairs,
  refreshAllCryptoQuotes,
};
