/**
 * 单只 Polygon 报价拉取，供 routes 与 refreshScheduler 复用
 */
const polygon = require('./polygon');
const db = require('./db');

function toQuoteSnapshot(q) {
  const close = q.price != null ? Number(q.price) : 0;
  const prevCloseRaw = q.prevClose != null
    ? Number(q.prevClose)
    : (q.price != null && q.change != null ? Number(q.price) - Number(q.change) : null);
  const prevClose = Number.isFinite(prevCloseRaw) && prevCloseRaw > 0 ? prevCloseRaw : null;
  const changeRaw = q.change != null ? Number(q.change) : 0;
  const change = prevClose != null ? close - prevClose : changeRaw;
  const changePercent =
    prevClose != null && prevClose > 0
      ? (change / prevClose) * 100
      : (q.changePercent != null ? Number(q.changePercent) : 0);
  return {
    symbol: q.symbol,
    close,
    change,
    percent_change: Number.isFinite(changePercent) ? changePercent : 0,
    prev_close: prevClose,
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
    const [snapshot, quote, prevBar] = await Promise.all([
      polygon.getTickerSnapshot(polygonKey, polygonSym),
      polygon.getQuote(polygonKey, polygonSym),
      polygon.getPrevDayBar(polygonKey, polygonSym),
    ]);
    let q = snapshot ? { ...snapshot, symbol: original } : null;
    if (!q || !(q.price > 0)) {
      q = {
        symbol: original,
        price: quote?.price > 0 ? quote.price : (prevBar?.c || 0),
        change: quote?.change ?? 0,
        changePercent: quote?.changePercent ?? 0,
        prevClose: prevBar?.c ?? null,
        open: snapshot?.open ?? prevBar?.o ?? null,
        high: snapshot?.high ?? prevBar?.h ?? null,
        low: snapshot?.low ?? prevBar?.l ?? null,
        volume: snapshot?.volume ?? prevBar?.v ?? null,
        bid: quote?.bid ?? snapshot?.bid ?? null,
        ask: quote?.ask ?? snapshot?.ask ?? null,
        bidSize: quote?.bidSize ?? snapshot?.bidSize ?? null,
        askSize: quote?.askSize ?? snapshot?.askSize ?? null,
        ...(quote?.price > 0 || prevBar?.c > 0 ? {} : { error_reason: 'Polygon Snapshot 无当日/昨收数据' }),
      };
    }
    return toQuoteSnapshot(q);
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
