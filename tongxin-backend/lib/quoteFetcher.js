/**
 * 单只 Polygon 报价拉取，供 routes 与 refreshScheduler 复用
 */
const polygon = require('./polygon');
const db = require('./db');

function toQuoteSnapshot(q) {
  return {
    symbol: q.symbol,
    close: q.price,
    change: q.change,
    percent_change: q.changePercent,
    open: q.open != null ? q.open : null,
    high: q.high != null ? q.high : null,
    low: q.low != null ? q.low : null,
    volume: q.volume != null ? q.volume : null,
    bid: q.bid != null ? q.bid : null,
    ask: q.ask != null ? q.ask : null,
    bidSize: q.bidSize != null ? q.bidSize : null,
    askSize: q.askSize != null ? q.askSize : null,
    ...(q.error_reason && { error_reason: q.error_reason }),
  };
}

async function fetchOneQuote(polygonKey, original, polygonSym) {
  try {
    const q = await polygon.getTickerSnapshot(polygonKey, polygonSym);
    // 有结果就直接返回（含 error_reason 时也能看到「为什么空」）
    if (q) return toQuoteSnapshot({ ...q, symbol: original });
    const fallback = await polygon.getQuote(polygonKey, polygonSym);
    return toQuoteSnapshot({ ...fallback, symbol: original });
  } catch (e) {
    db.recordQuoteFetchFailure(original);
    return toQuoteSnapshot({
      symbol: original,
      price: 0,
      change: 0,
      changePercent: 0,
      error_reason: String(e.message || e),
    });
  }
}

module.exports = { toQuoteSnapshot, fetchOneQuote };
