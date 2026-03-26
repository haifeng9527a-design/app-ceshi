/**
 * 与前端 SymbolResolver 一致：决定用 Polygon 还是 Twelve Data、symbol 格式
 */
const POLYGON_INDICES = new Set(['SPX', 'NDX', 'DJI', 'IXIC', 'VIX', 'RUT', 'HSI', 'N225']);
const CRYPTO_BASES = new Set([
  'BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'AVAX', 'BNB', 'ADA', 'DOT',
  'MATIC', 'LINK', 'LTC', 'TRX', 'ATOM', 'UNI', 'USDT', 'USDC',
  'DAI', 'BCH', 'ETC', 'XLM', 'FIL', 'APT', 'ARB', 'OP',
]);

function isIndex(symbol) {
  return POLYGON_INDICES.has(String(symbol).trim().toUpperCase());
}

function isFx(symbol) {
  const s = String(symbol).trim().toUpperCase();
  if (s.includes('/')) return s.length >= 7 && !isCrypto(s);
  return s.length === 6 && /^[A-Z]+$/.test(s);
}

function isCrypto(symbol) {
  const s = String(symbol).trim();
  if (s.includes('/')) {
    const [base, quote] = s.toUpperCase().split('/');
    return CRYPTO_BASES.has(base) || CRYPTO_BASES.has(quote);
  }
  const u = s.toUpperCase();
  return CRYPTO_BASES.has(u) ||
    (u.endsWith('USD') && u.length >= 6);
}

function isUsStock(symbol) {
  const s = String(symbol).trim().toUpperCase();
  if (!s || s.length > 5 || s.includes('/')) return false;
  if (!/^[A-Z]+$/.test(s)) return false;
  return !POLYGON_INDICES.has(s);
}

function forPolygon(symbol) {
  const s = String(symbol).trim().toUpperCase();
  if (!s) return symbol;
  if (POLYGON_INDICES.has(s)) return `I:${s}`;
  return s;
}

function forTwelve(symbol) {
  const s = String(symbol).trim();
  if (!s) return s;
  if (s.includes('/')) return s;
  const u = s.toUpperCase();
  if (u.length === 6 && /^[A-Z]+$/.test(u))
    return `${u.slice(0, 3)}/${u.slice(3)}`;
  if (u === 'BTC' || u === 'ETH') return `${u}/USD`;
  return s;
}

/**
 * @returns {{ polygon: string, twelve: string, usePolygon: boolean, useTwelve: boolean }}
 */
function resolve(symbol) {
  const s = String(symbol).trim();
  const u = s.toUpperCase();
  if (!s) return { polygon: s, twelve: s, usePolygon: false, useTwelve: false };
  if (isUsStock(s)) return { polygon: u, twelve: s, usePolygon: true, useTwelve: false };
  if (isIndex(s)) return { polygon: `I:${u}`, twelve: u, usePolygon: true, useTwelve: true };
  if (isFx(s) || isCrypto(s)) return { polygon: '', twelve: forTwelve(s), usePolygon: false, useTwelve: true };
  return { polygon: u, twelve: forTwelve(s), usePolygon: true, useTwelve: true };
}

module.exports = { resolve, forPolygon, forTwelve, isUsStock, isIndex, isFx, isCrypto };
