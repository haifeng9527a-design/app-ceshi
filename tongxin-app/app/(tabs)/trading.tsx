import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  Animated,
  Platform,
  useWindowDimensions,
  ActivityIndicator,
} from 'react-native';
import { Colors, Sizes } from '../../theme/colors';
import { useMarketStore } from '../../services/store/marketStore';
import { useAuthStore } from '../../services/store/authStore';
import { useTradingStore } from '../../services/store/tradingStore';
import { marketWs } from '../../services/websocket/marketWs';
import PositionCard from '../../components/trading/PositionCard';
import ClosedPositionCard from '../../components/trading/ClosedPositionCard';
import OrderCard from '../../components/trading/OrderCard';
import { usePriceFlash } from '../../hooks/usePriceFlash';
import { fetchFundingRate, fetchVipInfo, type VipInfo } from '../../services/api/client';
import { Skeleton, SkeletonChart, SkeletonPosition } from '../../components/Skeleton';
import type { MarketQuote, KlineBar } from '../../services/api/client';
import TradingViewChart, { type CrosshairData, MA_COLORS, type ChartType, type ActiveIndicator } from '../../components/chart/TradingViewChart';
import IndicatorsPanel from '../../components/chart/IndicatorsPanel';
import ChartTypeDropdown, { getChartTypeIcon } from '../../components/chart/ChartTypeDropdown';
import DrawingToolsSidebar, { DrawingToolsSettings, DEFAULT_ENABLED_TOOLS, type DrawingTool } from '../../components/chart/DrawingToolsSidebar';
import type { IndicatorType } from '../../components/chart/indicators';

/* ════════════════════════════════════════
   Constants
   ════════════════════════════════════════ */

const TIMEFRAMES_MAIN = ['1min', '15min', '1h', '4h', '1day', '1week'] as const;
const TIMEFRAMES_MORE = ['3min', '5min', '30min', '2h', '6h', '12h', '3day', '1month'] as const;
const ALL_EXTRA_TFS = new Set<string>(TIMEFRAMES_MORE);
const TIMEFRAME_LABELS: Record<string, string> = {
  '1min': '1分钟',
  '3min': '3分钟',
  '5min': '5分钟',
  '15min': '15分钟',
  '30min': '30分钟',
  '1h': '1小时',
  '2h': '2小时',
  '4h': '4小时',
  '6h': '6小时',
  '12h': '12小时',
  '1day': '1天',
  '3day': '3天',
  '1week': '1周',
  '1month': '1月',
};

// ChartType imported from TradingViewChart

type AssetTab = 'crypto' | 'stocks' | 'forex' | 'futures';

const ASSET_TABS: { key: AssetTab; label: string }[] = [
  { key: 'crypto', label: '数字货币' },
  { key: 'stocks', label: '美股' },
  { key: 'forex', label: '外汇' },
  { key: 'futures', label: '期货' },
];

const CRYPTO_SYMBOLS = [
  'BTC/USD','ETH/USD','SOL/USD','BNB/USD','XRP/USD','DOGE/USD','ADA/USD','AVAX/USD',
  'DOT/USD','MATIC/USD','LINK/USD','UNI/USD','SHIB/USD','LTC/USD','TRX/USD',
  'ATOM/USD','NEAR/USD','APT/USD','ARB/USD','OP/USD','FIL/USD','ICP/USD',
  'AAVE/USD','GRT/USD','MKR/USD','IMX/USD','INJ/USD','RUNE/USD','FTM/USD',
  'ALGO/USD','XLM/USD','VET/USD','SAND/USD','MANA/USD','AXS/USD','THETA/USD',
  'EOS/USD','IOTA/USD','XTZ/USD','FLOW/USD','CHZ/USD','CRV/USD','LDO/USD',
  'SNX/USD','COMP/USD','ZEC/USD','DASH/USD','ENJ/USD','BAT/USD','1INCH/USD',
  'SUSHI/USD','YFI/USD','ZRX/USD','KSM/USD','CELO/USD','QTUM/USD','ICX/USD',
  'ONT/USD','ZIL/USD','WAVES/USD','ANKR/USD','SKL/USD','REN/USD','SRM/USD',
  'DYDX/USD','MASK/USD','API3/USD','BAND/USD','OCEAN/USD','STORJ/USD','NKN/USD',
  'SUI/USD','SEI/USD','TIA/USD','JUP/USD','WIF/USD','BONK/USD','PEPE/USD',
  'FLOKI/USD','ORDI/USD','STX/USD','PYTH/USD','JTO/USD','BLUR/USD','STRK/USD',
  'MEME/USD','WLD/USD','CYBER/USD','ARKM/USD','PENDLE/USD','GMX/USD','SSV/USD',
  'RPL/USD','FXS/USD','OSMO/USD','KAVA/USD','CFX/USD','AGIX/USD','FET/USD',
  'RNDR/USD','AR/USD','HNT/USD','ROSE/USD',
];

const STOCK_SYMBOLS = [
  'AAPL','MSFT','GOOGL','AMZN','NVDA','META','TSLA','BRK.B','JPM','V',
  'UNH','JNJ','XOM','WMT','MA','PG','HD','CVX','MRK','ABBV',
  'LLY','PEP','KO','COST','AVGO','TMO','MCD','CSCO','ACN','ABT',
  'DHR','ADBE','CRM','TXN','NEE','NKE','PM','BMY','UPS','RTX',
  'AMGN','HON','QCOM','INTC','IBM','CAT','GE','LOW','INTU','SBUX',
  'BA','DE','GS','BLK','MDLZ','GILD','ADP','ISRG','SYK','ADI',
  'VRTX','MMC','PLD','REGN','CI','SCHW','MO','DUK','SO','BDX',
  'CME','NOC','CL','ZTS','APD','MCK','SHW','TGT','HUM','PYPL',
  'ANET','SNPS','CDNS','ABNB','MRVL','LRCX','KLAC','FTNT','DXCM','MNST',
  'COIN','SQ','SHOP','ROKU','PLTR','SNAP','RBLX','HOOD','SOFI','RIVN',
];

const FOREX_SYMBOLS = [
  'EUR/USD','GBP/USD','USD/JPY','AUD/USD','USD/CAD','USD/CHF','NZD/USD',
  'EUR/GBP','EUR/JPY','GBP/JPY','AUD/JPY','EUR/AUD','EUR/CAD','EUR/CHF',
  'GBP/AUD','GBP/CAD','GBP/CHF','AUD/CAD','AUD/CHF','AUD/NZD',
  'NZD/JPY','NZD/CAD','NZD/CHF','CAD/JPY','CAD/CHF','CHF/JPY',
  'EUR/NZD','GBP/NZD','USD/SGD','USD/HKD','USD/MXN','USD/ZAR',
  'USD/TRY','USD/SEK','USD/NOK','USD/DKK','USD/PLN','USD/CZK',
  'EUR/SEK','EUR/NOK','EUR/DKK','EUR/PLN','EUR/TRY','EUR/HUF',
];

const FUTURES_SYMBOLS = [
  'ES','NQ','YM','RTY','CL','GC','SI','HG','NG','ZB',
  'ZN','ZF','ZT','ZC','ZS','ZW','ZM','ZL','KC','SB',
  'CC','CT','LE','HE','GF','PA','PL',
];

const SYMBOLS_BY_TAB: Record<AssetTab, string[]> = {
  crypto: CRYPTO_SYMBOLS,
  stocks: STOCK_SYMBOLS,
  forex: FOREX_SYMBOLS,
  futures: FUTURES_SYMBOLS,
};

type BottomTab = 'positions' | 'copyPositions' | 'posHistory' | 'orders' | 'history' | 'analysis';
type OrderType = 'limit' | 'market';

/* ════════════════════════════════════════
   Helpers
   ════════════════════════════════════════ */

/** Smart price formatting based on value magnitude */
function formatPrice(price: number | undefined, symbol?: string): string {
  if (price == null || price === 0) return '--';

  // Forex pairs: always 4-5 decimals (industry standard pips)
  if (symbol && symbol.includes('/') && !isCryptoSym(symbol)) {
    // JPY pairs use 3 decimals, others use 5
    const isJpy = symbol.includes('JPY');
    return price.toFixed(isJpy ? 3 : 5);
  }

  // Large prices (≥10000): 2 decimals with comma grouping
  if (price >= 10000) return price.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  // Medium prices (≥1): 2 decimals
  if (price >= 1) return price.toFixed(2);
  // Small prices (≥0.01): 4 decimals
  if (price >= 0.01) return price.toFixed(4);
  // Very small prices (≥0.0001): 6 decimals
  if (price >= 0.0001) return price.toFixed(6);
  // Micro prices (meme coins like PEPE, SHIB): 8 decimals
  return price.toFixed(8);
}

/** Parse a formatted number string (e.g. "66,780.60") into a float */
function parseInputNumber(s: string): number {
  return parseFloat(s.replace(/,/g, '')) || 0;
}

/** Check if symbol is a crypto pair */
function isCryptoSym(sym: string): boolean {
  if (!sym.includes('/')) return false;
  const base = sym.split('/')[0];
  return CRYPTO_SYMBOLS.some((s) => s.startsWith(base + '/'));
}

/** Format change amount — uses reference price to determine precision */
function fmtChange(val: number, symbol?: string, refPrice?: number): string {
  // Use reference price (e.g. current price) to determine the right precision
  const ref = refPrice && refPrice > 0 ? refPrice : val;
  if (symbol && symbol.includes('/') && !isCryptoSym(symbol)) {
    const isJpy = symbol.includes('JPY');
    return val.toFixed(isJpy ? 3 : 5);
  }
  if (ref >= 1000) return val.toFixed(2);
  if (ref >= 1) return val.toFixed(2);
  if (ref >= 0.01) return val.toFixed(4);
  if (ref >= 0.0001) return val.toFixed(6);
  return val.toFixed(8);
}

function formatChange(pct: number | undefined): string {
  if (pct == null) return '--';
  const sign = pct >= 0 ? '+' : '';
  return `${sign}${pct.toFixed(2)}%`;
}

function changeColor(pct: number | undefined): string {
  if (pct == null) return Colors.textMuted;
  if (pct > 0) return Colors.up;
  if (pct < 0) return Colors.down;
  return Colors.textSecondary;
}

/* ════════════════════════════════════════
   Mock Order Book (Level 1 + simulated depth)
   ════════════════════════════════════════ */

/* ════════════════════════════════════════
   Leverage config per asset type
   ════════════════════════════════════════ */

type AssetType = 'crypto' | 'forex' | 'stocks' | 'futures';

function getAssetType(symbol: string): AssetType {
  if (isCryptoSym(symbol)) return 'crypto';
  if (symbol.includes('/')) return 'forex';
  if (FUTURES_SYMBOLS.includes(symbol)) return 'futures';
  return 'stocks';
}

const LEVERAGE_CONFIG: Record<AssetType, { steps: number[]; max: number }> = {
  crypto:  { steps: [1, 2, 3, 5, 10, 20, 25, 50, 75, 100, 125], max: 125 },
  forex:   { steps: [1, 10, 25, 50, 100, 200, 300, 400, 500], max: 500 },
  stocks:  { steps: [1, 2, 3, 4, 5], max: 5 },
  futures: { steps: [1, 2, 5, 10, 20, 50, 100], max: 100 },
};

function snapToStep(value: number, steps: number[]): number {
  let closest = steps[0];
  let minDist = Math.abs(value - closest);
  for (const s of steps) {
    const d = Math.abs(value - s);
    if (d < minDist) { minDist = d; closest = s; }
  }
  return closest;
}

function generateOrderBook(price: number, symbol?: string, tick = 0) {
  // Seeded PRNG — mix price (structure) + tick (micro-variation).
  let seed = ((Math.round(price) | 0) * 31 + tick) | 0;
  const rand = () => {
    seed = (seed * 1664525 + 1013904223) & 0x7fffffff;
    return seed / 0x7fffffff;
  };

  // Asset-specific parameters
  const isCrypto = symbol ? isCryptoSym(symbol) : price > 100;
  const isForex = symbol ? symbol.includes('/') && !isCrypto : false;

  // Tick size: realistic price increments
  let tickSize: number;
  if (isForex) {
    tickSize = price > 100 ? 0.01 : 0.0001; // JPY pairs vs others
  } else if (price >= 10000) {
    tickSize = 0.01;
  } else if (price >= 100) {
    tickSize = 0.01;
  } else if (price >= 1) {
    tickSize = 0.01;
  } else if (price >= 0.01) {
    tickSize = 0.0001;
  } else {
    tickSize = 0.000001;
  }

  // Spread: 1-3 ticks for liquid assets
  const spreadTicks = 1 + Math.floor(rand() * 2);
  const halfSpread = spreadTicks * tickSize;

  // Base quantity scaled to price (higher price → smaller qty, like real markets)
  let baseQty: number;
  if (price >= 50000) baseQty = 0.3;       // BTC-level
  else if (price >= 2000) baseQty = 1.5;    // ETH-level
  else if (price >= 100) baseQty = 15;      // stocks/mid-cap
  else if (price >= 1) baseQty = 500;       // low-price coins/forex
  else baseQty = 50000;                     // micro-price tokens

  const asks: { price: number; qty: number; pct: number }[] = [];
  const bids: { price: number; qty: number; pct: number }[] = [];
  const levels = 10;

  // Generate quantities with realistic distribution:
  // - Near the spread: smaller orders (retail, scalpers)
  // - Mid-depth: larger orders (institutional)
  // - Occasional "wall" at round numbers
  const genQty = (depth: number): number => {
    // Depth factor: qty tends to increase with distance from spread
    const depthMul = 0.5 + depth * 0.15;
    // Random variation with log-normal-ish distribution for occasional large orders
    const variation = Math.exp((rand() - 0.5) * 1.5);
    let qty = baseQty * depthMul * variation;

    // 15% chance of a "wall" (2-5x normal size) at certain levels
    if (rand() < 0.15) qty *= 2 + rand() * 3;

    // Round to sensible precision
    if (qty >= 100) qty = Math.round(qty);
    else if (qty >= 1) qty = Math.round(qty * 100) / 100;
    else qty = Math.round(qty * 10000) / 10000;

    return Math.max(qty, tickSize);
  };

  // Build ask side (ascending from spread)
  let maxAskQty = 0;
  for (let i = 1; i <= levels; i++) {
    // Price levels: mostly 1-tick apart, sometimes skip a tick (thin liquidity)
    const skip = rand() < 0.2 ? 2 : 1;
    const askPrice = price + halfSpread + (i - 1 + (skip - 1) * 0.5) * tickSize;
    const roundedPrice = Math.round(askPrice / tickSize) * tickSize;
    const qty = genQty(i);
    if (qty > maxAskQty) maxAskQty = qty;
    asks.push({ price: roundedPrice, qty, pct: 0 });
  }

  // Build bid side (descending from spread)
  let maxBidQty = 0;
  for (let i = 1; i <= levels; i++) {
    const skip = rand() < 0.2 ? 2 : 1;
    const bidPrice = price - halfSpread - (i - 1 + (skip - 1) * 0.5) * tickSize;
    const roundedPrice = Math.round(bidPrice / tickSize) * tickSize;
    const qty = genQty(i);
    if (qty > maxBidQty) maxBidQty = qty;
    bids.push({ price: roundedPrice, qty, pct: 0 });
  }

  // Calculate pct as proportion of max qty on each side (for bar width)
  const maxQty = Math.max(maxAskQty, maxBidQty, 0.001);
  for (const a of asks) a.pct = a.qty / maxQty;
  for (const b of bids) b.pct = b.qty / maxQty;

  // Long/short ratio from total bid/ask volume
  const totalBidQty = bids.reduce((sum, b) => sum + b.qty, 0);
  const totalAskQty = asks.reduce((sum, a) => sum + a.qty, 0);
  const total = totalBidQty + totalAskQty || 1;
  const buyPct = Math.round((totalBidQty / total) * 100);

  return { asks, bids, buyPct };
}

