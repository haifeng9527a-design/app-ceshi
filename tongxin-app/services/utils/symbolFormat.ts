/**
 * Symbol display shims.
 *
 * Internally the codebase still stores crypto symbols as `BTC/USD`, `ETH/USD`,
 * etc. — that's the format the market-store / depth API / backend all use.
 * Product, however, wants users to see the industry-standard `BTC/USDT`.
 *
 * `toDisplaySymbol` is a pure rendering shim: it rewrites `<base>/USD` →
 * `<base>/USDT` for crypto bases, and leaves everything else alone (forex
 * pairs like `EUR/USD`, stocks like `AAPL`, futures like `ES`).
 *
 * The `/USD` vs `/USDT` ambiguity is resolved by checking the base against a
 * known set of fiat currency codes. Anything outside that set is treated as
 * crypto — so new crypto listings automatically get the USDT suffix without
 * having to maintain a crypto allow-list in sync with backend seeds.
 */

/** Fiat bases that legitimately pair with USD in the forex tab. */
const FIAT_BASES: ReadonlySet<string> = new Set([
  'EUR', 'GBP', 'AUD', 'NZD', 'CAD', 'CHF', 'JPY',
  'CNH', 'SGD', 'HKD', 'SEK', 'NOK', 'DKK',
  'MXN', 'ZAR', 'TRY', 'PLN', 'CZK', 'HUF',
  'RUB', 'INR', 'BRL', 'KRW', 'IDR', 'THB', 'PHP',
]);

/**
 * Convert a storage-format symbol to its UI display form.
 *
 *   BTC/USD   → BTC/USDT
 *   ETH/USD   → ETH/USDT
 *   EUR/USD   → EUR/USD      (forex — unchanged)
 *   AAPL      → AAPL         (stock — no quote)
 *   BTC/USDT  → BTC/USDT     (idempotent)
 */
export function toDisplaySymbol(sym: string | undefined | null): string {
  if (!sym) return '';
  if (!sym.includes('/')) return sym;
  if (!sym.endsWith('/USD')) return sym;
  const base = sym.split('/', 1)[0];
  if (FIAT_BASES.has(base)) return sym;
  return `${base}/USDT`;
}

/**
 * Convert a storage-format quote asset string to its UI display form.
 * Useful for "available balance in USDT" labels when the backend column
 * still returns `USD`.
 */
export function toDisplayQuote(quote: string | undefined | null): string {
  if (!quote) return '';
  return quote === 'USD' ? 'USDT' : quote;
}
