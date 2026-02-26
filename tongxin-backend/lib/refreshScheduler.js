/**
 * 后台刷新：按 tick 从 meta_symbol 取到期 symbol，按优先级+预算拉取并写回
 */
const db = require('./db');
const quoteStore = require('./quoteStore');
const singleFlight = require('./singleFlight');
const rateLimiter = require('./rateLimiter');
const quoteFetcher = require('./quoteFetcher');
const { resolve } = require('./symbolResolver');
const { REFRESH_BUDGET_PER_TICK, REFRESH_TICK_MS } = require('./config');

let tickTimer = null;

function startRefreshScheduler(polygonKey) {
  if (!polygonKey || tickTimer) return;
  tickTimer = setInterval(async () => {
    try {
      const symbols = db.getEligibleSymbolsForRefresh(REFRESH_BUDGET_PER_TICK);
      if (symbols.length === 0) return;
      const entries = [];
      for (const sym of symbols) {
        const r = resolve(sym);
        if (!r.usePolygon) continue;
        await rateLimiter.acquire();
        const snap = await singleFlight.getOrInflight(`quote:${sym}`, () =>
          quoteFetcher.fetchOneQuote(polygonKey, sym, r.polygon)
        );
        entries.push({ symbol: sym, payload: snap, priority: 3 });
      }
      if (entries.length > 0) quoteStore.setQuotesBatch(entries);
    } catch (e) {
      // 静默忽略，避免影响主流程
    }
  }, REFRESH_TICK_MS);
}

function stopRefreshScheduler() {
  if (tickTimer) {
    clearInterval(tickTimer);
    tickTimer = null;
  }
}

module.exports = { startRefreshScheduler, stopRefreshScheduler };