/* ════════════════════════════════════════
   Price-flash sub-components
   ════════════════════════════════════════ */

function TickerRowFlash({ sym, price, percentChange, isSelected, onPress }: {
  sym: string; price?: number; percentChange?: number; isSelected: boolean; onPress: () => void;
}) {
  const flashBg = usePriceFlash(price);
  return (
    <Animated.View style={{ backgroundColor: flashBg, borderRadius: 4 }}>
      <TouchableOpacity
        style={[s.tickerRow, isSelected && s.tickerRowActive]}
        onPress={onPress}
        activeOpacity={0.7}
      >
        <Text style={s.tickerSymbol}>{sym.replace('/USD', '')}</Text>
        <Text style={s.tickerPrice}>{formatPrice(price, sym)}</Text>
        <Text style={[s.tickerChange, { color: changeColor(percentChange) }]}>
          {formatChange(percentChange)}
        </Text>
      </TouchableOpacity>
    </Animated.View>
  );
}

function OrderBookCurrentPrice({ price, percentChange, symbol }: { price: number; percentChange?: number; symbol?: string }) {
  const flashBg = usePriceFlash(price);
  return (
    <Animated.View style={[s.obCurrentRow, { backgroundColor: flashBg, borderRadius: 4 }]}>
      <Text style={[s.obCurrentPrice, { color: changeColor(percentChange) }]}>
        {formatPrice(price, symbol)}
      </Text>
      <Text style={s.obCurrentSub}>≈ ${formatPrice(price, symbol)}</Text>
    </Animated.View>
  );
}

/** Funding rate countdown timer */
function FundingCountdown({ nextTime }: { nextTime?: number }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);
  if (!nextTime) return <Text style={s.statValue}>--</Text>;
  const diff = Math.max(0, nextTime - now);
  const h = String(Math.floor(diff / 3600000)).padStart(2, '0');
  const m = String(Math.floor((diff % 3600000) / 60000)).padStart(2, '0');
  const sec = String(Math.floor((diff % 60000) / 1000)).padStart(2, '0');
  return <Text style={s.statValue}>{h}:{m}:{sec}</Text>;
}

function MobilePriceHeader({ price, percentChange, symbol }: { price: number; percentChange?: number; symbol?: string }) {
  const flashBg = usePriceFlash(price);
  return (
    <Animated.View style={[s.mobilePriceHeader, { backgroundColor: flashBg, borderRadius: 8 }]}>
      <Text style={[s.mobileBigPrice, { color: changeColor(percentChange) }]}>
        {formatPrice(price, symbol)}
      </Text>
      <Text style={[s.mobilePriceChange, { color: changeColor(percentChange) }]}>
        {formatChange(percentChange)}
      </Text>
    </Animated.View>
  );
}

/* ════════════════════════════════════════
   OHLC + MA Overlay (on top of chart)
   ════════════════════════════════════════ */

function OhlcOverlay({ data, symbol }: { data: CrosshairData | null; symbol: string }) {
  if (!data) return null;

  const isUp = data.close >= data.open;
  const ohlcColor = isUp ? Colors.up : Colors.down;
  const sign = data.changePct >= 0 ? '+' : '';

  return (
    <View style={ohlc.container}>
      <View style={ohlc.row}>
        <Text style={ohlc.symbol}>{symbol}</Text>
        <Text style={ohlc.label}>O</Text>
        <Text style={[ohlc.val, { color: ohlcColor }]}>{fmtOhlc(data.open)}</Text>
        <Text style={ohlc.label}>H</Text>
        <Text style={[ohlc.val, { color: ohlcColor }]}>{fmtOhlc(data.high)}</Text>
        <Text style={ohlc.label}>L</Text>
        <Text style={[ohlc.val, { color: ohlcColor }]}>{fmtOhlc(data.low)}</Text>
        <Text style={ohlc.label}>C</Text>
        <Text style={[ohlc.val, { color: ohlcColor }]}>{fmtOhlc(data.close)}</Text>
        <Text style={[ohlc.val, { color: ohlcColor, marginLeft: 8 }]}>
          {sign}{data.change.toFixed(2)} ({sign}{data.changePct.toFixed(2)}%)
        </Text>
      </View>
      <View style={ohlc.row}>
        <Text style={[ohlc.maLabel, { color: MA_COLORS.ma5 }]}>MA5</Text>
        <Text style={[ohlc.maVal, { color: MA_COLORS.ma5 }]}>
          {data.ma5 != null ? fmtOhlc(data.ma5) : '--'}
        </Text>
        <Text style={[ohlc.maLabel, { color: MA_COLORS.ma10 }]}>MA10</Text>
        <Text style={[ohlc.maVal, { color: MA_COLORS.ma10 }]}>
          {data.ma10 != null ? fmtOhlc(data.ma10) : '--'}
        </Text>
        <Text style={[ohlc.maLabel, { color: MA_COLORS.ma30 }]}>MA30</Text>
        <Text style={[ohlc.maVal, { color: MA_COLORS.ma30 }]}>
          {data.ma30 != null ? fmtOhlc(data.ma30) : '--'}
        </Text>
      </View>
    </View>
  );
}

function fmtOhlc(n: number): string {
  if (n >= 10000) return n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (n >= 1) return n.toFixed(2);
  if (n >= 0.01) return n.toFixed(4);
  if (n >= 0.0001) return n.toFixed(6);
  return n.toFixed(8);
}

const ohlc = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 4,
    left: 8,
    zIndex: 10,
    gap: 2,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  symbol: {
    color: Colors.textActive,
    fontSize: 11,
    fontWeight: '700',
    marginRight: 6,
  },
  label: {
    color: Colors.textMuted,
    fontSize: 10,
  },
  val: {
    fontSize: 10,
    fontWeight: '600',
    fontFamily: 'monospace',
    marginRight: 4,
  },
  maLabel: {
    fontSize: 10,
    fontWeight: '600',
    marginRight: 2,
  },
  maVal: {
    fontSize: 10,
    fontWeight: '600',
    fontFamily: 'monospace',
    marginRight: 8,
  },
});

/* ════════════════════════════════════════
   Main Component
   ════════════════════════════════════════ */

/* ════════════════════════════════════════
   Symbol Dropdown Selector
   ════════════════════════════════════════ */

function SymbolDropdown({
  visible,
  selectedSymbol,
  onSelect,
  onClose,
  quotes,
}: {
  visible: boolean;
  selectedSymbol: string;
  onSelect: (sym: string) => void;
  onClose: () => void;
  quotes: Record<string, MarketQuote>;
}) {
  const [activeTab, setActiveTab] = useState<AssetTab>('crypto');
  const [filter, setFilter] = useState('');

  if (!visible) return null;

  const symbols = SYMBOLS_BY_TAB[activeTab];
  const filtered = filter
    ? symbols.filter((s) => s.toLowerCase().includes(filter.toLowerCase()))
    : symbols;

  return (
    <View style={dd.overlay}>
      <TouchableOpacity style={dd.backdrop} onPress={onClose} activeOpacity={1} />
      <View style={dd.panel}>
        {/* Search */}
        <View style={dd.searchRow}>
          <Text style={dd.searchIcon}>🔍</Text>
          <TextInput
            style={dd.searchInput}
            placeholder="搜索交易对..."
            placeholderTextColor={Colors.textMuted}
            value={filter}
            onChangeText={setFilter}
            autoFocus
          />
          <TouchableOpacity onPress={onClose}>
            <Text style={dd.closeBtn}>✕</Text>
          </TouchableOpacity>
        </View>

        {/* Tabs */}
        <View style={dd.tabRow}>
          {ASSET_TABS.map((tab) => (
            <TouchableOpacity
              key={tab.key}
              style={[dd.tab, activeTab === tab.key && dd.tabActive]}
              onPress={() => { setActiveTab(tab.key); setFilter(''); }}
              activeOpacity={0.7}
            >
              <Text style={[dd.tabText, activeTab === tab.key && dd.tabTextActive]}>
                {tab.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* Header */}
        <View style={dd.listHeader}>
          <Text style={dd.headerText}>交易对</Text>
          <Text style={[dd.headerText, { textAlign: 'right' }]}>价格</Text>
          <Text style={[dd.headerText, { textAlign: 'right' }]}>24h 涨跌</Text>
        </View>

        {/* List */}
        <ScrollView style={dd.list} keyboardShouldPersistTaps="handled">
          {filtered.map((sym) => {
            const q = quotes[sym];
            const isActive = selectedSymbol === sym;
            const pct = q?.percent_change;
            return (
              <TouchableOpacity
                key={sym}
                style={[dd.row, isActive && dd.rowActive]}
                onPress={() => { onSelect(sym); onClose(); }}
                activeOpacity={0.6}
              >
                <Text style={[dd.rowSymbol, isActive && { color: Colors.primary }]}>
                  {sym}
                </Text>
                <Text style={dd.rowPrice}>
                  {q?.price ? formatPrice(q.price, sym) : '--'}
                </Text>
                <Text style={[dd.rowChange, { color: changeColor(pct) }]}>
                  {formatChange(pct)}
                </Text>
              </TouchableOpacity>
            );
          })}
          {filtered.length === 0 && (
            <View style={dd.empty}>
              <Text style={{ color: Colors.textMuted, fontSize: 13 }}>无匹配结果</Text>
            </View>
          )}
        </ScrollView>
      </View>
    </View>
  );
}

const dd = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    zIndex: 100,
  },
  backdrop: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  panel: {
    position: 'absolute',
    top: 0, left: 0, bottom: 0,
    width: 380,
    backgroundColor: '#131313',
    borderRightWidth: 1,
    borderRightColor: Colors.border,
  },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    gap: 8,
  },
  searchIcon: { fontSize: 14, opacity: 0.5 },
  searchInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 13,
    paddingVertical: 4,
  },
  closeBtn: {
    color: Colors.textMuted,
    fontSize: 16,
    padding: 4,
  },
  tabRow: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 8,
  },
  tab: {
    paddingVertical: 10,
    paddingHorizontal: 14,
  },
  tabActive: {
    borderBottomWidth: 2,
    borderBottomColor: Colors.primary,
  },
  tabText: {
    fontSize: 12,
    color: Colors.textMuted,
    fontWeight: '600',
  },
  tabTextActive: {
    color: Colors.primary,
  },
  listHeader: {
    flexDirection: 'row',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.05)',
  },
  headerText: {
    flex: 1,
    fontSize: 10,
    color: Colors.textMuted,
    fontWeight: '500',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  list: {
    flex: 1,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  rowActive: {
    backgroundColor: 'rgba(42,42,42,0.3)',
  },
  rowSymbol: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  rowPrice: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 12,
    textAlign: 'right',
    fontFamily: 'monospace',
  },
  rowChange: {
    flex: 1,
    fontSize: 12,
    textAlign: 'right',
    fontFamily: 'monospace',
  },
  empty: {
    paddingVertical: 40,
    alignItems: 'center',
  },
});

/* ════════════════════════════════════════
   Main Component
   ════════════════════════════════════════ */

