const binance = require('./binance');
const { toQuoteSnapshot } = require('./quoteFetcher');
const supabaseCryptoCache = require('./supabaseCryptoCache');

const CRYPTO_METADATA_REFRESH_MS = Math.max(
  5 * 60 * 1000,
  parseInt(process.env.CRYPTO_METADATA_REFRESH_MS || `${60 * 60 * 1000}`, 10),
);
const CRYPTO_QUOTES_REFRESH_MS = Math.max(
  60 * 1000,
  parseInt(process.env.CRYPTO_QUOTES_REFRESH_MS || `${5 * 60 * 1000}`, 10),
);
const CRYPTO_QUOTES_BATCH_SIZE = Math.max(1, Math.min(parseInt(process.env.CRYPTO_QUOTES_BATCH_SIZE || '80', 10), 100));
const CRYPTO_CHUNK_DELAY_MS = Math.max(0, parseInt(process.env.CRYPTO_CHUNK_DELAY_MS || '120', 10));

let pairsTimer = null;
let quotesTimer = null;
let refreshingPairs = false;
let refreshingQuotes = false;

function chunkArray(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) {
    out.push(list.slice(i, i + size));
  }
  return out;
}

async function refreshCryptoPairs() {
  if (refreshingPairs || !supabaseCryptoCache.isConfigured()) return;
  refreshingPairs = true;
  try {
    const pairs = await binance.getTradingPairs();
    if (pairs.length > 0) {
      await supabaseCryptoCache.upsertCryptoPairs(pairs);
      console.log(`[cryptoScheduler] refreshed crypto pairs from Binance: ${pairs.length}`);
    }
  } catch (e) {
    console.warn('[cryptoScheduler] refreshCryptoPairs failed:', String(e?.message || e));
  } finally {
    refreshingPairs = false;
  }
}

async function refreshAllCryptoQuotes() {
  if (refreshingQuotes || !supabaseCryptoCache.isConfigured()) return;
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
      const binanceSymbols = symbols.map((sym) => binance.toBinanceSymbol(sym)).filter(Boolean);
      const liveMap = await binance.getQuotes(binanceSymbols);
      const entries = [];
      for (const sym of symbols) {
        const live = liveMap.get(binance.toBinanceSymbol(sym));
        if (!live || !(live.price > 0)) continue;
        entries.push({ symbol: sym, payload: toQuoteSnapshot({ ...live, symbol: sym, source: 'binance' }) });
      }
      if (entries.length > 0) {
        await supabaseCryptoCache.setCryptoQuotesBatch(entries);
        written += entries.length;
      }
      if (offset < total && CRYPTO_CHUNK_DELAY_MS > 0) {
        await new Promise((resolve) => setTimeout(resolve, CRYPTO_CHUNK_DELAY_MS));
      }
    }
    console.log(`[cryptoScheduler] refreshed crypto quotes from Binance: ${written}/${total}`);
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

function startCryptoScheduler() {
  if (!supabaseCryptoCache.isConfigured()) {
    console.warn('[cryptoScheduler] Supabase 未配置，加密货币调度器未启动');
    return;
  }
  if (!pairsTimer) {
    refreshCryptoPairs().catch(() => {});
    pairsTimer = setInterval(() => {
      refreshCryptoPairs().catch(() => {});
    }, CRYPTO_METADATA_REFRESH_MS);
  }
  if (!quotesTimer) {
    refreshAllCryptoQuotes().catch(() => {});
    quotesTimer = setInterval(() => {
      refreshAllCryptoQuotes().catch(() => {});
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
