/**
 * 调用 Twelve Data API，需环境变量 TWELVE_DATA_API_KEY
 */
const TWELVE_BASE = 'https://api.twelvedata.com';

function toNum(v) {
  if (v == null) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** 单标的或批量 quote，返回 { symbol: { close, change, percent_change, open, high, low, volume? } } */
async function getQuotes(apiKey, symbols) {
  if (!symbols.length) return {};
  const list = symbols.map((s) => s.trim()).filter(Boolean);
  if (!list.length) return {};
  const url = `${TWELVE_BASE}/quote?symbol=${list.map((s) => encodeURIComponent(s)).join(',')}&apikey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (res.status !== 200) return {};
  const data = await res.json();
  const out = {};
  if (Array.isArray(data)) {
    for (const item of data) {
      const sym = item?.symbol;
      if (!sym) continue;
      if (item.code != null && item.code !== 200 && item.code !== 0) continue;
      out[sym] = {
        symbol: sym,
        close: toNum(item.close) ?? 0,
        change: toNum(item.change) ?? 0,
        percent_change: toNum(item.percent_change) ?? 0,
        open: toNum(item.open),
        high: toNum(item.high),
        low: toNum(item.low),
        volume: item.volume != null ? parseInt(item.volume, 10) : undefined,
      };
    }
    return out;
  }
  if (data?.code != null && data.code !== 200 && data.code !== 0) return {};
  const single = data?.symbol ? [data] : (data?.data && Array.isArray(data.data) ? data.data : []);
  for (const item of single) {
    const sym = item?.symbol || data?.symbol;
    if (!sym) continue;
    out[sym] = {
      symbol: sym,
      close: toNum(item.close ?? data.close) ?? 0,
      change: toNum(item.change ?? data.change) ?? 0,
      percent_change: toNum(item.percent_change ?? data.percent_change) ?? 0,
      open: toNum(item.open ?? data.open),
      high: toNum(item.high ?? data.high),
      low: toNum(item.low ?? data.low),
      volume: item?.volume != null ? parseInt(item.volume, 10) : undefined,
    };
  }
  return out;
}

/** K 线 time_series，返回 [{ t(ms), o, h, l, c, v }] */
async function getTimeSeries(apiKey, symbol, interval, outputsize = 120) {
  const url = `${TWELVE_BASE}/time_series?symbol=${encodeURIComponent(symbol)}&interval=${interval}&outputsize=${outputsize}&apikey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  const values = data?.values;
  if (!Array.isArray(values)) return [];
  return values.map((v) => {
    const dt = v.datetime;
    const ms = dt ? new Date(dt).getTime() : 0;
    return {
      t: ms,
      o: toNum(v.open) ?? 0,
      h: toNum(v.high) ?? 0,
      l: toNum(v.low) ?? 0,
      c: toNum(v.close) ?? 0,
      v: parseInt(v.volume, 10) || 0,
    };
  });
}

module.exports = { getQuotes, getTimeSeries };