export default function TradingScreen() {
  const { width } = useWindowDimensions();
  const isDesktop = width >= 900;
  const { user } = useAuthStore();

  const {
    positions,
    positionHistory,
    pendingOrders,
    orderHistory,
    account,
    fetchPositions,
    fetchPositionHistory,
    fetchPendingOrders,
    fetchOrderHistory,
    fetchAccount,
    placeOrder,
    cancelOrder: cancelTradingOrder,
    closePosition,
    deposit: doDeposit,
    connectWs: connectTradingWs,
    disconnectWs: disconnectTradingWs,
  } = useTradingStore();

  const [showDepositModal, setShowDepositModal] = useState(false);
  const [depositAmount, setDepositAmount] = useState('');
  const [orderLoading, setOrderLoading] = useState(false);
  const [closeAllLoading, setCloseAllLoading] = useState(false);
  const [panelMode, setPanelMode] = useState<'open' | 'close'>('open');

  const {
    quotes,
    klines,
    klinesLoading,
    loadCryptoQuotes,
    loadQuotes,
    loadForexQuotes,
    loadFuturesQuotes,
    loadKlines,
    updateQuote,
  } = useMarketStore();

  // Local state
  const [selectedSymbol, setSelectedSymbol] = useState('BTC/USD');
  const [timeframe, setTimeframe] = useState<string>('1h');
  const [bottomTab, setBottomTab] = useState<BottomTab>('positions');
  const [orderType, setOrderType] = useState<OrderType>('limit');
  const [priceInput, setPriceInput] = useState('');
  const [qtyInput, setQtyInput] = useState('');
  const [sliderPct, setSliderPct] = useState(0);
  const [qtyMode, setQtyMode] = useState<'coin' | 'notional' | 'margin'>('coin'); // 币本位 / 名义价值 / 保证金价值
  const [showQtyModeDropdown, setShowQtyModeDropdown] = useState(false);
  const [leverage, setLeverage] = useState(20);
  const [marginMode, setMarginMode] = useState<'cross' | 'isolated'>('cross');
  const [showTPSL, setShowTPSL] = useState(false);
  const [tpInput, setTpInput] = useState('');
  const [slInput, setSlInput] = useState('');
  const [showLeverageModal, setShowLeverageModal] = useState(false);
  const [showDropdown, setShowDropdown] = useState(false);
  const [crosshairData, setCrosshairData] = useState<CrosshairData | null>(null);
  const [vipInfo, setVipInfo] = useState<VipInfo | null>(null);
  const [chartType, setChartType] = useState<ChartType>('candle');
  const [showMoreTf, setShowMoreTf] = useState(false);
  const [showIndicatorsPanel, setShowIndicatorsPanel] = useState(false);
  const [showChartTypeDropdown, setShowChartTypeDropdown] = useState(false);
  const [showDrawingTools, setShowDrawingTools] = useState(true);
  const [activeIndicators, setActiveIndicators] = useState<ActiveIndicator[]>([]);
  const [drawingTool, setDrawingTool] = useState<DrawingTool>('cursor');
  const [clearDrawings, setClearDrawings] = useState(false);
  const [enabledTools, setEnabledTools] = useState<DrawingTool[]>(DEFAULT_ENABLED_TOOLS);
  const [showDrawingToolsSettings, setShowDrawingToolsSettings] = useState(false);

  // Network status monitoring
  const [netConnected, setNetConnected] = useState(true);
  const [netLatency, setNetLatency] = useState(-1); // ms

  // Funding rate
  const [fundingRate, setFundingRate] = useState<{ fundingRate: string | null; nextFundingTime?: number } | null>(null);

  // Fetch VIP info when user logs in
  useEffect(() => {
    if (!user) { setVipInfo(null); return; }
    fetchVipInfo().then(setVipInfo).catch(() => {});
  }, [user]);

  // Load enabled tools from localStorage on mount
  useEffect(() => {
    if (Platform.OS !== 'web') return;
    try {
      const saved = localStorage.getItem('drawingToolsEnabled');
      if (saved) setEnabledTools(JSON.parse(saved));
    } catch (_) {}
  }, []);

  // Load saved leverage per asset type from localStorage
  useEffect(() => {
    if (Platform.OS !== 'web') return;
    try {
      const at = getAssetType(selectedSymbol);
      const saved = localStorage.getItem(`trading_leverage_${at}`);
      if (saved) {
        const val = parseInt(saved, 10);
        const config = LEVERAGE_CONFIG[at];
        if (config.steps.includes(val)) setLeverage(val);
      }
    } catch (_) {}
  }, [selectedSymbol]);

  const handleToggleDrawingTool = useCallback((tool: DrawingTool) => {
    setEnabledTools((prev) => {
      const next = prev.includes(tool) ? prev.filter((t) => t !== tool) : [...prev, tool];
      if (Platform.OS === 'web') {
        try { localStorage.setItem('drawingToolsEnabled', JSON.stringify(next)); } catch (_) {}
      }
      return next;
    });
  }, []);

  const handleResetDrawingTools = useCallback(() => {
    setEnabledTools(DEFAULT_ENABLED_TOOLS);
    if (Platform.OS === 'web') {
      try { localStorage.setItem('drawingToolsEnabled', JSON.stringify(DEFAULT_ENABLED_TOOLS)); } catch (_) {}
    }
  }, []);

  const handleToggleIndicator = useCallback((type: IndicatorType, params: Record<string, number>) => {
    setActiveIndicators((prev) => {
      const exists = prev.find((i) => i.type === type);
      if (exists) return prev.filter((i) => i.type !== type);
      return [...prev, { type, params }];
    });
  }, []);

  const handleRemoveIndicator = useCallback((type: IndicatorType) => {
    setActiveIndicators((prev) => prev.filter((i) => i.type !== type));
  }, []);

  const handleDrawingToolSelect = useCallback((tool: DrawingTool) => {
    if (tool === 'eraser') {
      setClearDrawings(true);
      setTimeout(() => setClearDrawings(false), 100);
      setDrawingTool('cursor');
    } else {
      setDrawingTool(tool);
    }
  }, []);

  const handleDrawingComplete = useCallback(() => {
    setDrawingTool('cursor');
  }, []);

  const selectedQuote = quotes[selectedSymbol];
  const currentPrice = selectedQuote?.price ?? 0;
  const baseAsset = selectedSymbol.includes('/') ? selectedSymbol.split('/')[0] : selectedSymbol;

  // Convert input to actual coin qty based on qtyMode
  const getActualQty = useCallback(() => {
    const val = parseInputNumber(qtyInput) || 0;
    if (val <= 0) return 0;
    const price = orderType === 'limit' ? (parseInputNumber(priceInput) || currentPrice) : currentPrice;
    if (!price || price <= 0) return 0;
    if (qtyMode === 'coin') return val;
    if (qtyMode === 'notional') return val / price;
    if (qtyMode === 'margin') return (val * leverage) / price;
    return val;
  }, [qtyInput, qtyMode, orderType, priceInput, currentPrice, leverage]);

  const qtyModeLabel = qtyMode === 'coin' ? baseAsset : 'USDT';

  const handlePlaceOrder = useCallback(async (side: 'long' | 'short') => {
    if (!user) {
      if (Platform.OS === 'web') window.alert('请先登录');
      return;
    }
    const qty = getActualQty();
    if (!qty || qty <= 0) {
      if (Platform.OS === 'web') window.alert('请输入数量');
      return;
    }
    const req: any = {
      symbol: selectedSymbol,
      side,
      type: orderType,
      qty: parseFloat(qty.toFixed(8)),
      leverage,
      margin_mode: marginMode,
    };
    if (showTPSL) {
      const tp = parseInputNumber(tpInput);
      const sl = parseInputNumber(slInput);
      if (tp > 0) req.tp_price = tp;
      if (sl > 0) req.sl_price = sl;
    }
    if (orderType === 'limit') {
      const price = parseInputNumber(priceInput);
      if (!price || price <= 0) {
        if (Platform.OS === 'web') window.alert('请输入限价');
        return;
      }
      req.price = price;
    }
    setOrderLoading(true);
    try {
      await placeOrder(req);
      setQtyInput('');
      setSliderPct(0);
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || '下单失败';
      if (Platform.OS === 'web') window.alert(msg);
    } finally {
      setOrderLoading(false);
    }
  }, [user, getActualQty, selectedSymbol, orderType, leverage, marginMode, placeOrder, showTPSL, tpInput, slInput, priceInput]);

  const handleCloseAll = useCallback(async () => {
    const openPositions = positions.filter(p => !p.is_copy_trade);
    if (openPositions.length === 0) return;
    const msg = `确定平掉全部 ${openPositions.length} 个持仓？`;
    if (Platform.OS === 'web') {
      if (!window.confirm(msg)) return;
    }
    setCloseAllLoading(true);
    try {
      await Promise.allSettled(openPositions.map(p => closePosition(p.id)));
      fetchPositions();
      fetchPositionHistory();
      fetchAccount();
    } catch (e) {
      console.error('[closeAll] error:', e);
    } finally {
      setCloseAllLoading(false);
    }
  }, [positions, closePosition, fetchPositions, fetchPositionHistory, fetchAccount]);

  const handleDeposit = useCallback(async (amount: number) => {
    if (!user) {
      if (Platform.OS === 'web') window.alert('请先登录');
      return;
    }
    try {
      await doDeposit(amount);
      fetchAccount();
      setShowDepositModal(false);
      setDepositAmount('');
    } catch (e: any) {
      if (Platform.OS === 'web') window.alert('充值失败');
    }
  }, [doDeposit, user, fetchAccount]);

  const calcMargin = useCallback(() => {
    const qty = getActualQty();
    const price = orderType === 'limit' ? (parseInputNumber(priceInput) || 0) : (currentPrice || 0);
    if (qty <= 0 || price <= 0 || leverage <= 0) return 0;
    return (qty * price) / leverage;
  }, [getActualQty, priceInput, orderType, currentPrice, leverage]);

  const calcLiqPrice = useCallback((side: 'long' | 'short') => {
    const price = orderType === 'limit' ? (parseInputNumber(priceInput) || 0) : (currentPrice || 0);
    if (price <= 0 || leverage <= 0) return 0;
    const mmr = 0.005;
    if (side === 'long') return price * (1 - 1 / leverage + mmr);
    return price * (1 + 1 / leverage - mmr);
  }, [priceInput, orderType, currentPrice, leverage]);
  // Tick counter drives order book refresh (~300ms) - stops when network disconnected
  const [obTick, setObTick] = useState(0);
  useEffect(() => {
    if (!netConnected) return; // 网络断开时盘口冻结
    const id = setInterval(() => setObTick(t => t + 1), 300);
    return () => clearInterval(id);
  }, [netConnected]);
  const orderBook = useMemo(() => generateOrderBook(currentPrice || 64289, selectedSymbol, obTick), [currentPrice, selectedSymbol, obTick]);

  // Slider percentage → qty calculation
  const handleSliderChange = useCallback((pct: number) => {
    setSliderPct(pct);
    if (pct === 0 || !account) { setQtyInput(''); return; }
    const price = orderType === 'limit' ? (parseInputNumber(priceInput) || currentPrice) : currentPrice;
    if (!price || price <= 0) return;
    const available = account.available || 0;
    // Fee is on notional value: fee = margin * leverage * feeRate
    // So total = margin + margin * leverage * feeRate = margin * (1 + leverage * feeRate)
    // maxMargin = available / (1 + leverage * feeRate)
    const feeRate = 0.0005;
    const maxMargin = available / (1 + leverage * feeRate);
    const maxQtyCoin = (maxMargin * leverage) / price;
    const qtyCoin = maxQtyCoin * (pct / 100);
    if (qtyCoin <= 0) { setQtyInput(''); return; }
    const decimals = price >= 1000 ? 4 : price >= 1 ? 2 : 0;
    if (qtyMode === 'coin') {
      setQtyInput(qtyCoin.toFixed(decimals));
    } else if (qtyMode === 'notional') {
      setQtyInput((qtyCoin * price).toFixed(2));
    } else {
      setQtyInput(((qtyCoin * price) / leverage).toFixed(2));
    }
  }, [account, orderType, priceInput, currentPrice, leverage, qtyMode]);

  // Snap leverage to valid value when switching asset types
  useEffect(() => {
    const config = LEVERAGE_CONFIG[getAssetType(selectedSymbol)];
    if (!config.steps.includes(leverage)) {
      setLeverage(snapToStep(leverage, config.steps));
    }
  }, [selectedSymbol]);

  // Persist leverage per asset type
  useEffect(() => {
    if (Platform.OS !== 'web') return;
    try {
      const at = getAssetType(selectedSymbol);
      localStorage.setItem(`trading_leverage_${at}`, String(leverage));
    } catch (_) {}
  }, [leverage, selectedSymbol]);

  // Load initial data via REST (one-time bootstrap while WS connects)
  // Split into batches to avoid API timeout on large symbol lists
  useEffect(() => {
    // Crypto: batch of 50
    for (let i = 0; i < CRYPTO_SYMBOLS.length; i += 50) {
      loadCryptoQuotes(CRYPTO_SYMBOLS.slice(i, i + 50));
    }
    // Stocks: batch of 50
    for (let i = 0; i < STOCK_SYMBOLS.length; i += 50) {
      loadQuotes(STOCK_SYMBOLS.slice(i, i + 50));
    }
    // Futures: dedicated API
    loadFuturesQuotes(FUTURES_SYMBOLS);
    // Forex: batch of 15
    for (let i = 0; i < FOREX_SYMBOLS.length; i += 15) {
      loadForexQuotes(FOREX_SYMBOLS.slice(i, i + 15));
    }
  }, []);

  // Load klines when symbol or timeframe changes
  useEffect(() => {
    if (selectedSymbol) {
      loadKlines(selectedSymbol, timeframe);
    }
  }, [selectedSymbol, timeframe]);

  // Fetch funding rate on symbol change (crypto only)
  useEffect(() => {
    if (!selectedSymbol) return;
    setFundingRate(null);
    fetchFundingRate(selectedSymbol).then(setFundingRate);
    // Refresh every 60s
    const id = setInterval(() => fetchFundingRate(selectedSymbol).then(setFundingRate), 60000);
    return () => clearInterval(id);
  }, [selectedSymbol]);

  // WebSocket: subscribe ALL symbols for real-time updates + network monitoring
  useEffect(() => {
    marketWs.connect();
    const handler = (msg: any) => {
      if (msg.symbol && msg.price != null) {
        updateQuote(msg.symbol, msg);
      }
    };
    // Network status listener
    const statusHandler = (msg: any) => {
      if (msg.type === 'ws_status') {
        setNetConnected(msg.connected);
        if (!msg.connected) setNetLatency(-1);
      }
      if (msg.type === 'ws_latency') {
        setNetLatency(msg.latency);
        setNetConnected(true);
      }
    };
    marketWs.onMessage(statusHandler);
    const allSubs = [...CRYPTO_SYMBOLS, ...STOCK_SYMBOLS, ...FOREX_SYMBOLS, ...FUTURES_SYMBOLS];
    marketWs.subscribeMany(allSubs, handler);
    return () => {
      allSubs.forEach((sym) => marketWs.unsubscribe(sym, handler));
      marketWs.offMessage(statusHandler);
    };
  }, []);

  // Trading WS + initial data fetch
  useEffect(() => {
    if (user) {
      connectTradingWs(); // Persistent — won't disconnect on page switch
      fetchPositions();
      fetchPositionHistory();
      fetchPendingOrders();
      fetchOrderHistory();
      fetchAccount();
      // No cleanup: WS stays alive across page switches.
      // Only disconnects on logout (authStore handles it).
    }
  }, [user]);

  // Update price input when symbol changes or first price arrives
  const priceInitRef = useRef<string>('');
  useEffect(() => {
    if (currentPrice) setPriceInput(formatPrice(currentPrice, selectedSymbol));
    priceInitRef.current = selectedSymbol;
  }, [selectedSymbol]);
  // Set price once when first quote arrives (initial load)
  useEffect(() => {
    if (currentPrice && priceInitRef.current !== selectedSymbol + '_loaded') {
      setPriceInput(formatPrice(currentPrice, selectedSymbol));
      priceInitRef.current = selectedSymbol + '_loaded';
    }
  }, [currentPrice]);

  const handleSelectSymbol = useCallback((sym: string) => {
    setSelectedSymbol(sym);
  }, []);

  /* ═══════ Desktop Layout ═══════ */
  if (isDesktop) {
    return (
      <View style={s.root}>
        {/* Symbol Dropdown */}
        <SymbolDropdown
          visible={showDropdown}
          selectedSymbol={selectedSymbol}
          onSelect={handleSelectSymbol}
          onClose={() => setShowDropdown(false)}
          quotes={quotes}
        />

        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ minHeight: '100%' }} showsVerticalScrollIndicator={false}>
        <View style={s.desktopRow}>
          {/* Main Chart Area (now full width, no left panel) */}
          <View style={s.middlePanel}>
            {/* Stats bar with symbol selector */}
            <View style={s.statsBar}>
              {/* Symbol selector trigger */}
              <TouchableOpacity
                style={s.symbolTrigger}
                onPress={() => setShowDropdown(true)}
                activeOpacity={0.7}
              >
                <Text style={s.symbolTriggerText}>{selectedSymbol}</Text>
                <Text style={s.symbolTriggerArrow}>▼</Text>
              </TouchableOpacity>

              {/* Current Price (large) */}
              <View style={s.priceBlock}>
                <Text style={[s.priceBig, { color: changeColor(selectedQuote?.percent_change) }]}>
                  {formatPrice(currentPrice, selectedSymbol)}
                </Text>
                <Text style={s.priceUsd}>≈ ${formatPrice(currentPrice, selectedSymbol)}</Text>
              </View>

              <View style={s.statDivider} />

              {/* Change */}
              <View style={s.statItem}>
                <Text style={s.statLabel}>涨跌额</Text>
                <Text style={[s.statValue, { color: changeColor(selectedQuote?.percent_change) }]}>
                  {selectedQuote?.change != null
                    ? `${selectedQuote.change >= 0 ? '+' : '-'}${fmtChange(Math.abs(selectedQuote.change), selectedSymbol, currentPrice)}`
                    : '--'}
                </Text>
              </View>
              <View style={s.statItem}>
                <Text style={s.statLabel}>涨跌幅</Text>
                <Text style={[s.statValue, { color: changeColor(selectedQuote?.percent_change) }]}>
                  {formatChange(selectedQuote?.percent_change)}
                </Text>
              </View>

              <View style={s.statDivider} />

              <View style={s.statItem}>
                <Text style={s.statLabel}>24h 最高</Text>
                <Text style={s.statValue}>{formatPrice(selectedQuote?.high, selectedSymbol)}</Text>
              </View>
              <View style={s.statItem}>
                <Text style={s.statLabel}>24h 最低</Text>
                <Text style={s.statValue}>{formatPrice(selectedQuote?.low, selectedSymbol)}</Text>
              </View>

              <View style={s.statDivider} />

              <View style={s.statItem}>
                <Text style={s.statLabel}>24h 成交量</Text>
                <Text style={s.statValue}>
                  {selectedQuote?.volume
                    ? selectedQuote.volume >= 1e6
                      ? `${(selectedQuote.volume / 1e6).toFixed(2)}M`
                      : selectedQuote.volume.toFixed(2)
                    : '--'}
                </Text>
              </View>
              <View style={s.statItem}>
                <Text style={s.statLabel}>24h 成交额</Text>
                <Text style={s.statValue}>
                  {selectedQuote?.volume && currentPrice
                    ? `${((selectedQuote.volume * currentPrice) / 1e6).toFixed(2)}M`
                    : '--'}
                </Text>
              </View>

              {fundingRate?.fundingRate != null && (
                <>
                  <View style={s.statDivider} />
                  <View style={s.statItem}>
                    <Text style={s.statLabel}>资金费率</Text>
                    <Text style={[s.statValue, { color: parseFloat(fundingRate.fundingRate) >= 0 ? '#0ECB81' : '#F6465D' }]}>
                      {(parseFloat(fundingRate.fundingRate) * 100).toFixed(4)}%
                    </Text>
                  </View>
                  <View style={s.statItem}>
                    <Text style={s.statLabel}>倒计时</Text>
                    <FundingCountdown nextTime={fundingRate.nextFundingTime} />
                  </View>
                </>
              )}

            </View>

            {/* Network disconnected banner */}
            {!netConnected && (
              <View style={{ backgroundColor: 'rgba(246,70,93,0.15)', paddingVertical: 6, paddingHorizontal: 16, flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: '#F6465D' }} />
                <Text style={{ color: '#F6465D', fontSize: 12 }}>网络连接已断开，行情数据已暂停，正在重连...</Text>
              </View>
            )}

            {/* Timeframe bar (separate row like Binance) */}
            <View style={s.timeframeBar}>
              <View style={s.tfRow}>
                {TIMEFRAMES_MAIN.map((tf) => (
                  <TouchableOpacity
                    key={tf}
                    style={[s.tfBtn, timeframe === tf && s.tfBtnActive]}
                    onPress={() => { setTimeframe(tf); setShowMoreTf(false); }}
                    activeOpacity={0.7}
                  >
                    <Text style={[s.tfText, timeframe === tf && s.tfTextActive]}>
                      {TIMEFRAME_LABELS[tf]}
                    </Text>
                  </TouchableOpacity>
                ))}

                {/* More button — show current extra TF label if selected */}
                <TouchableOpacity
                  style={[s.tfBtn, (showMoreTf || ALL_EXTRA_TFS.has(timeframe)) && s.tfBtnActive]}
                  onPress={() => setShowMoreTf(!showMoreTf)}
                  activeOpacity={0.7}
                >
                  <Text style={[s.tfText, (showMoreTf || ALL_EXTRA_TFS.has(timeframe)) && s.tfTextActive]}>
                    {ALL_EXTRA_TFS.has(timeframe) ? TIMEFRAME_LABELS[timeframe] : 'More'} ▾
                  </Text>
                </TouchableOpacity>
              </View>

              <View style={{ flex: 1 }} />

              {/* Chart type selector */}
              <View style={s.chartTypeRow}>
                <TouchableOpacity
                  style={[s.chartTypeBtn, showChartTypeDropdown && s.chartTypeBtnActive]}
                  onPress={() => setShowChartTypeDropdown(!showChartTypeDropdown)}
                  activeOpacity={0.7}
                >
                  <Text style={[s.chartTypeIcon, showChartTypeDropdown && s.chartTypeIconActive]}>
                    {getChartTypeIcon(chartType)} ▾
                  </Text>
                </TouchableOpacity>

                {/* Indicators button */}
                <TouchableOpacity
                  style={[s.chartTypeBtn, { paddingHorizontal: 8 }, activeIndicators.length > 0 && s.chartTypeBtnActive]}
                  onPress={() => setShowIndicatorsPanel(true)}
                  activeOpacity={0.7}
                >
                  <Text style={[s.chartTypeIcon, activeIndicators.length > 0 && s.chartTypeIconActive]}>
                    ƒx{activeIndicators.length > 0 ? ` (${activeIndicators.length})` : ''}
                  </Text>
                </TouchableOpacity>

                {/* Drawing tools toggle */}
                <TouchableOpacity
                  style={[s.chartTypeBtn, showDrawingTools && s.chartTypeBtnActive]}
                  onPress={() => {
                    setShowDrawingTools(!showDrawingTools);
                    if (showDrawingTools) setDrawingTool('cursor');
                  }}
                  activeOpacity={0.7}
                >
                  <Text style={[s.chartTypeIcon, showDrawingTools && s.chartTypeIconActive]}>
                    ✎
                  </Text>
                </TouchableOpacity>
              </View>
            </View>

            {/* More timeframe dropdown (rendered outside overflow:hidden chart) */}
            {showMoreTf && (
              <View style={s.moreTfOverlay}>
                <TouchableOpacity style={s.moreTfBackdrop} onPress={() => setShowMoreTf(false)} activeOpacity={1} />
                <View style={s.moreTfDropdown}>
                  <View style={s.moreTfGrid}>
                    {TIMEFRAMES_MORE.map((tf) => (
                      <TouchableOpacity
                        key={tf}
                        style={[s.moreTfItem, timeframe === tf && s.moreTfItemActive]}
                        onPress={() => { setTimeframe(tf); setShowMoreTf(false); }}
                        activeOpacity={0.7}
                      >
                        <Text style={[s.moreTfText, timeframe === tf && s.moreTfTextActive]}>
                          {TIMEFRAME_LABELS[tf]}
                        </Text>
                      </TouchableOpacity>
                    ))}
                  </View>
                </View>
              </View>
            )}

            {/* Chart area with Drawing Tools Sidebar + OHLC overlay */}
            <View style={s.chartArea}>
              <View style={{ flexDirection: 'row', flex: 1 }}>
                {/* Drawing tools sidebar */}
                <DrawingToolsSidebar
                  visible={showDrawingTools}
                  activeTool={drawingTool}
                  onToolSelect={handleDrawingToolSelect}
                  enabledTools={enabledTools}
                  onOpenSettings={() => setShowDrawingToolsSettings(true)}
                />

                {/* Chart */}
                <View style={{ flex: 1, position: 'relative' }}>
                  <OhlcOverlay data={crosshairData} symbol={selectedSymbol} />
                  {klinesLoading && klines.length === 0 ? (
                    <SkeletonChart />
                  ) : klines.length > 0 ? (
                    <TradingViewChart
                      klines={klines}
                      symbol={selectedSymbol}
                      chartType={chartType}
                      activeIndicators={activeIndicators}
                      drawingTool={drawingTool}
                      onCrosshairData={setCrosshairData}
                      onDrawingComplete={handleDrawingComplete}
                      onClearDrawings={clearDrawings}
                      realtimePrice={currentPrice}
                    />
                  ) : (
                    <View style={s.chartPlaceholder}>
                      <Text style={s.chartWatermark}>SOVEREIGN</Text>
                      <Text style={{ color: Colors.textMuted, fontSize: 13 }}>暂无K线数据</Text>
                    </View>
                  )}
                </View>
              </View>
            </View>

            {/* Bottom tabs */}
            <View style={s.bottomPanel}>
              <View style={s.bottomTabRow}>
                {(() => {
                  const selfPositions = positions.filter(p => !p.is_copy_trade);
                  const copyPositions = positions.filter(p => p.is_copy_trade);
                  return ([
                    ['positions', '当前持仓'],
                    ['copyPositions', '跟单'],
                    ['orders', '当前委托'],
                    ['posHistory', '历史仓位'],
                    ['history', '历史委托'],
                    ['analysis', '资产分析'],
                  ] as [BottomTab, string][]).map(([key, label]) => {
                    const badgeCount = key === 'positions' ? selfPositions.length
                      : key === 'copyPositions' ? copyPositions.length
                      : key === 'orders' ? pendingOrders.length
                      : 0;
                    return (
                      <TouchableOpacity
                        key={key}
                        style={[s.bottomTabBtn, bottomTab === key && s.bottomTabBtnActive]}
                        onPress={() => setBottomTab(key)}
                        activeOpacity={0.7}
                      >
                        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                          <Text style={[s.bottomTabText, bottomTab === key && s.bottomTabTextActive]}>
                            {label}
                          </Text>
                          {badgeCount > 0 && (
                            <View style={{ backgroundColor: key === 'copyPositions' ? '#C9A84C' : '#C9A84C', borderRadius: 8, minWidth: 16, height: 16, alignItems: 'center', justifyContent: 'center', marginLeft: 4, paddingHorizontal: 4 }}>
                              <Text style={{ color: '#000', fontSize: 10, fontWeight: '700' }}>{badgeCount}</Text>
                            </View>
                          )}
                        </View>
                      </TouchableOpacity>
                    );
                  });
                })()}
                {/* Spacer to push close-all button to the right */}
                <View style={{ flex: 1 }} />
                {positions.filter(p => !p.is_copy_trade).length > 0 && (
                  <TouchableOpacity
                    style={{ paddingVertical: 8, paddingHorizontal: 12, backgroundColor: 'rgba(220,53,69,0.15)', borderRadius: 4, alignSelf: 'center' }}
                    onPress={handleCloseAll}
                    disabled={closeAllLoading}
                    activeOpacity={0.7}
                  >
                    <Text style={{ color: '#DC3545', fontSize: 11, fontWeight: '600' }}>
                      {closeAllLoading ? '平仓中...' : '一键平仓'}
                    </Text>
                  </TouchableOpacity>
                )}
              </View>
              <View>
                {bottomTab === 'positions' && (() => {
                  const selfPos = positions.filter(p => !p.is_copy_trade);
                  return selfPos.length > 0
                    ? selfPos.map((p) => <PositionCard key={p.id} position={p} onClose={(id) => closePosition(id)} onUpdated={() => { fetchPositions(); fetchAccount(); }} />)
                    : <View style={s.bottomEmpty}><Text style={{ color: Colors.textMuted, fontSize: 12 }}>暂无持仓</Text></View>;
                })()}
                {bottomTab === 'copyPositions' && (() => {
                  const copyPos = positions.filter(p => p.is_copy_trade);
                  return copyPos.length > 0
                    ? copyPos.map((p) => <PositionCard key={p.id} position={p} onClose={(id) => closePosition(id)} onUpdated={() => { fetchPositions(); fetchAccount(); }} />)
                    : <View style={s.bottomEmpty}><Text style={{ color: Colors.textMuted, fontSize: 12 }}>暂无跟单仓位</Text></View>;
                })()}
                {bottomTab === 'posHistory' && (
                  positionHistory.length > 0
                    ? positionHistory.map((p) => <ClosedPositionCard key={p.id} position={p} />)
                    : <View style={s.bottomEmpty}><Text style={{ color: Colors.textMuted, fontSize: 12 }}>暂无历史仓位</Text></View>
                )}
                {bottomTab === 'orders' && (
                  pendingOrders.length > 0
                    ? pendingOrders.map((o) => <OrderCard key={o.id} order={o} onCancel={(id) => cancelTradingOrder(id)} />)
                    : <View style={s.bottomEmpty}><Text style={{ color: Colors.textMuted, fontSize: 12 }}>暂无委托</Text></View>
                )}
                {bottomTab === 'history' && (
                  orderHistory.length > 0
                    ? orderHistory.map((o) => <OrderCard key={o.id} order={o} />)
                    : <View style={s.bottomEmpty}><Text style={{ color: Colors.textMuted, fontSize: 12 }}>暂无历史</Text></View>
                )}
                {bottomTab === 'analysis' && (
                  <View style={s.bottomEmpty}>
                    <Text style={{ color: '#fff', fontSize: 14, marginBottom: 4 }}>
                      余额: {account?.balance?.toFixed(2) || '0.00'} USDT
                    </Text>
                    <Text style={{ color: '#888', fontSize: 12 }}>
                      冻结: {account?.frozen?.toFixed(2) || '0.00'} | 权益: {account?.equity?.toFixed(2) || '0.00'}
                    </Text>
                  </View>
                )}
              </View>
            </View>
          </View>

          {/* Right: Order Book on top, Execution below */}
          <View style={s.rightPanel}>
            {/* Order Book */}
            <View style={s.orderBookHeader}>
              <Text style={s.orderBookTitle}>委托账本</Text>
            </View>
            <View style={s.obColHeader}>
              <Text style={s.obColLabel}>价格(USDT)</Text>
              <Text style={[s.obColLabel, { textAlign: 'right' }]}>数量</Text>
            </View>
            <View style={s.orderBookContent}>
              {orderBook.asks.map((a, i) => (
                <View key={`ask-${i}`} style={s.obRow}>
                  <View style={[s.obBarAsk, { width: `${a.pct * 100}%` }]} />
                  <Text style={s.obAskPrice}>{formatPrice(a.price, selectedSymbol)}</Text>
                  <Text style={s.obQty}>{a.qty.toFixed(4)}</Text>
                </View>
              ))}
              <OrderBookCurrentPrice price={currentPrice} percentChange={selectedQuote?.percent_change} symbol={selectedSymbol} />
              {orderBook.bids.map((b, i) => (
                <View key={`bid-${i}`} style={s.obRow}>
                  <View style={[s.obBarBid, { width: `${b.pct * 100}%` }]} />
                  <Text style={s.obBidPrice}>{formatPrice(b.price, selectedSymbol)}</Text>
                  <Text style={s.obQty}>{b.qty.toFixed(4)}</Text>
                </View>
              ))}
            </View>

            {/* Long/Short Ratio Bar */}
            <View style={s.lsRatioRow}>
              <Text style={[s.lsLabel, { color: Colors.up }]}>B {orderBook.buyPct}%</Text>
              <View style={s.lsBarTrack}>
                <View style={[s.lsBarBuy, { flex: orderBook.buyPct }]} />
                <View style={[s.lsBarSell, { flex: 100 - orderBook.buyPct }]} />
              </View>
              <Text style={[s.lsLabel, { color: Colors.down }]}>{100 - orderBook.buyPct}% S</Text>
            </View>

            {/* Execution Panel */}
            <View style={s.execPanel}>
              {/* Top bar: margin mode + leverage */}
              <View style={s.execTopBar}>
                {getAssetType(selectedSymbol) === 'crypto' ? (
                  <TouchableOpacity style={s.execTopChip} onPress={() => setMarginMode(marginMode === 'cross' ? 'isolated' : 'cross')} activeOpacity={0.7}>
                    <Text style={s.execTopChipText}>{marginMode === 'cross' ? '全仓' : '逐仓'}</Text>
                  </TouchableOpacity>
                ) : (
                  <View style={s.execTopChip}>
                    <Text style={s.execTopChipText}>{getAssetType(selectedSymbol) === 'forex' ? '外汇' : getAssetType(selectedSymbol) === 'futures' ? '期货' : '股票'}</Text>
                  </View>
                )}
                <TouchableOpacity style={s.execTopChip} onPress={() => setShowLeverageModal(true)} activeOpacity={0.7}>
                  <Text style={s.execTopChipText}>{leverage}X</Text>
                </TouchableOpacity>
              </View>

              {/* Open / Close */}
              <View style={s.openCloseRow}>
                <TouchableOpacity style={[s.openBtn, panelMode === 'open' && s.openBtnActive]} activeOpacity={0.7} onPress={() => setPanelMode('open')}>
                  <Text style={[s.openBtnText, panelMode === 'open' && s.openBtnTextActive]}>开仓</Text>
                </TouchableOpacity>
                <TouchableOpacity style={[s.closeBtn, panelMode === 'close' && s.closeBtnActive]} activeOpacity={0.7} onPress={() => setPanelMode('close')}>
                  <Text style={[s.closeBtnText, panelMode === 'close' && s.closeBtnTextActive]}>平仓</Text>
                </TouchableOpacity>
              </View>

              {panelMode === 'open' ? (<>
              {/* Limit / Market */}
              <View style={s.execTabRow}>
                <TouchableOpacity onPress={() => setOrderType('limit')} activeOpacity={0.7}>
                  <Text style={[s.execTabText, orderType === 'limit' && s.execTabTextActive]}>限价</Text>
                  {orderType === 'limit' && <View style={s.execTabUnderline} />}
                </TouchableOpacity>
                <TouchableOpacity onPress={() => setOrderType('market')} activeOpacity={0.7}>
                  <Text style={[s.execTabText, orderType === 'market' && s.execTabTextActive]}>市价</Text>
                  {orderType === 'market' && <View style={s.execTabUnderline} />}
                </TouchableOpacity>
              </View>

              <View style={s.availRow}>
                <Text style={s.availLabel}>可用</Text>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                  <Text style={s.availValue}>{account?.available?.toFixed(2) || '0.00'} USDT</Text>
                  <TouchableOpacity onPress={() => { console.log('[deposit] btn pressed'); setShowDepositModal(true); }} activeOpacity={0.7} style={{ paddingHorizontal: 6, paddingVertical: 4 }}>
                    <Text style={{ color: '#C9A84C', fontSize: 11, fontWeight: '600' }}>充值</Text>
                  </TouchableOpacity>
                </View>
              </View>

              {orderType === 'limit' && (
                <View style={s.execInputRow}>
                  <Text style={s.execInputLabel}>价格</Text>
                  <TextInput style={s.execInput} value={priceInput} onChangeText={setPriceInput} keyboardType="decimal-pad" placeholderTextColor={Colors.textMuted} />
                  <Text style={s.execInputUnit}>USDT</Text>
                </View>
              )}

              <View style={s.execInputRow}>
                <Text style={s.execInputLabel}>数量</Text>
                <TextInput style={s.execInput} value={qtyInput} onChangeText={(v: string) => { setQtyInput(v); setSliderPct(0); }} placeholder="0.00" keyboardType="decimal-pad" placeholderTextColor={Colors.textMuted} />
                <TouchableOpacity style={s.unitDropdown} activeOpacity={0.7} onPress={() => setShowQtyModeDropdown(!showQtyModeDropdown)}>
                  <Text style={s.execInputUnit}>{qtyModeLabel} ▾</Text>
                </TouchableOpacity>
              </View>
              {showQtyModeDropdown && (
                <View style={s.qtyModeMenu}>
                  <TouchableOpacity style={[s.qtyModeItem, qtyMode === 'coin' && s.qtyModeItemActive]} onPress={() => { setQtyMode('coin'); setShowQtyModeDropdown(false); setQtyInput(''); }} activeOpacity={0.7}>
                    <Text style={s.qtyModeItemText}>币本位 ({baseAsset})</Text>
                  </TouchableOpacity>
                  <TouchableOpacity style={[s.qtyModeItem, qtyMode === 'notional' && s.qtyModeItemActive]} onPress={() => { setQtyMode('notional'); setShowQtyModeDropdown(false); setQtyInput(''); }} activeOpacity={0.7}>
                    <Text style={s.qtyModeItemText}>名义价值 (USDT)</Text>
                  </TouchableOpacity>
                  <TouchableOpacity style={[s.qtyModeItem, qtyMode === 'margin' && s.qtyModeItemActive]} onPress={() => { setQtyMode('margin'); setShowQtyModeDropdown(false); setQtyInput(''); }} activeOpacity={0.7}>
                    <Text style={s.qtyModeItemText}>保证金价值 (USDT)</Text>
                  </TouchableOpacity>
                </View>
              )}

              <View style={s.pctSliderWrap}>
                <input type="range" min={0} max={100} step={1} value={sliderPct} onChange={(e: any) => handleSliderChange(Number(e.target.value))} style={{ width: '100%', height: 4, accentColor: '#C9A84C', cursor: 'pointer' }} />
                <View style={s.pctLabels}>
                  {['0%', '25%', '50%', '75%', '100%'].map((p) => (
                    <Text key={p} style={s.pctLabelText}>{p}</Text>
                  ))}
                </View>
              </View>

              <TouchableOpacity style={s.checkRow} activeOpacity={0.7} onPress={() => setShowTPSL(!showTPSL)}>
                <View style={[s.checkbox, showTPSL && s.checkboxActive]} />
                <Text style={s.checkLabel}>止盈/止损 TP/SL</Text>
              </TouchableOpacity>
              {showTPSL && (
                <>
                  <View style={s.execInputRow}>
                    <Text style={s.execInputLabel}>止盈</Text>
                    <TextInput style={s.execInput} value={tpInput} onChangeText={setTpInput} placeholder="TP 价格" keyboardType="decimal-pad" placeholderTextColor={Colors.textMuted} />
                    <Text style={s.execInputUnit}>USDT</Text>
                  </View>
                  <View style={s.execInputRow}>
                    <Text style={s.execInputLabel}>止损</Text>
                    <TextInput style={s.execInput} value={slInput} onChangeText={setSlInput} placeholder="SL 价格" keyboardType="decimal-pad" placeholderTextColor={Colors.textMuted} />
                    <Text style={s.execInputUnit}>USDT</Text>
                  </View>
                </>
              )}

              <View style={s.actionRow}>
                <TouchableOpacity style={s.longBtn} activeOpacity={0.8} onPress={() => handlePlaceOrder('long')} disabled={orderLoading}>
                  <Text style={s.longBtnText}>{orderLoading ? '...' : '做多 Long'}</Text>
                </TouchableOpacity>
                <TouchableOpacity style={s.shortBtn} activeOpacity={0.8} onPress={() => handlePlaceOrder('short')} disabled={orderLoading}>
                  <Text style={s.shortBtnText}>{orderLoading ? '...' : '做空 Short'}</Text>
                </TouchableOpacity>
              </View>

              <View style={s.infoRow}>
                <Text style={s.infoLabel}>成本</Text>
                <Text style={s.infoValue}>{calcMargin().toFixed(2)} USDT</Text>
              </View>
              <View style={s.infoRow}>
                <Text style={s.infoLabel}>预估强平价</Text>
                <Text style={s.infoValue}>{calcLiqPrice('long').toFixed(2)} / {calcLiqPrice('short').toFixed(2)}</Text>
              </View>

              {/* VIP & Fee Info */}
              {vipInfo && (
                <>
                  <View style={s.infoRow}>
                    <Text style={s.infoLabel}>VIP 等级</Text>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                      <View style={{ backgroundColor: vipInfo.vip_level >= 3 ? '#FFB800' : '#C9A84C', borderRadius: 4, paddingHorizontal: 6, paddingVertical: 1 }}>
                        <Text style={{ color: '#000', fontSize: 10, fontWeight: '700' }}>VIP{vipInfo.vip_level}</Text>
                      </View>
                      <Text style={s.infoValue}>
                        {orderType === 'limit' ? `Maker ${(vipInfo.maker_fee * 100).toFixed(3)}%` : `Taker ${(vipInfo.taker_fee * 100).toFixed(3)}%`}
                      </Text>
                    </View>
                  </View>
                  <View style={s.infoRow}>
                    <Text style={s.infoLabel}>预估手续费</Text>
                    <Text style={s.infoValue}>
                      {(() => {
                        const qty = getActualQty();
                        const price = orderType === 'limit' ? (parseInputNumber(priceInput) || currentPrice) : currentPrice;
                        const rate = orderType === 'limit' ? vipInfo.maker_fee : vipInfo.taker_fee;
                        const fee = qty * price * rate;
                        return fee > 0 ? `${fee.toFixed(4)} USDT` : '--';
                      })()}
                    </Text>
                  </View>
                </>
              )}

              {/* ── Margin Ratio ── */}
              <View style={s.acctSection}>
                <View style={s.acctSectionHeader}>
                  <Text style={s.acctSectionTitle}>保证金比率</Text>
                  <Text style={s.acctSectionBadge}>{marginMode === 'cross' ? 'USDT 全仓' : 'USDT 逐仓'}</Text>
                </View>
                <View style={s.acctDivider} />
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>保证金比率</Text>
                  <Text style={[s.acctRowValue, { color: '#0ECB81' }]}>
                    {account && account.equity > 0 ? ((account.margin_used / account.equity) * 100).toFixed(2) : '0.00'}%
                  </Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>维持保证金</Text>
                  <Text style={s.acctRowValue}>{account?.margin_used?.toFixed(2) || '0.00'} USDT</Text>
                </View>
              </View>

              {/* ── Futures Assets ── */}
              <View style={s.acctSection}>
                <View style={s.acctSectionHeader}>
                  <Text style={s.acctSectionTitle}>合约资产</Text>
                  <Text style={s.acctSectionBadge}>USDT</Text>
                </View>
                <View style={s.acctDivider} />
                <Text style={s.acctBalance}>{account?.equity?.toFixed(2) || '0.00'} USDT</Text>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>可用</Text>
                  <Text style={s.acctRowValue}>{account?.available?.toFixed(2) || '0.00'} USDT</Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>已冻结</Text>
                  <Text style={s.acctRowValue}>{account?.frozen?.toFixed(2) || '0.00'} USDT</Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>未实现盈亏</Text>
                  <Text style={[s.acctRowValue, { color: (account?.unrealized_pnl ?? 0) >= 0 ? '#0ECB81' : '#F6465D' }]}>
                    {(account?.unrealized_pnl ?? 0) >= 0 ? '+' : ''}{account?.unrealized_pnl?.toFixed(2) || '0.00'} USDT
                  </Text>
                </View>
              </View>

              {/* ── Contract Info ── */}
              <View style={s.acctSection}>
                <Text style={s.acctSectionTitle}>合约信息</Text>
                <View style={s.acctDivider} />
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>合约</Text>
                  <Text style={s.acctRowValue}>{selectedSymbol.replace('/', '')}</Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>结算方式</Text>
                  <Text style={s.acctRowValue}>永续</Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>标的资产</Text>
                  <Text style={s.acctRowValue}>{selectedSymbol.replace('/', '')} Index</Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>保证金资产</Text>
                  <Text style={s.acctRowValue}>USDT</Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>最小价格变动</Text>
                  <Text style={s.acctRowValue}>0.1 USDT</Text>
                </View>
                <View style={s.acctRow}>
                  <Text style={s.acctRowLabel}>最低维持保证金</Text>
                  <Text style={s.acctRowValue}>0.50%</Text>
                </View>
              </View>
              </>) : (
              /* Close Position Panel */
              <View style={{ gap: 8 }}>
                {positions.length === 0 ? (
                  <Text style={{ color: '#666', fontSize: 12, textAlign: 'center', marginTop: 20 }}>暂无持仓</Text>
                ) : (
                  positions.map((pos) => (
                    <PositionCard key={pos.id} position={pos} onClose={(id) => closePosition(id)} onUpdated={() => { fetchPositions(); fetchAccount(); }} />
                  ))
                )}
              </View>
              )}
            </View>
          </View>
        </View>
        </ScrollView>

        {/* Leverage Modal */}
        {showLeverageModal && (() => {
          const config = LEVERAGE_CONFIG[getAssetType(selectedSymbol)];
          return (
            <View style={s.leverageModalOverlay}>
              <View style={s.leverageModal}>
                <View style={s.leverageModalHeader}>
                  <Text style={s.leverageModalTitle}>调整杠杆</Text>
                  <TouchableOpacity onPress={() => setShowLeverageModal(false)} activeOpacity={0.7}>
                    <Text style={s.leverageModalClose}>✕</Text>
                  </TouchableOpacity>
                </View>
                <Text style={s.leverageModalValue}>{leverage}x</Text>
                <View style={s.leverageModalSlider}>
                  <input
                    type="range"
                    min={0}
                    max={config.steps.length - 1}
                    step={1}
                    value={config.steps.indexOf(leverage) >= 0 ? config.steps.indexOf(leverage) : 0}
                    onChange={(e: any) => setLeverage(config.steps[parseInt(e.target.value, 10)])}
                    style={{ width: '100%', height: 6, accentColor: '#C9A84C', cursor: 'pointer' }}
                  />
                </View>
                <View style={s.leverageModalSteps}>
                  {config.steps.map((lv) => (
                    <TouchableOpacity
                      key={lv}
                      style={[s.leverageModalChip, leverage === lv && s.leverageModalChipActive]}
                      onPress={() => setLeverage(lv)}
                      activeOpacity={0.7}
                    >
                      <Text style={[s.leverageModalChipText, leverage === lv && s.leverageModalChipTextActive]}>{lv}x</Text>
                    </TouchableOpacity>
                  ))}
                </View>
                <Text style={s.leverageModalHint}>最大可用杠杆 {config.max}x</Text>
                <TouchableOpacity style={s.leverageModalConfirm} onPress={() => setShowLeverageModal(false)} activeOpacity={0.8}>
                  <Text style={s.leverageModalConfirmText}>确认</Text>
                </TouchableOpacity>
              </View>
            </View>
          );
        })()}

        {/* Overlay panels */}
        <IndicatorsPanel
          visible={showIndicatorsPanel}
          activeIndicators={activeIndicators}
          onToggleIndicator={handleToggleIndicator}
          onRemoveIndicator={handleRemoveIndicator}
          onClose={() => setShowIndicatorsPanel(false)}
        />
        <ChartTypeDropdown
          visible={showChartTypeDropdown}
          currentType={chartType}
          onSelect={setChartType}
          onClose={() => setShowChartTypeDropdown(false)}
        />
        <DrawingToolsSettings
          visible={showDrawingToolsSettings}
          enabledTools={enabledTools}
          onToggleTool={handleToggleDrawingTool}
          onResetDefaults={handleResetDrawingTools}
          onClose={() => setShowDrawingToolsSettings(false)}
        />

        {/* Deposit Modal (Desktop) */}
        {showDepositModal && (
          <View style={s.leverageModalOverlay}>
            <View style={[s.leverageModal, { width: 340 }]}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                <Text style={{ color: '#fff', fontSize: 16, fontWeight: '700' }}>充值 USDT</Text>
                <TouchableOpacity onPress={() => setShowDepositModal(false)}>
                  <Text style={{ color: '#888', fontSize: 18 }}>✕</Text>
                </TouchableOpacity>
              </View>
              <Text style={{ color: '#888', fontSize: 12, marginBottom: 12 }}>当前余额: {account?.balance?.toFixed(2) || '0.00'} USDT</Text>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 16 }}>
                {[100, 500, 1000, 5000, 10000, 50000].map((amt) => (
                  <TouchableOpacity
                    key={amt}
                    style={{ backgroundColor: 'rgba(201,168,76,0.15)', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 6 }}
                    onPress={() => handleDeposit(amt)}
                    activeOpacity={0.7}
                  >
                    <Text style={{ color: '#C9A84C', fontSize: 13, fontWeight: '600' }}>{amt.toLocaleString()}</Text>
                  </TouchableOpacity>
                ))}
              </View>
              <View style={{ flexDirection: 'row', gap: 8 }}>
                <TextInput
                  style={{ flex: 1, backgroundColor: '#1a1a1a', color: '#fff', borderRadius: 6, paddingHorizontal: 12, paddingVertical: 8, fontSize: 14, borderWidth: 1, borderColor: '#333' }}
                  value={depositAmount}
                  onChangeText={setDepositAmount}
                  placeholder="自定义金额"
                  keyboardType="decimal-pad"
                  placeholderTextColor="#666"
                />
                <TouchableOpacity
                  style={{ backgroundColor: '#C9A84C', paddingHorizontal: 20, paddingVertical: 8, borderRadius: 6, justifyContent: 'center' }}
                  onPress={() => {
                    const amt = parseFloat(depositAmount);
                    if (amt > 0) handleDeposit(amt);
                  }}
                  activeOpacity={0.7}
                >
                  <Text style={{ color: '#000', fontSize: 13, fontWeight: '700' }}>充值</Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
        )}
      </View>
    );
  }

  /* ═══════ Mobile Layout ═══════ */
  return (
    <View style={s.root}>
      {/* Symbol Dropdown */}
      <SymbolDropdown
        visible={showDropdown}
        selectedSymbol={selectedSymbol}
        onSelect={handleSelectSymbol}
        onClose={() => setShowDropdown(false)}
        quotes={quotes}
      />

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 100 }} showsVerticalScrollIndicator={false}>
        {/* Symbol selector trigger */}
        <TouchableOpacity
          style={s.mobileSymTrigger}
          onPress={() => setShowDropdown(true)}
          activeOpacity={0.7}
        >
          <Text style={s.mobileSymTriggerText}>{selectedSymbol}</Text>
          <Text style={s.symbolTriggerArrow}>▼</Text>
        </TouchableOpacity>

        {/* Price header */}
        <MobilePriceHeader price={currentPrice} percentChange={selectedQuote?.percent_change} symbol={selectedSymbol} />

        {/* Stats */}
        <View style={s.mobileStatsRow}>
          <View style={s.mobileStatItem}>
            <Text style={s.statLabel}>涨跌额</Text>
            <Text style={[s.statValue, { color: changeColor(selectedQuote?.percent_change) }]}>
              {selectedQuote?.change != null ? `${selectedQuote.change >= 0 ? '+' : '-'}${fmtChange(Math.abs(selectedQuote.change), selectedSymbol, currentPrice)}` : '--'}
            </Text>
          </View>
          <View style={s.mobileStatItem}>
            <Text style={s.statLabel}>涨跌幅</Text>
            <Text style={[s.statValue, { color: changeColor(selectedQuote?.percent_change) }]}>
              {formatChange(selectedQuote?.percent_change)}
            </Text>
          </View>
          <View style={s.mobileStatItem}>
            <Text style={s.statLabel}>最高</Text>
            <Text style={s.statValue}>{formatPrice(selectedQuote?.high, selectedSymbol)}</Text>
          </View>
          <View style={s.mobileStatItem}>
            <Text style={s.statLabel}>最低</Text>
            <Text style={s.statValue}>{formatPrice(selectedQuote?.low, selectedSymbol)}</Text>
          </View>
          <View style={s.mobileStatItem}>
            <Text style={s.statLabel}>成交量</Text>
            <Text style={s.statValue}>
              {selectedQuote?.volume
                ? selectedQuote.volume >= 1e6
                  ? `${(selectedQuote.volume / 1e6).toFixed(1)}M`
                  : selectedQuote.volume.toFixed(2)
                : '--'}
            </Text>
          </View>
          {fundingRate?.fundingRate != null && (
            <View style={s.mobileStatItem}>
              <Text style={s.statLabel}>资金费率</Text>
              <Text style={[s.statValue, { color: parseFloat(fundingRate.fundingRate) >= 0 ? '#0ECB81' : '#F6465D', fontSize: 10 }]}>
                {(parseFloat(fundingRate.fundingRate) * 100).toFixed(4)}%
              </Text>
            </View>
          )}
          <View style={[s.mobileStatItem, { flexDirection: 'row', alignItems: 'center', gap: 4 }]}>
            <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: !netConnected ? '#F6465D' : netLatency < 100 ? '#0ECB81' : netLatency < 300 ? '#F0B90B' : '#F6465D' }} />
            <View>
              <Text style={s.statLabel}>延迟</Text>
              <Text style={[s.statValue, { color: !netConnected ? '#F6465D' : netLatency < 100 ? '#0ECB81' : netLatency < 300 ? '#F0B90B' : '#F6465D', fontSize: 10 }]}>
                {!netConnected ? '断开' : netLatency >= 0 ? `${netLatency}ms` : '...'}
              </Text>
            </View>
          </View>
        </View>

        {/* Mobile network disconnected banner */}
        {!netConnected && (
          <View style={{ backgroundColor: 'rgba(246,70,93,0.15)', paddingVertical: 6, paddingHorizontal: 12, flexDirection: 'row', alignItems: 'center', gap: 6, marginHorizontal: 8, marginBottom: 4, borderRadius: 4 }}>
            <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: '#F6465D' }} />
            <Text style={{ color: '#F6465D', fontSize: 11 }}>网络已断开，行情暂停，重连中...</Text>
          </View>
        )}

        {/* Timeframe + chart type bar */}
        <View style={s.mobileTfRow}>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 4, paddingHorizontal: 4 }}>
            {TIMEFRAMES_MAIN.map((tf) => (
              <TouchableOpacity
                key={tf}
                style={[s.tfBtn, timeframe === tf && s.tfBtnActive]}
                onPress={() => setTimeframe(tf)}
                activeOpacity={0.7}
              >
                <Text style={[s.tfText, timeframe === tf && s.tfTextActive]}>
                  {TIMEFRAME_LABELS[tf]}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
          <View style={s.chartTypeRow}>
            <TouchableOpacity
              style={[s.chartTypeBtn, showChartTypeDropdown && s.chartTypeBtnActive]}
              onPress={() => setShowChartTypeDropdown(!showChartTypeDropdown)}
              activeOpacity={0.7}
            >
              <Text style={[s.chartTypeIcon, showChartTypeDropdown && s.chartTypeIconActive]}>
                {getChartTypeIcon(chartType)} ▾
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[s.chartTypeBtn, activeIndicators.length > 0 && s.chartTypeBtnActive]}
              onPress={() => setShowIndicatorsPanel(true)}
              activeOpacity={0.7}
            >
              <Text style={[s.chartTypeIcon, activeIndicators.length > 0 && s.chartTypeIconActive]}>
                ƒx
              </Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Chart */}
        <View style={s.mobileChart}>
          <OhlcOverlay data={crosshairData} symbol={selectedSymbol} />
          {klinesLoading && klines.length === 0 ? (
            <SkeletonChart />
          ) : klines.length > 0 ? (
            <TradingViewChart
              klines={klines}
              symbol={selectedSymbol}
              chartType={chartType}
              activeIndicators={activeIndicators}
              onCrosshairData={setCrosshairData}
              realtimePrice={currentPrice}
            />
          ) : (
            <Text style={{ color: Colors.textMuted, fontSize: 13 }}>暂无K线数据</Text>
          )}
        </View>

        {/* Order Book (compact) */}
        <View style={s.mobileOrderBook}>
          <Text style={s.orderBookTitle}>委托账本</Text>
          <View style={{ flexDirection: 'row', gap: 12, marginTop: 10 }}>
            {/* Bids side */}
            <View style={{ flex: 1 }}>
              {orderBook.bids.map((b, i) => (
                <View key={i} style={s.obRow}>
                  <View style={[s.obBarBid, { width: `${b.pct * 100}%` }]} />
                  <Text style={s.obBidPrice}>{formatPrice(b.price, selectedSymbol)}</Text>
                  <Text style={s.obQty}>{b.qty.toFixed(3)}</Text>
                </View>
              ))}
            </View>
            {/* Asks side */}
            <View style={{ flex: 1 }}>
              {orderBook.asks.map((a, i) => (
                <View key={i} style={s.obRow}>
                  <View style={[s.obBarAsk, { width: `${a.pct * 100}%` }]} />
                  <Text style={s.obAskPrice}>{formatPrice(a.price, selectedSymbol)}</Text>
                  <Text style={s.obQty}>{a.qty.toFixed(3)}</Text>
                </View>
              ))}
            </View>
          </View>

          {/* Long/Short Ratio Bar */}
          <View style={s.lsRatioRow}>
            <Text style={[s.lsLabel, { color: Colors.up }]}>B {orderBook.buyPct}%</Text>
            <View style={s.lsBarTrack}>
              <View style={[s.lsBarBuy, { flex: orderBook.buyPct }]} />
              <View style={[s.lsBarSell, { flex: 100 - orderBook.buyPct }]} />
            </View>
            <Text style={[s.lsLabel, { color: Colors.down }]}>{100 - orderBook.buyPct}% S</Text>
          </View>
        </View>

        {/* Execution — Binance-style (mobile) */}
        <View style={[s.execPanel, { marginTop: 12 }]}>
          {/* Top bar */}
          <View style={s.execTopBar}>
            {getAssetType(selectedSymbol) === 'crypto' ? (
              <TouchableOpacity style={s.execTopChip} onPress={() => setMarginMode(marginMode === 'cross' ? 'isolated' : 'cross')} activeOpacity={0.7}>
                <Text style={s.execTopChipText}>{marginMode === 'cross' ? '全仓' : '逐仓'}</Text>
              </TouchableOpacity>
            ) : (
              <View style={s.execTopChip}>
                <Text style={s.execTopChipText}>{getAssetType(selectedSymbol) === 'forex' ? '外汇' : getAssetType(selectedSymbol) === 'futures' ? '期货' : '股票'}</Text>
              </View>
            )}
            <TouchableOpacity style={s.execTopChip} onPress={() => setShowLeverageModal(true)} activeOpacity={0.7}>
              <Text style={s.execTopChipText}>{leverage}X</Text>
            </TouchableOpacity>
          </View>

          {/* Open / Close */}
          <View style={s.openCloseRow}>
            <TouchableOpacity style={[s.openBtn, panelMode === 'open' && s.openBtnActive]} activeOpacity={0.7} onPress={() => setPanelMode('open')}>
              <Text style={[s.openBtnText, panelMode === 'open' && s.openBtnTextActive]}>开仓</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[s.closeBtn, panelMode === 'close' && s.closeBtnActive]} activeOpacity={0.7} onPress={() => setPanelMode('close')}>
              <Text style={[s.closeBtnText, panelMode === 'close' && s.closeBtnTextActive]}>平仓</Text>
            </TouchableOpacity>
          </View>

          {panelMode === 'open' ? (<>
          {/* Order type tabs */}
          <View style={s.execTabRow}>
            <TouchableOpacity onPress={() => setOrderType('limit')} activeOpacity={0.7}>
              <Text style={[s.execTabText, orderType === 'limit' && s.execTabTextActive]}>限价</Text>
              {orderType === 'limit' && <View style={s.execTabUnderline} />}
            </TouchableOpacity>
            <TouchableOpacity onPress={() => setOrderType('market')} activeOpacity={0.7}>
              <Text style={[s.execTabText, orderType === 'market' && s.execTabTextActive]}>市价</Text>
              {orderType === 'market' && <View style={s.execTabUnderline} />}
            </TouchableOpacity>
          </View>

          {/* Available */}
          <View style={s.availRow}>
            <Text style={s.availLabel}>可用</Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <Text style={s.availValue}>{account?.available?.toFixed(2) || '0.00'} USDT</Text>
              <TouchableOpacity onPress={() => { console.log('[deposit] btn pressed'); setShowDepositModal(true); }} activeOpacity={0.7} style={{ paddingHorizontal: 6, paddingVertical: 4 }}>
                <Text style={{ color: '#C9A84C', fontSize: 11, fontWeight: '600' }}>充值</Text>
              </TouchableOpacity>
            </View>
          </View>

          {/* Price input */}
          {orderType === 'limit' && (
            <View style={s.execInputRow}>
              <Text style={s.execInputLabel}>价格</Text>
              <TextInput style={s.execInput} value={priceInput} onChangeText={setPriceInput} keyboardType="decimal-pad" placeholderTextColor={Colors.textMuted} />
              <Text style={s.execInputUnit}>USDT</Text>
            </View>
          )}

          {/* Quantity */}
          <View style={s.execInputRow}>
            <Text style={s.execInputLabel}>数量</Text>
            <TextInput style={s.execInput} value={qtyInput} onChangeText={(v: string) => { setQtyInput(v); setSliderPct(0); }} placeholder="0.00" keyboardType="decimal-pad" placeholderTextColor={Colors.textMuted} />
            <TouchableOpacity style={s.unitDropdown} activeOpacity={0.7} onPress={() => setShowQtyModeDropdown(!showQtyModeDropdown)}>
              <Text style={s.execInputUnit}>{qtyModeLabel} ▾</Text>
            </TouchableOpacity>
          </View>
          {showQtyModeDropdown && (
            <View style={s.qtyModeMenu}>
              <TouchableOpacity style={[s.qtyModeItem, qtyMode === 'coin' && s.qtyModeItemActive]} onPress={() => { setQtyMode('coin'); setShowQtyModeDropdown(false); setQtyInput(''); }} activeOpacity={0.7}>
                <Text style={s.qtyModeItemText}>币本位 ({baseAsset})</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[s.qtyModeItem, qtyMode === 'notional' && s.qtyModeItemActive]} onPress={() => { setQtyMode('notional'); setShowQtyModeDropdown(false); setQtyInput(''); }} activeOpacity={0.7}>
                <Text style={s.qtyModeItemText}>名义价值 (USDT)</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[s.qtyModeItem, qtyMode === 'margin' && s.qtyModeItemActive]} onPress={() => { setQtyMode('margin'); setShowQtyModeDropdown(false); setQtyInput(''); }} activeOpacity={0.7}>
                <Text style={s.qtyModeItemText}>保证金价值 (USDT)</Text>
              </TouchableOpacity>
            </View>
          )}

          {/* Percentage slider */}
          <View style={s.pctSliderWrap}>
            <input type="range" min={0} max={100} step={1} defaultValue={0} style={{ width: '100%', height: 4, accentColor: '#C9A84C', cursor: 'pointer' }} />
            <View style={s.pctLabels}>
              {['0%', '25%', '50%', '75%', '100%'].map((p) => (
                <Text key={p} style={s.pctLabelText}>{p}</Text>
              ))}
            </View>
          </View>

          {/* TP/SL */}
          <TouchableOpacity style={s.checkRow} activeOpacity={0.7}>
            <View style={s.checkbox} />
            <Text style={s.checkLabel}>止盈/止损 TP/SL</Text>
          </TouchableOpacity>

          {/* Long / Short */}
          <View style={s.actionRow}>
            <TouchableOpacity style={s.longBtn} activeOpacity={0.8} onPress={() => handlePlaceOrder('long')} disabled={orderLoading}>
              <Text style={s.longBtnText}>{orderLoading ? '...' : '做多 Long'}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.shortBtn} activeOpacity={0.8} onPress={() => handlePlaceOrder('short')} disabled={orderLoading}>
              <Text style={s.shortBtnText}>{orderLoading ? '...' : '做空 Short'}</Text>
            </TouchableOpacity>
          </View>

          {/* Info */}
          <View style={s.infoRow}>
            <Text style={s.infoLabel}>成本</Text>
            <Text style={s.infoValue}>{calcMargin().toFixed(2)} USDT</Text>
          </View>
          <View style={s.infoRow}>
            <Text style={s.infoLabel}>预估强平价</Text>
            <Text style={s.infoValue}>{calcLiqPrice('long').toFixed(2)} / {calcLiqPrice('short').toFixed(2)}</Text>
          </View>

          {/* VIP & Fee Info */}
          {vipInfo && (
            <>
              <View style={s.infoRow}>
                <Text style={s.infoLabel}>VIP 等级</Text>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                  <View style={{ backgroundColor: vipInfo.vip_level >= 3 ? '#FFB800' : '#C9A84C', borderRadius: 4, paddingHorizontal: 6, paddingVertical: 1 }}>
                    <Text style={{ color: '#000', fontSize: 10, fontWeight: '700' }}>VIP{vipInfo.vip_level}</Text>
                  </View>
                  <Text style={s.infoValue}>
                    {orderType === 'limit' ? `Maker ${(vipInfo.maker_fee * 100).toFixed(3)}%` : `Taker ${(vipInfo.taker_fee * 100).toFixed(3)}%`}
                  </Text>
                </View>
              </View>
              <View style={s.infoRow}>
                <Text style={s.infoLabel}>预估手续费</Text>
                <Text style={s.infoValue}>
                  {(() => {
                    const qty = getActualQty();
                    const price = orderType === 'limit' ? (parseInputNumber(priceInput) || currentPrice) : currentPrice;
                    const rate = orderType === 'limit' ? vipInfo.maker_fee : vipInfo.taker_fee;
                    const fee = qty * price * rate;
                    return fee > 0 ? `${fee.toFixed(4)} USDT` : '--';
                  })()}
                </Text>
              </View>
            </>
          )}
          </>) : (
          /* Close Position Panel (mobile) */
          <View style={{ gap: 8, paddingHorizontal: 4 }}>
            {positions.length === 0 ? (
              <Text style={{ color: '#666', fontSize: 12, textAlign: 'center', marginTop: 20 }}>暂无持仓</Text>
            ) : (
              positions.map((pos) => (
                <PositionCard key={pos.id} position={pos} onClose={(id) => closePosition(id)} onUpdated={() => { fetchPositions(); fetchAccount(); }} />
              ))
            )}
          </View>
          )}
        </View>
      </ScrollView>

      {/* Overlay panels (mobile) */}
      <IndicatorsPanel
        visible={showIndicatorsPanel}
        activeIndicators={activeIndicators}
        onToggleIndicator={handleToggleIndicator}
        onRemoveIndicator={handleRemoveIndicator}
        onClose={() => setShowIndicatorsPanel(false)}
      />
      <ChartTypeDropdown
        visible={showChartTypeDropdown}
        currentType={chartType}
        onSelect={setChartType}
        onClose={() => setShowChartTypeDropdown(false)}
      />
      <DrawingToolsSettings
        visible={showDrawingToolsSettings}
        enabledTools={enabledTools}
        onToggleTool={handleToggleDrawingTool}
        onResetDefaults={handleResetDrawingTools}
        onClose={() => setShowDrawingToolsSettings(false)}
      />

      {/* Deposit Modal */}
      {showDepositModal && (
        <View style={s.leverageModalOverlay}>
          <View style={[s.leverageModal, { width: 340 }]}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
              <Text style={{ color: '#fff', fontSize: 16, fontWeight: '700' }}>充值 USDT</Text>
              <TouchableOpacity onPress={() => setShowDepositModal(false)}>
                <Text style={{ color: '#888', fontSize: 18 }}>✕</Text>
              </TouchableOpacity>
            </View>
            <Text style={{ color: '#888', fontSize: 12, marginBottom: 12 }}>当前余额: {account?.balance?.toFixed(2) || '0.00'} USDT</Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 16 }}>
              {[100, 500, 1000, 5000, 10000, 50000].map((amt) => (
                <TouchableOpacity
                  key={amt}
                  style={{ backgroundColor: 'rgba(201,168,76,0.15)', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 6 }}
                  onPress={() => handleDeposit(amt)}
                  activeOpacity={0.7}
                >
                  <Text style={{ color: '#C9A84C', fontSize: 13, fontWeight: '600' }}>{amt.toLocaleString()}</Text>
                </TouchableOpacity>
              ))}
            </View>
            <View style={{ flexDirection: 'row', gap: 8 }}>
              <TextInput
                style={{ flex: 1, backgroundColor: '#1a1a1a', color: '#fff', borderRadius: 6, paddingHorizontal: 12, paddingVertical: 8, fontSize: 14, borderWidth: 1, borderColor: '#333' }}
                value={depositAmount}
                onChangeText={setDepositAmount}
                placeholder="自定义金额"
                keyboardType="decimal-pad"
                placeholderTextColor="#666"
              />
              <TouchableOpacity
                style={{ backgroundColor: '#C9A84C', paddingHorizontal: 20, paddingVertical: 8, borderRadius: 6, justifyContent: 'center' }}
                onPress={() => {
                  const amt = parseFloat(depositAmount);
                  if (amt > 0) handleDeposit(amt);
                }}
                activeOpacity={0.7}
              >
                <Text style={{ color: '#000', fontSize: 13, fontWeight: '700' }}>充值</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      )}
    </View>
  );
}

