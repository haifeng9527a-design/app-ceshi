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
  // 批量 quote 常见结构：{ "EUR/USD": {...}, "USD/JPY": {...} }
  if (data && !Array.isArray(data) && typeof data === 'object' && data.data == null && data.symbol == null) {
    let parsedAny = false;
    for (const [sym, item] of Object.entries(data)) {
      if (!sym || !item || typeof item !== 'object') continue;
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
      parsedAny = true;
    }
    if (parsedAny) return out;
  }
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

/** 获取外汇交易对列表，返回 [{ symbol, name, market: 'forex' }] */
async function getForexPairs(apiKey) {
  const url = `${TWELVE_BASE}/forex_pairs?apikey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  if (data?.code != null && data.code !== 200 && data.code !== 0) return [];
  const rows = Array.isArray(data?.data) ? data.data : [];
  const out = [];
  const seen = new Set();
  for (const row of rows) {
    if (!row || typeof row !== 'object') continue;
    const symbol = String(row.symbol || '').trim();
    if (!symbol || !symbol.includes('/')) continue;
    if (seen.has(symbol)) continue;
    const rowName = String(row.name || '').trim();
    const base = String(row.currency_base || '').trim();
    const quote = String(row.currency_quote || '').trim();
    const name = rowName || ((base && quote) ? `${base}/${quote}` : symbol);
    out.push({ symbol, name, market: 'forex' });
    seen.add(symbol);
  }
  out.sort((a, b) => a.symbol.localeCompare(b.symbol));
  return out;
}

/** 获取加密货币交易对列表，返回 [{ symbol, name, market: 'crypto' }] */
async function getCryptoPairs(apiKey) {
  const url = `${TWELVE_BASE}/cryptocurrencies?apikey=${apiKey}`;
  const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (res.status !== 200) return [];
  const data = await res.json();
  if (data?.code != null && data.code !== 200 && data.code !== 0) return [];
  const rows = Array.isArray(data?.data) ? data.data : [];
  const out = [];
  const seen = new Set();
  for (const row of rows) {
    if (!row || typeof row !== 'object') continue;
    const symbol = String(row.symbol || '').trim();
    if (!symbol || !symbol.includes('/')) continue;
    if (seen.has(symbol)) continue;
    const rowName = String(row.name || '').trim();
    const base = String(row.currency_base || '').trim();
    const quote = String(row.currency_quote || '').trim();
    const name = rowName || ((base && quote) ? `${base}/${quote}` : symbol);
    out.push({ symbol, name, market: 'crypto' });
    seen.add(symbol);
  }
  out.sort((a, b) => a.symbol.localeCompare(b.symbol));
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
  const rows = values.map((v) => {
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
  // Twelve Data 常返回“最新在前”，统一转换为“时间升序”以匹配图表组件习惯（最后一根=最新）。
  rows.sort((a, b) => a.t - b.t);
  return rows;
}

module.exports = { getQuotes, getTimeSeries, getForexPairs, getCryptoPairs };
