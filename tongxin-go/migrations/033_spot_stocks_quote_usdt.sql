-- ═══════════════════════════════════════════════════════════
-- 033_spot_stocks_quote_usdt.sql
-- 把股票类现货交易对的计价资产从 USD 改成 USDT
--   - 与加密货币保持一致（账户里只维护 USDT 一个稳定币）
--   - 行情仍走 Polygon（AAPL/USD, AAPL/USDT 都会被 TrimSuffix 还原成 ticker "AAPL"）
-- ═══════════════════════════════════════════════════════════

BEGIN;

UPDATE spot_supported_symbols
SET
    symbol      = REPLACE(symbol, '/USD', '/USDT'),
    quote_asset = 'USDT'
WHERE category = 'stocks'
  AND quote_asset = 'USD';

COMMIT;