/* ════════════════════════════════════════
   Styles
   ════════════════════════════════════════ */

const s = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: Colors.background,
  },

  /* ── Desktop 3-column ── */
  desktopRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },

  /* Symbol trigger button */
  symbolTrigger: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 4,
    paddingRight: 12,
  },
  symbolTriggerText: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
    fontFamily: 'monospace',
  },
  symbolTriggerPrice: {
    fontSize: 14,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  symbolTriggerArrow: {
    color: Colors.textMuted,
    fontSize: 10,
  },
  priceBlock: {
    gap: 1,
    marginRight: 8,
  },
  priceBig: {
    fontSize: 18,
    fontWeight: '800',
    fontFamily: 'monospace',
  },
  priceUsd: {
    fontSize: 10,
    color: Colors.textMuted,
    fontFamily: 'monospace',
  },
  statDivider: {
    width: 1,
    height: 24,
    backgroundColor: 'rgba(77,70,53,0.2)',
  },
  tickerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  tickerRowActive: {
    backgroundColor: 'rgba(42,42,42,0.3)',
  },
  tickerSymbol: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '700',
  },
  tickerPrice: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 12,
    textAlign: 'right',
  },
  tickerChange: {
    flex: 1,
    fontSize: 12,
    textAlign: 'right',
  },

  /* Middle panel */
  middlePanel: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  statsBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 12,
    backgroundColor: '#131313',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.1)',
    gap: 24,
  },
  statItem: {
    gap: 2,
  },
  statBorder: {
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(77,70,53,0.1)',
    paddingLeft: 24,
  },
  statLabel: {
    fontSize: 10,
    color: Colors.textMuted,
    letterSpacing: 0.5,
  },
  statValue: {
    fontSize: 13,
    color: Colors.textActive,
    fontWeight: '700',
  },
  /* Timeframe bar (separate row below stats) */
  timeframeBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 6,
    backgroundColor: '#131313',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.15)',
    gap: 6,
  },
  tfRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
  },
  tfBtn: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 4,
  },
  tfBtnActive: {
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  tfText: {
    fontSize: 12,
    color: Colors.textMuted,
    fontWeight: '500',
  },
  tfTextActive: {
    color: Colors.textActive,
    fontWeight: '700',
  },

  /* More timeframe overlay */
  moreTfOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 50,
  },
  moreTfBackdrop: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
  },
  moreTfDropdown: {
    position: 'absolute',
    top: 90,
    left: 20,
    backgroundColor: '#1a1a1a',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.3)',
    padding: 12,
    zIndex: 51,
    ...(Platform.OS === 'web' ? { boxShadow: '0 4px 20px rgba(0,0,0,0.6)' } : {}),
  },
  moreTfGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    maxWidth: 320,
  },
  moreTfItem: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 4,
    backgroundColor: 'rgba(42,42,42,0.5)',
    minWidth: 70,
    alignItems: 'center',
  },
  moreTfItemActive: {
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  moreTfText: {
    fontSize: 12,
    color: Colors.textMuted,
    fontWeight: '500',
  },
  moreTfTextActive: {
    color: Colors.textActive,
    fontWeight: '700',
  },

  /* Chart type icons */
  chartTypeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(77,70,53,0.2)',
    paddingLeft: 8,
    marginLeft: 4,
  },
  chartTypeBtn: {
    width: 32,
    height: 28,
    borderRadius: 4,
    justifyContent: 'center',
    alignItems: 'center',
  },
  chartTypeBtnActive: {
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  chartTypeIcon: {
    fontSize: 12,
    color: Colors.textMuted,
    fontFamily: 'monospace',
    fontWeight: '700',
  },
  chartTypeIconActive: {
    color: Colors.textActive,
  },
  chartArea: {
    height: 500,
    backgroundColor: Colors.background,
    overflow: 'hidden',
  },
  chartPlaceholder: {
    alignItems: 'center',
    gap: 8,
  },
  chartWatermark: {
    fontSize: 36,
    fontWeight: '800',
    color: 'rgba(242,202,80,0.05)',
    letterSpacing: 16,
  },

  /* Bottom panel */
  bottomPanel: {
    height: 280,
    backgroundColor: '#131313',
    borderTopWidth: 1,
    borderTopColor: 'rgba(77,70,53,0.1)',
  },
  bottomTabRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.1)',
    paddingHorizontal: 20,
  },
  bottomTabBtn: {
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
  bottomTabBtnActive: {
    borderBottomWidth: 2,
    borderBottomColor: Colors.primary,
  },
  bottomTabText: {
    fontSize: 11,
    color: Colors.textMuted,
  },
  bottomTabTextActive: {
    color: Colors.primary,
    fontWeight: '700',
  },
  bottomEmpty: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 6,
  },

  /* Right panel */
  rightPanel: {
    width: 280,
    maxWidth: 280,
    flexShrink: 0,
    flexGrow: 0,
    backgroundColor: '#131313',
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(77,70,53,0.1)',
  },
  obColHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.1)',
  },
  obColLabel: {
    fontSize: 10,
    color: Colors.textMuted,
  },

  /* Order book */
  orderBookSection: {
    flex: 1,
  },
  orderBookHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 6,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.1)',
  },
  orderBookTitle: {
    fontSize: 12,
    fontWeight: '700',
    color: Colors.textActive,
  },
  orderBookContent: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    gap: 1,
  },
  obRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 3,
    paddingHorizontal: 4,
    position: 'relative',
  },
  obBarAsk: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: 0,
    backgroundColor: 'rgba(255,180,171,0.08)',
  },
  obBarBid: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: 0,
    backgroundColor: 'rgba(102,228,185,0.08)',
  },
  obAskPrice: {
    fontSize: 11,
    color: Colors.down,
  },
  obBidPrice: {
    fontSize: 11,
    color: Colors.up,
  },
  obQty: {
    fontSize: 11,
    color: Colors.textActive,
  },
  lsRatioRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 8,
    paddingVertical: 8,
  },
  lsLabel: {
    fontSize: 11,
    fontWeight: '700',
    minWidth: 38,
  },
  lsBarTrack: {
    flex: 1,
    flexDirection: 'row',
    height: 6,
    borderRadius: 3,
    overflow: 'hidden',
  },
  lsBarBuy: {
    backgroundColor: Colors.up,
    borderRadius: 3,
  },
  lsBarSell: {
    backgroundColor: Colors.down,
    borderRadius: 3,
  },
  obCurrentRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 8,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: 'rgba(77,70,53,0.1)',
    marginVertical: 2,
  },
  obCurrentPrice: {
    fontSize: 16,
    fontWeight: '700',
  },
  obCurrentSub: {
    fontSize: 10,
    color: Colors.textMuted,
  },

  /* Execution panel — Binance-style */
  execPanel: {
    borderTopWidth: 1,
    borderTopColor: 'rgba(77,70,53,0.2)',
    backgroundColor: 'rgba(28,27,27,0.6)',
    padding: 10,
    gap: 8,
  },
  execTopBar: {
    flexDirection: 'row',
    gap: 8,
  },
  execTopChip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 4,
    backgroundColor: 'rgba(42,42,42,0.8)',
  },
  execTopChipText: {
    fontSize: 12,
    fontWeight: '700',
    color: Colors.textActive,
  },
  openCloseRow: {
    flexDirection: 'row',
    borderRadius: 6,
    overflow: 'hidden',
  },
  openBtn: {
    flex: 1,
    paddingVertical: 8,
    backgroundColor: 'rgba(0,188,140,0.25)',
    alignItems: 'center',
  },
  openBtnText: {
    fontSize: 12,
    fontWeight: '700',
    color: Colors.up,
  },
  closeBtn: {
    flex: 1,
    paddingVertical: 8,
    backgroundColor: 'rgba(42,42,42,0.4)',
    alignItems: 'center',
  },
  closeBtnText: {
    fontSize: 12,
    fontWeight: '600',
    color: Colors.textMuted,
  },
  openBtnActive: {
    backgroundColor: 'rgba(0,188,140,0.35)',
  },
  openBtnTextActive: {
    color: '#0ECB81',
  },
  closeBtnActive: {
    backgroundColor: 'rgba(246,70,93,0.25)',
  },
  closeBtnTextActive: {
    color: '#F6465D',
  },
  execTabRow: {
    flexDirection: 'row',
    gap: 20,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.15)',
    paddingBottom: 8,
  },
  execTabText: {
    fontSize: 13,
    color: Colors.textMuted,
    fontWeight: '500',
  },
  execTabTextActive: {
    color: Colors.textActive,
    fontWeight: '700',
  },
  execTabUnderline: {
    height: 2,
    backgroundColor: Colors.primary,
    borderRadius: 1,
    marginTop: 4,
  },
  availRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  availLabel: {
    fontSize: 11,
    color: Colors.textMuted,
  },
  availValue: {
    fontSize: 11,
    color: Colors.textActive,
  },
  execInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(42,42,42,0.4)',
    borderRadius: 6,
    paddingHorizontal: 10,
    height: 36,
  },
  execInputLabel: {
    fontSize: 11,
    color: Colors.textMuted,
    marginRight: 6,
  },
  execInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 13,
    paddingVertical: 0,
    outlineStyle: 'none',
  } as any,
  execInputUnit: {
    fontSize: 11,
    color: Colors.textMuted,
  },
  unitDropdown: {
    marginLeft: 6,
    paddingHorizontal: 4,
    paddingVertical: 2,
  },
  qtyModeMenu: {
    backgroundColor: '#2A2A2A',
    borderRadius: 6,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    marginTop: 2,
    marginBottom: 4,
    overflow: 'hidden',
  },
  qtyModeItem: {
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  qtyModeItemActive: {
    backgroundColor: 'rgba(201,168,76,0.15)',
  },
  qtyModeItemText: {
    color: '#ccc',
    fontSize: 12,
  },
  pctSliderWrap: {
    gap: 2,
  },
  pctLabels: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  pctLabelText: {
    fontSize: 9,
    color: Colors.textMuted,
  },
  leverageSliderWrap: {
    gap: 4,
  },
  leverageHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  leverageLabel: {
    fontSize: 11,
    color: Colors.textMuted,
  },
  leverageValue: {
    fontSize: 12,
    fontWeight: '700',
    color: Colors.primary,
  },
  /* Leverage Modal */
  leverageModalOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 200,
  },
  leverageModal: {
    backgroundColor: '#1e1e1e',
    borderRadius: 12,
    padding: 24,
    width: 340,
    gap: 16,
    ...(Platform.OS === 'web' ? { boxShadow: '0 8px 32px rgba(0,0,0,0.8)' } : {}),
  },
  leverageModalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  leverageModalTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: Colors.textActive,
  },
  leverageModalClose: {
    fontSize: 18,
    color: Colors.textMuted,
    padding: 4,
  },
  leverageModalValue: {
    fontSize: 32,
    fontWeight: '700',
    color: Colors.primary,
    textAlign: 'center',
  },
  leverageModalSlider: {
    paddingHorizontal: 4,
  },
  leverageModalSteps: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    justifyContent: 'center',
  },
  leverageModalChip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 4,
    backgroundColor: 'rgba(42,42,42,0.6)',
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.15)',
  },
  leverageModalChipActive: {
    backgroundColor: 'rgba(201,168,76,0.2)',
    borderColor: Colors.primary,
  },
  leverageModalChipText: {
    fontSize: 11,
    color: Colors.textMuted,
    fontWeight: '600',
  },
  leverageModalChipTextActive: {
    color: Colors.primary,
  },
  leverageModalHint: {
    fontSize: 11,
    color: Colors.textMuted,
    textAlign: 'center',
  },
  leverageModalConfirm: {
    backgroundColor: Colors.primary,
    borderRadius: 6,
    paddingVertical: 12,
    alignItems: 'center',
  },
  leverageModalConfirmText: {
    fontSize: 14,
    fontWeight: '700',
    color: '#1a1a1a',
  },
  checkRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  checkbox: {
    width: 14,
    height: 14,
    borderRadius: 2,
    borderWidth: 1,
    borderColor: Colors.textMuted,
  },
  checkboxActive: {
    backgroundColor: '#C9A84C',
    borderColor: '#C9A84C',
  },
  checkLabel: {
    fontSize: 11,
    color: Colors.textMuted,
  },
  actionRow: {
    flexDirection: 'row',
    gap: 8,
  },
  longBtn: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 6,
    backgroundColor: '#0ECB81',
    alignItems: 'center',
  },
  longBtnText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '700',
  },
  shortBtn: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 6,
    backgroundColor: '#F6465D',
    alignItems: 'center',
  },
  shortBtnText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '700',
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  infoLabel: {
    fontSize: 10,
    color: Colors.textMuted,
  },
  infoValue: {
    fontSize: 10,
    color: Colors.textActive,
  },
  /* Legacy — used by mobile */
  orderTypeRow: {
    flexDirection: 'row',
    backgroundColor: Colors.background,
    borderRadius: 8,
    padding: 3,
  },
  orderTypeBtn: {
    flex: 1,
    paddingVertical: 8,
    borderRadius: 6,
    alignItems: 'center',
  },
  orderTypeBtnActive: {
    backgroundColor: 'rgba(42,42,42,0.8)',
  },
  orderTypeText: {
    fontSize: 12,
    color: Colors.textMuted,
  },
  orderTypeTextActive: {
    color: Colors.primary,
    fontWeight: '700',
  },
  fieldGroup: {
    gap: 6,
  },
  fieldLabel: {
    fontSize: 10,
    color: Colors.textMuted,
    letterSpacing: 1,
    textTransform: 'uppercase',
    fontWeight: '500',
  },
  fieldInput: {
    backgroundColor: Colors.background,
    borderBottomWidth: 2,
    borderBottomColor: 'rgba(77,70,53,0.3)',
    color: Colors.textActive,
    fontSize: 14,
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  marginModeRow: {
    flexDirection: 'row',
    backgroundColor: Colors.background,
    borderRadius: 6,
    padding: 2,
  },
  marginModeBtn: {
    flex: 1,
    paddingVertical: 6,
    borderRadius: 4,
    alignItems: 'center',
  },
  marginModeBtnActive: {
    backgroundColor: 'rgba(201,168,76,0.15)',
    borderWidth: 1,
    borderColor: 'rgba(201,168,76,0.3)',
  },
  marginModeText: {
    fontSize: 11,
    color: Colors.textMuted,
    fontWeight: '600',
  },
  marginModeTextActive: {
    color: Colors.primary,
  },
  sliderContainer: {
    paddingHorizontal: 2,
    paddingVertical: 4,
  },
  leverageRow: {
    flexDirection: 'row',
    gap: 6,
    flexWrap: 'wrap',
  },
  leverageChip: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 4,
    backgroundColor: 'rgba(42,42,42,0.5)',
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.15)',
  },
  leverageChipActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  leverageChipText: {
    fontSize: 10,
    color: Colors.textMuted,
    fontWeight: '600',
  },
  leverageChipTextActive: {
    color: Colors.primary,
  },
  buyBtn: {
    flex: 1,
    paddingVertical: 14,
    borderRadius: 8,
    backgroundColor: Colors.up,
    alignItems: 'center',
  },
  buyBtnText: {
    color: '#002116',
    fontSize: 13,
    fontWeight: '700',
  },
  sellBtn: {
    flex: 1,
    paddingVertical: 14,
    borderRadius: 8,
    backgroundColor: Colors.down,
    alignItems: 'center',
  },
  sellBtnText: {
    color: '#690005',
    fontSize: 13,
    fontWeight: '700',
  },

  /* ── Mobile layout ── */
  mobileSymTrigger: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.1)',
  },
  mobileSymTriggerText: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
    fontFamily: 'monospace',
  },
  mobilePriceHeader: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  mobileBigPrice: {
    fontSize: 28,
    fontWeight: '800',
  },
  mobilePriceChange: {
    fontSize: 14,
    fontWeight: '600',
  },
  mobileStatsRow: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingBottom: 12,
    gap: 20,
  },
  mobileStatItem: {
    gap: 2,
  },
  mobileTfRow: {
    flexDirection: 'row',
    gap: 6,
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  mobileChart: {
    height: 200,
    marginHorizontal: 12,
    marginBottom: 16,
    borderRadius: 12,
    backgroundColor: 'rgba(28,27,27,0.6)',
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.1)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  mobileOrderBook: {
    marginHorizontal: 12,
    marginBottom: 16,
    padding: 14,
    borderRadius: 12,
    backgroundColor: 'rgba(28,27,27,0.6)',
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.1)',
  },
  mobileExec: {
    marginHorizontal: 12,
    padding: 16,
    borderRadius: 12,
    backgroundColor: 'rgba(28,27,27,0.6)',
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.1)',
    gap: 14,
  },
  acctSection: {
    backgroundColor: '#1C1B1B',
    borderRadius: 8,
    padding: 12,
    marginTop: 12,
  },
  acctSectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  acctSectionTitle: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
  },
  acctSectionBadge: {
    color: '#888',
    fontSize: 11,
  },
  acctDivider: {
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.06)',
    marginVertical: 8,
  },
  acctRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 4,
  },
  acctRowLabel: {
    color: '#666',
    fontSize: 12,
  },
  acctRowValue: {
    color: '#ccc',
    fontSize: 12,
  },
  acctBalance: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 6,
  },
});
