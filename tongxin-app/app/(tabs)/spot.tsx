/**
 * 现货交易独立页（Spot Standalone Page）- Bitunix 风格 4 列布局
 * ================================================================
 * 入口：左侧 Sidebar「现货」菜单。与合约页 /trading 完全隔离。
 *
 * 桌面端（width >= 900）：
 *   ┌────────────────────────────────────────────────────────────────┐
 *   │ SymbolDropdown    24h: 涨跌 · 高 · 低 · 量 · 额                │
 *   ├──────────┬───────────────────────┬─────────┬────────────────────┤
 *   │ 左 280   │  中 flex              │ 240     │ 右 320             │
 *   │ Info 卡  │  K 线 + 指标          │ OB/成交 │ 下单面板          │
 *   ├──────────┴───────────────────────┴─────────┴────────────────────┤
 *   │ Tabs: [当前委托] [历史委托] [资产持仓]  +  表格式订单列表      │
 *   └────────────────────────────────────────────────────────────────┘
 *
 * 移动端：单列垂直堆叠
 *
 * 符号格式映射：
 *   spotApi 返回 "BTC/USDT" / "AAPL/USD"
 *   marketStore + fetchCryptoDepth 用 "BTC/USD" / "AAPL"
 *   toMarketSymbol() 负责 display → market 转换
 */

import { useEffect, useMemo, useState, useCallback, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  useWindowDimensions,
  Alert,
  Platform,
  Modal,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import TradingViewChart from '../../components/chart/TradingViewChart';
import { useMarketStore } from '../../services/store/marketStore';
import {
  spotApi,
  type SpotSupportedSymbol,
  type SpotOrder,
  type SpotAccountInfo,
  type SpotCategory,
} from '../../services/api/spotApi';
import { useAuthStore } from '../../services/store/authStore';
import { fetchCryptoDepth } from '../../services/api/client';
import { transferAssets } from '../../services/api/assetsApi';
import { tradingWs } from '../../services/websocket/tradingWs';
import { Colors } from '../../theme/colors';

/* ════════════════════════════════════════════
   Helpers
   ════════════════════════════════════════════ */

const toMarketSymbol = (spotSymbol: string, category: SpotCategory): string => {
  if (category === 'crypto') {
    // BTC/USDT → BTC/USD（market store / depth API 的格式）
    return spotSymbol.replace('/USDT', '/USD');
  }
  // stocks: AAPL/USD → AAPL
  return spotSymbol.split('/')[0];
};

/**
 * 股票类现货 UI 统一用 USDT 显示
 *   - 数据库里 seed 为 `AAPL/USD, quote_asset='USD'`，但账户只维护 USDT 持仓
 *   - migration 033 跑完后 DB 自动变成 `AAPL/USDT`，该 shim 对 USDT 字符串幂等
 *   - 只影响展示，下单 / API 请求依旧沿用后端原值（由 selectedSymbol 承载）
 */
const toDisplaySymbol = (sym: string): string => sym.replace(/\/USD$/, '/USDT');
const toDisplayQuote = (q: string | undefined | null): string =>
  q === 'USD' ? 'USDT' : q || 'USDT';

const formatPrice = (n: number | null | undefined, precision = 2): string => {
  if (n == null || !isFinite(n)) return '--';
  return n.toLocaleString(undefined, {
    minimumFractionDigits: precision,
    maximumFractionDigits: precision,
  });
};

const formatCompact = (n: number | null | undefined): string => {
  if (n == null || !isFinite(n)) return '--';
  const abs = Math.abs(n);
  if (abs >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (abs >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (abs >= 1e3) return `${(n / 1e3).toFixed(2)}K`;
  return n.toFixed(2);
};

/* ── Seeded PRNG（复用 trading.tsx 的模式） ── */
function seededRng(seed: number) {
  let s = seed | 0;
  return () => {
    s = (s * 1664525 + 1013904223) & 0x7fffffff;
    return s / 0x7fffffff;
  };
}

/* ── Mock orderbook 生成（仅用于非 crypto symbol 或 API 失败兜底） ── */
type OBRow = { price: number; qty: number; pct: number };

function generateMockOrderBook(price: number, tick = 0): { asks: OBRow[]; bids: OBRow[] } {
  if (!price || price <= 0) return { asks: [], bids: [] };
  const rand = seededRng(((Math.round(price) | 0) * 31 + tick) | 0);

  let tickSize: number;
  if (price >= 10000) tickSize = 0.01;
  else if (price >= 100) tickSize = 0.01;
  else if (price >= 1) tickSize = 0.01;
  else if (price >= 0.01) tickSize = 0.0001;
  else tickSize = 0.000001;

  const halfSpread = (1 + Math.floor(rand() * 2)) * tickSize;
  let baseQty: number;
  if (price >= 50000) baseQty = 0.3;
  else if (price >= 2000) baseQty = 1.5;
  else if (price >= 100) baseQty = 15;
  else if (price >= 1) baseQty = 500;
  else baseQty = 50000;

  const genQty = (depth: number): number => {
    const variation = Math.exp((rand() - 0.5) * 1.5);
    let qty = baseQty * (0.5 + depth * 0.15) * variation;
    if (rand() < 0.15) qty *= 2 + rand() * 3;
    if (qty >= 100) qty = Math.round(qty);
    else if (qty >= 1) qty = Math.round(qty * 100) / 100;
    else qty = Math.round(qty * 10000) / 10000;
    return Math.max(qty, tickSize);
  };

  const asks: OBRow[] = [];
  const bids: OBRow[] = [];
  const levels = 10;
  let maxQty = 0;
  for (let i = 1; i <= levels; i++) {
    const skipA = rand() < 0.2 ? 2 : 1;
    const askPrice = price + halfSpread + (i - 1 + (skipA - 1) * 0.5) * tickSize;
    const qtyA = genQty(i);
    if (qtyA > maxQty) maxQty = qtyA;
    asks.push({ price: Math.round(askPrice / tickSize) * tickSize, qty: qtyA, pct: 0 });

    const skipB = rand() < 0.2 ? 2 : 1;
    const bidPrice = price - halfSpread - (i - 1 + (skipB - 1) * 0.5) * tickSize;
    const qtyB = genQty(i);
    if (qtyB > maxQty) maxQty = qtyB;
    bids.push({ price: Math.round(bidPrice / tickSize) * tickSize, qty: qtyB, pct: 0 });
  }
  const m = Math.max(maxQty, 0.001);
  asks.forEach((r) => { r.pct = r.qty / m; });
  bids.forEach((r) => { r.pct = r.qty / m; });
  // asks 需要倒序展示（高价在上）
  return { asks: asks.slice().reverse(), bids };
}

/* ── Mock trades 生成 ── */
type TradeRow = { id: string; price: number; qty: number; side: 'buy' | 'sell'; timestamp: number };

function generateMockTrades(basePrice: number, count = 20): TradeRow[] {
  if (!basePrice || basePrice <= 0) return [];
  const windowKey = Math.floor(Date.now() / 1500);
  const rand = seededRng(windowKey * 37 + Math.round(basePrice));
  const now = Date.now();
  return Array.from({ length: count }, (_, i) => ({
    id: `t-${windowKey}-${i}`,
    price: basePrice * (1 + (rand() - 0.5) * 0.002),
    qty: +(rand() * 0.5 + 0.01).toFixed(4),
    side: rand() > 0.5 ? 'buy' : 'sell',
    timestamp: now - i * 1500,
  }));
}

/* ════════════════════════════════════════════
   Main component
   ════════════════════════════════════════════ */

export default function SpotPage() {
  const { t } = useTranslation();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 900;
  const user = useAuthStore((s) => s.user);

  /* ── Symbols ── */
  const [symbols, setSymbols] = useState<SpotSupportedSymbol[]>([]);
  const [selectedSymbol, setSelectedSymbol] = useState<string>('BTC/USDT');
  const [showSymbolDropdown, setShowSymbolDropdown] = useState(false);
  const [dropdownTab, setDropdownTab] = useState<SpotCategory>('crypto');
  const [dropdownFilter, setDropdownFilter] = useState('');

  const selectedMeta = useMemo(
    () => symbols.find((s) => s.symbol === selectedSymbol),
    [symbols, selectedSymbol],
  );

  const marketSymbol = useMemo(
    () => toMarketSymbol(selectedSymbol, selectedMeta?.category || 'crypto'),
    [selectedSymbol, selectedMeta],
  );

  /* ── Market data ── */
  const klines = useMarketStore((s) => s.klines);
  const klinesLoading = useMarketStore((s) => s.klinesLoading);
  const loadKlines = useMarketStore((s) => s.loadKlines);
  const quotes = useMarketStore((s) => s.quotes);
  const loadCryptoQuotes = useMarketStore((s) => s.loadCryptoQuotes);
  const loadQuotes = useMarketStore((s) => s.loadQuotes);

  const [timeframe, setTimeframe] = useState('1h');
  const currentQuote = quotes[marketSymbol];
  const currentPrice = currentQuote?.price ?? 0;
  const percentChange = currentQuote?.percent_change ?? 0;
  const pricePrecision = selectedMeta?.price_precision ?? 2;
  const qtyPrecision = selectedMeta?.qty_precision ?? 4;

  /* ── OrderBook & Trades ── */
  const [orderBook, setOrderBook] = useState<{ asks: OBRow[]; bids: OBRow[] }>({ asks: [], bids: [] });
  const [trades, setTrades] = useState<TradeRow[]>([]);
  const [obTab, setObTab] = useState<'orderbook' | 'trades'>('orderbook');
  const [obMobileOpen, setObMobileOpen] = useState(true);
  const tickRef = useRef(0);

  /* ── Order form ── */
  const [side, setSide] = useState<'buy' | 'sell'>('buy');
  const [orderType, setOrderType] = useState<'limit' | 'market'>('limit');
  const [priceInput, setPriceInput] = useState('');
  const [qtyInput, setQtyInput] = useState('');
  const [amountInput, setAmountInput] = useState('');
  const [sliderPct, setSliderPct] = useState(0);
  const [placing, setPlacing] = useState(false);

  /* ── Transfer modal ── */
  const [showTransferModal, setShowTransferModal] = useState(false);
  const [transferDirection, setTransferDirection] = useState<
    'spot_to_futures' | 'futures_to_spot'
  >('futures_to_spot');
  const [transferAmount, setTransferAmount] = useState('');
  const [transferring, setTransferring] = useState(false);

  /* ── Orders / account ── */
  const [pendingOrders, setPendingOrders] = useState<SpotOrder[]>([]);
  const [historyOrders, setHistoryOrders] = useState<SpotOrder[]>([]);
  const [account, setAccount] = useState<SpotAccountInfo | null>(null);
  const [bottomTab, setBottomTab] = useState<'current' | 'history' | 'holdings'>('current');

  const baseAsset = selectedMeta?.base_asset || '';
  // 真实 quote（用于账户 holding 查询，后端数据库原值）
  const rawQuoteAsset = selectedMeta?.quote_asset || 'USDT';
  // UI 展示用 quote：股票统一显示 USDT
  const quoteAsset = toDisplayQuote(rawQuoteAsset);
  // UI 展示用 symbol：股票 AAPL/USD → AAPL/USDT
  const displaySymbol = toDisplaySymbol(selectedSymbol);
  // 账户持仓按原 quote 查找；股票场景若 migration 未跑 rawQuote=USD，会找不到 USD holding，
  // 这时 fallback 到 USDT holding（账户里实际只有 USDT），保证 UI 显示 USDT 余额。
  const quoteHolding =
    account?.holdings.find((h) => h.asset === rawQuoteAsset) ||
    (rawQuoteAsset === 'USD'
      ? account?.holdings.find((h) => h.asset === 'USDT')
      : undefined);
  const baseHolding = account?.holdings.find((h) => h.asset === baseAsset);
  const availableBalance =
    side === 'buy' ? quoteHolding?.available ?? 0 : baseHolding?.available ?? 0;

  /* ═════════════════════════════════════════
     Load symbol list
     ═════════════════════════════════════════ */
  useEffect(() => {
    let cancelled = false;
    Promise.all([spotApi.listSymbols('crypto'), spotApi.listSymbols('stocks')])
      .then(([crypto, stocks]) => {
        if (cancelled) return;
        const merged = [...(crypto.symbols || []), ...(stocks.symbols || [])];
        merged.sort((a, b) => a.sort_order - b.sort_order);
        setSymbols(merged);
        if (merged.length > 0 && !merged.find((s) => s.symbol === selectedSymbol)) {
          setSelectedSymbol(merged[0].symbol);
        }
      })
      .catch((e) => {
        console.error('[spot] load symbols failed', e);
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /* ═════════════════════════════════════════
     Load klines + quote on symbol/timeframe change
     ═════════════════════════════════════════ */
  useEffect(() => {
    if (!marketSymbol) return;
    loadKlines(marketSymbol, timeframe);
    if (selectedMeta?.category === 'crypto') {
      loadCryptoQuotes([marketSymbol]);
    } else {
      loadQuotes([marketSymbol]);
    }
  }, [marketSymbol, timeframe, selectedMeta?.category, loadKlines, loadCryptoQuotes, loadQuotes]);

  /* ═════════════════════════════════════════
     OrderBook refresh (real API for crypto + mock fallback)
     ═════════════════════════════════════════ */
  useEffect(() => {
    if (!selectedSymbol) return;
    const isCrypto = selectedMeta?.category === 'crypto';
    let cancelled = false;

    const refresh = async () => {
      if (cancelled) return;
      tickRef.current = (tickRef.current + 1) & 0x7fffffff;

      if (isCrypto && marketSymbol) {
        try {
          const depth: any = await fetchCryptoDepth(marketSymbol, 10);
          if (cancelled) return;
          const asksRaw: [string, string][] = depth?.asks || [];
          const bidsRaw: [string, string][] = depth?.bids || [];
          if (asksRaw.length > 0 && bidsRaw.length > 0) {
            const asks: OBRow[] = asksRaw.map(([p, q]) => ({ price: +p, qty: +q, pct: 0 }));
            const bids: OBRow[] = bidsRaw.map(([p, q]) => ({ price: +p, qty: +q, pct: 0 }));
            const maxQty = Math.max(...asks.map((r) => r.qty), ...bids.map((r) => r.qty), 0.001);
            asks.forEach((r) => { r.pct = r.qty / maxQty; });
            bids.forEach((r) => { r.pct = r.qty / maxQty; });
            // asks 倒序展示（高价在上）
            setOrderBook({ asks: asks.slice().reverse(), bids });
            return;
          }
        } catch (e) {
          // fall through to mock
        }
      }
      setOrderBook(generateMockOrderBook(currentPrice, tickRef.current));
    };

    refresh();
    const timer = setInterval(refresh, 1500);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [selectedSymbol, selectedMeta?.category, marketSymbol, currentPrice]);

  /* ═════════════════════════════════════════
     Mock trades tick
     ═════════════════════════════════════════ */
  useEffect(() => {
    if (currentPrice <= 0) return;
    const gen = () => setTrades(generateMockTrades(currentPrice, 20));
    gen();
    const timer = setInterval(gen, 1500);
    return () => clearInterval(timer);
  }, [currentPrice]);

  /* ═════════════════════════════════════════
     Poll orders + account
     ═════════════════════════════════════════ */
  const refreshPending = useCallback(async () => {
    if (!user) return;
    try {
      const data = await spotApi.listOrders({ status: 'pending', limit: 50 });
      setPendingOrders(data.orders || []);
    } catch (e) {
      console.error('[spot] listOrders pending failed', e);
    }
  }, [user]);

  const refreshHistory = useCallback(async () => {
    if (!user) return;
    try {
      const data = await spotApi.orderHistory({ limit: 50 });
      setHistoryOrders(data.orders || []);
    } catch (e) {
      console.error('[spot] orderHistory failed', e);
    }
  }, [user]);

  const refreshAccount = useCallback(async () => {
    if (!user) return;
    try {
      const data = await spotApi.getAccount();
      setAccount(data);
    } catch (e) {
      console.error('[spot] getAccount failed', e);
    }
  }, [user]);

  /* WS-driven updates.
     后端在 placeMarket/placeLimit/FillPendingSpotOrder/CancelSpotOrder 会通过 trading hub
     推 spot_order_placed / _filled / _cancelled / spot_balance_update。
     相比轮询 5s 一拉，这里是实时；只在断线重连时 fallback 拉全量。 */
  useEffect(() => {
    if (!user) {
      setPendingOrders([]);
      setHistoryOrders([]);
      setAccount(null);
      return;
    }

    // 首屏拉一次
    refreshPending();
    refreshHistory();
    refreshAccount();

    // 确保 WS 连接（若别的 tab 已连，singleton 自动复用）
    tradingWs.connect();

    const mergeOrder = (prev: SpotOrder[], o: SpotOrder): SpotOrder[] => {
      const idx = prev.findIndex((x) => x.id === o.id);
      if (idx >= 0) {
        const next = prev.slice();
        next[idx] = o;
        return next;
      }
      return [o, ...prev];
    };

    const onPlaced = (order: SpotOrder) => {
      if (!order) return;
      setPendingOrders((prev) => mergeOrder(prev, order));
    };

    const onFilled = (order: SpotOrder) => {
      if (!order) return;
      // 从 pending 拿掉（可能是 limit 成交），推到 history 前面
      setPendingOrders((prev) => prev.filter((x) => x.id !== order.id));
      setHistoryOrders((prev) => mergeOrder(prev, order));
      // 余额变化 → 重拉账户（后面的 balance_update 也会触发一次，幂等）
      refreshAccount();
    };

    const onCancelled = (order: SpotOrder) => {
      if (!order) return;
      setPendingOrders((prev) => prev.filter((x) => x.id !== order.id));
      // 可选：把 cancelled 行也塞进 history（看后端 orderHistory 返回规则，这里不硬合并，拉一次兜底）
      refreshHistory();
      refreshAccount();
    };

    const onBalance = (_payload: { balances?: Record<string, number> }) => {
      // spot account 里还有 valuation_usdt 等聚合字段，直接重拉最简单
      refreshAccount();
    };

    const onReconnect = () => {
      refreshPending();
      refreshHistory();
      refreshAccount();
    };

    tradingWs.on('spot_order_placed', onPlaced);
    tradingWs.on('spot_order_filled', onFilled);
    tradingWs.on('spot_order_cancelled', onCancelled);
    tradingWs.on('spot_balance_update', onBalance);
    tradingWs.onReconnect(onReconnect);

    return () => {
      tradingWs.off('spot_order_placed', onPlaced);
      tradingWs.off('spot_order_filled', onFilled);
      tradingWs.off('spot_order_cancelled', onCancelled);
      tradingWs.off('spot_balance_update', onBalance);
      tradingWs.offReconnect(onReconnect);
    };
  }, [user, refreshPending, refreshHistory, refreshAccount]);

  /* ═════════════════════════════════════════
     Form field interactions
     ═════════════════════════════════════════ */

  const effectivePrice = useMemo(() => {
    if (orderType === 'market') return currentPrice;
    const p = parseFloat(priceInput);
    return isFinite(p) && p > 0 ? p : currentPrice;
  }, [orderType, priceInput, currentPrice]);

  const handlePriceChange = (v: string) => {
    setPriceInput(v);
    setSliderPct(0);
    const p = parseFloat(v);
    const q = parseFloat(qtyInput);
    if (isFinite(p) && p > 0 && isFinite(q) && q > 0) {
      setAmountInput((p * q).toFixed(2));
    }
  };

  const handleQtyChange = (v: string) => {
    setQtyInput(v);
    setSliderPct(0);
    const q = parseFloat(v);
    if (isFinite(q) && q > 0 && effectivePrice > 0) {
      setAmountInput((effectivePrice * q).toFixed(2));
    } else {
      setAmountInput('');
    }
  };

  const handleAmountChange = (v: string) => {
    setAmountInput(v);
    setSliderPct(0);
    const a = parseFloat(v);
    if (isFinite(a) && a > 0 && effectivePrice > 0) {
      setQtyInput((a / effectivePrice).toFixed(qtyPrecision));
    } else {
      setQtyInput('');
    }
  };

  // 滑块 0-100 → 金额/数量；与合约页行为保持一致
  const handleSliderChange = useCallback(
    (pct: number) => {
      setSliderPct(pct);
      if (pct === 0) {
        setQtyInput('');
        setAmountInput('');
        return;
      }
      if (availableBalance <= 0 || effectivePrice <= 0) return;
      if (side === 'buy') {
        // 买：滑块百分比作用于可用 quote 资金
        const amt = (availableBalance * pct) / 100;
        setAmountInput(amt.toFixed(2));
        setQtyInput((amt / effectivePrice).toFixed(qtyPrecision));
      } else {
        // 卖：滑块百分比作用于可用 base 持仓
        const qty = (availableBalance * pct) / 100;
        setQtyInput(qty.toFixed(qtyPrecision));
        setAmountInput((qty * effectivePrice).toFixed(2));
      }
    },
    [availableBalance, effectivePrice, side, qtyPrecision],
  );

  /* ═════════════════════════════════════════
     Submit order
     ═════════════════════════════════════════ */
  const handlePlaceOrder = async () => {
    if (!user) {
      Alert.alert(t('auth.notLoggedIn'));
      return;
    }
    const qtyNum = parseFloat(qtyInput);
    if (!qtyInput || !isFinite(qtyNum) || qtyNum <= 0) {
      Alert.alert(t('trading.enterQuantity') || '请输入数量');
      return;
    }

    const req: any = {
      symbol: selectedSymbol,
      side,
      order_type: orderType,
      qty: qtyNum,
    };

    if (orderType === 'limit') {
      const p = parseFloat(priceInput);
      if (!priceInput || !isFinite(p) || p <= 0) {
        Alert.alert(t('trading.enterLimitPrice') || '请输入限价');
        return;
      }
      req.price = p;
    }

    setPlacing(true);
    try {
      await spotApi.placeOrder(req);
      Alert.alert(t('trading.spotOrderPlaced'));
      setQtyInput('');
      setAmountInput('');
      setSliderPct(0);
      refreshPending();
      refreshAccount();
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || t('trading.spotInsufficientBalance');
      Alert.alert(msg);
    } finally {
      setPlacing(false);
    }
  };

  /* ═════════════════════════════════════════
     Transfer 划转
     ═════════════════════════════════════════ */
  const handleTransfer = async () => {
    const amt = parseFloat(transferAmount);
    if (!isFinite(amt) || amt <= 0) {
      Alert.alert(t('assets.transferFailedTitle'), t('assets.transferInvalidAmount'));
      return;
    }
    setTransferring(true);
    try {
      await transferAssets({
        from_account: transferDirection === 'spot_to_futures' ? 'spot' : 'futures',
        to_account: transferDirection === 'spot_to_futures' ? 'futures' : 'spot',
        amount: amt,
      });
      setShowTransferModal(false);
      setTransferAmount('');
      refreshAccount();
      Alert.alert(t('assets.transferSuccessTitle'), t('assets.transferSuccessBody', { amount: amt.toFixed(2) }));
    } catch (e: any) {
      Alert.alert(
        t('assets.transferFailedTitle'),
        e?.response?.data?.error || e?.message || t('assets.transferFailedBody'),
      );
    } finally {
      setTransferring(false);
    }
  };

  const handleCancel = async (orderId: string) => {
    try {
      await spotApi.cancelOrder(orderId);
      refreshPending();
      refreshAccount();
    } catch (e: any) {
      Alert.alert(e?.response?.data?.error || e?.message || t('common.error') || '撤单失败');
    }
  };

  /* ═════════════════════════════════════════
     Render sub-sections
     ═════════════════════════════════════════ */

  /* ── Top bar: symbol + 24h stats ── */
  const render24hStats = () => {
    const isCrypto = selectedMeta?.category === 'crypto';
    const turnover = currentQuote?.volume && currentPrice
      ? currentQuote.volume * currentPrice
      : undefined;
    return (
      <View style={styles.stats24Row}>
        <View style={styles.statItem}>
          <Text style={styles.statLabel}>{t('trading.changePercent') || '涨跌幅'}</Text>
          <Text style={[styles.statValue, { color: percentChange >= 0 ? Colors.up : Colors.down }]}>
            {percentChange >= 0 ? '+' : ''}
            {percentChange.toFixed(2)}%
          </Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statLabel}>{t('trading.high24h')}</Text>
          <Text style={styles.statValue}>{formatPrice(currentQuote?.high, pricePrecision)}</Text>
        </View>
        <View style={styles.statDivider} />
        <View style={styles.statItem}>
          <Text style={styles.statLabel}>{t('trading.low24h')}</Text>
          <Text style={styles.statValue}>{formatPrice(currentQuote?.low, pricePrecision)}</Text>
        </View>
        {isCrypto && (
          <>
            <View style={styles.statDivider} />
            <View style={styles.statItem}>
              <Text style={styles.statLabel}>
                {t('trading.volume24h')}({baseAsset || '--'})
              </Text>
              <Text style={styles.statValue}>{formatCompact(currentQuote?.volume)}</Text>
            </View>
            <View style={styles.statDivider} />
            <View style={styles.statItem}>
              <Text style={styles.statLabel}>
                {t('trading.turnover24h')}({quoteAsset})
              </Text>
              <Text style={styles.statValue}>{formatCompact(turnover)}</Text>
            </View>
          </>
        )}
      </View>
    );
  };

  // 顶部 Chip：只展示当前 symbol + 价格，点击后打开侧滑下拉
  const renderSymbolDropdown = () => (
    <View style={styles.symbolDropdownWrap}>
      <TouchableOpacity
        style={styles.symbolChip}
        activeOpacity={0.7}
        onPress={() => {
          setDropdownTab(selectedMeta?.category || 'crypto');
          setDropdownFilter('');
          setShowSymbolDropdown(true);
        }}
      >
        <Text style={styles.symbolText}>{displaySymbol}</Text>
        <Text style={styles.chevron}>▼</Text>
      </TouchableOpacity>
      <View style={styles.priceBox}>
        <Text
          style={[
            styles.priceValue,
            { color: percentChange >= 0 ? Colors.up : Colors.down },
          ]}
        >
          {formatPrice(currentPrice, pricePrecision)}
        </Text>
      </View>
    </View>
  );

  // 侧滑 SymbolDropdown（与合约页一致：search + tabs + list）
  const renderSymbolPanel = () => {
    const tabs: { key: SpotCategory; label: string }[] = [
      { key: 'crypto', label: t('trading.crypto') },
      { key: 'stocks', label: t('trading.stock') },
    ];
    const filtered = symbols.filter((s) => {
      if (s.category !== dropdownTab) return false;
      if (!dropdownFilter.trim()) return true;
      const q = dropdownFilter.trim().toLowerCase();
      return (
        s.symbol.toLowerCase().includes(q) ||
        s.display_name.toLowerCase().includes(q) ||
        s.base_asset.toLowerCase().includes(q)
      );
    });

    return (
      <Modal
        visible={showSymbolDropdown}
        transparent
        animationType="fade"
        onRequestClose={() => setShowSymbolDropdown(false)}
      >
        <View style={styles.sdOverlay}>
          <TouchableOpacity
            style={styles.sdBackdrop}
            activeOpacity={1}
            onPress={() => setShowSymbolDropdown(false)}
          />
          <View style={styles.sdPanel}>
            {/* Search */}
            <View style={styles.sdSearchRow}>
              <Text style={styles.sdSearchIcon}>🔍</Text>
              <TextInput
                style={styles.sdSearchInput}
                placeholder={t('trading.searchPairs')}
                placeholderTextColor={Colors.textMuted}
                value={dropdownFilter}
                onChangeText={setDropdownFilter}
                autoFocus
              />
              <TouchableOpacity onPress={() => setShowSymbolDropdown(false)}>
                <Text style={styles.sdClose}>✕</Text>
              </TouchableOpacity>
            </View>

            {/* Tabs */}
            <View style={styles.sdTabRow}>
              {tabs.map((tab) => (
                <TouchableOpacity
                  key={tab.key}
                  style={[styles.sdTab, dropdownTab === tab.key && styles.sdTabActive]}
                  activeOpacity={0.7}
                  onPress={() => {
                    setDropdownTab(tab.key);
                    setDropdownFilter('');
                  }}
                >
                  <Text
                    style={[
                      styles.sdTabText,
                      dropdownTab === tab.key && styles.sdTabTextActive,
                    ]}
                  >
                    {tab.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            {/* List header */}
            <View style={styles.sdListHeader}>
              <Text style={[styles.sdHeaderText, { flex: 1.4 }]}>{t('trading.pair')}</Text>
              <Text style={[styles.sdHeaderText, { flex: 1, textAlign: 'right' }]}>
                {t('spot.price') || '价格'}
              </Text>
              <Text style={[styles.sdHeaderText, { flex: 1, textAlign: 'right' }]}>
                {t('trading.changePercent') || '涨跌幅'}
              </Text>
            </View>

            {/* List */}
            <ScrollView style={styles.sdList} keyboardShouldPersistTaps="handled">
              {filtered.length === 0 ? (
                <View style={styles.sdEmpty}>
                  <Text style={styles.sdEmptyText}>{t('trading.noMatch')}</Text>
                </View>
              ) : (
                filtered.map((s) => {
                  const isActive = s.symbol === selectedSymbol;
                  const ms = toMarketSymbol(s.symbol, s.category);
                  const q = quotes[ms];
                  const p = q?.price ?? 0;
                  const pct = q?.percent_change ?? 0;
                  const color = !q ? Colors.textMuted : pct >= 0 ? Colors.up : Colors.down;
                  return (
                    <TouchableOpacity
                      key={s.symbol}
                      style={[styles.sdRow, isActive && styles.sdRowActive]}
                      activeOpacity={0.7}
                      onPress={() => {
                        setSelectedSymbol(s.symbol);
                        setShowSymbolDropdown(false);
                        setPriceInput('');
                        setQtyInput('');
                        setAmountInput('');
                        setSliderPct(0);
                      }}
                    >
                      <View style={{ flex: 1.4 }}>
                        <Text style={[styles.sdRowSymbol, isActive && { color: Colors.primary }]}>
                          {toDisplaySymbol(s.symbol)}
                        </Text>
                        {!!s.display_name && (
                          <Text style={styles.sdRowName}>{s.display_name}</Text>
                        )}
                      </View>
                      <Text style={[styles.sdRowPrice, { flex: 1 }]}>
                        {p > 0 ? formatPrice(p, s.price_precision) : '--'}
                      </Text>
                      <Text style={[styles.sdRowChange, { flex: 1, color }]}>
                        {q ? `${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%` : '--'}
                      </Text>
                    </TouchableOpacity>
                  );
                })
              )}
            </ScrollView>
          </View>
        </View>
      </Modal>
    );
  };

  /* ── Chart ── */
  const renderChart = () => (
    <View style={styles.chartCard}>
      <View style={styles.tfRow}>
        {['1min', '5min', '15min', '1h', '4h', '1day'].map((tf) => (
          <TouchableOpacity
            key={tf}
            onPress={() => setTimeframe(tf)}
            style={[styles.tfBtn, tf === timeframe && styles.tfBtnActive]}
            activeOpacity={0.7}
          >
            <Text style={[styles.tfText, tf === timeframe && styles.tfTextActive]}>{tf}</Text>
          </TouchableOpacity>
        ))}
      </View>
      <View style={styles.chartBox}>
        {Platform.OS === 'web' ? (
          <TradingViewChart
            klines={klines}
            symbol={marketSymbol}
            realtimePrice={currentPrice || undefined}
          />
        ) : (
          <View style={styles.chartPlaceholder}>
            <Text style={styles.placeholderText}>
              {klinesLoading ? t('common.loading') : `${marketSymbol} ${timeframe}`}
            </Text>
          </View>
        )}
      </View>
    </View>
  );

  /* ── Order book panel ── */
  const renderOrderBookPanel = () => (
    <View style={styles.obCard}>
      <View style={styles.obTabRow}>
        <TouchableOpacity
          onPress={() => setObTab('orderbook')}
          style={styles.obTabBtn}
          activeOpacity={0.7}
        >
          <Text
            style={[styles.obTabText, obTab === 'orderbook' && styles.obTabTextActive]}
          >
            {t('spot.orderBook') || '订单簿'}
          </Text>
          {obTab === 'orderbook' && <View style={styles.obTabUnderline} />}
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => setObTab('trades')}
          style={styles.obTabBtn}
          activeOpacity={0.7}
        >
          <Text
            style={[styles.obTabText, obTab === 'trades' && styles.obTabTextActive]}
          >
            {t('spot.recentTrades') || '最近成交'}
          </Text>
          {obTab === 'trades' && <View style={styles.obTabUnderline} />}
        </TouchableOpacity>
      </View>

      {obTab === 'orderbook' ? (
        <>
          <View style={styles.obColHeader}>
            <Text style={styles.obColLabel}>
              {t('spot.price') || '价格'}({quoteAsset})
            </Text>
            <Text style={[styles.obColLabel, { textAlign: 'right' }]}>
              {t('spot.qty') || '数量'}({baseAsset || '--'})
            </Text>
          </View>
          <View style={styles.obContent}>
            {orderBook.asks.slice(0, 10).map((a, i) => (
              <TouchableOpacity
                key={`ask-${i}`}
                style={styles.obRow}
                onPress={() => {
                  setOrderType('limit');
                  setPriceInput(a.price.toFixed(pricePrecision));
                }}
                activeOpacity={0.7}
              >
                <View style={[styles.obBarAsk, { width: `${a.pct * 100}%` }]} />
                <Text style={styles.obAskPrice}>{formatPrice(a.price, pricePrecision)}</Text>
                <Text style={styles.obQty}>{a.qty.toFixed(qtyPrecision)}</Text>
              </TouchableOpacity>
            ))}
            <View style={styles.obCurrentRow}>
              <Text
                style={[
                  styles.obCurrentPrice,
                  { color: percentChange >= 0 ? Colors.up : Colors.down },
                ]}
              >
                {formatPrice(currentPrice, pricePrecision)}
              </Text>
              <Text
                style={[
                  styles.obCurrentChange,
                  { color: percentChange >= 0 ? Colors.up : Colors.down },
                ]}
              >
                {percentChange >= 0 ? '↑' : '↓'} {Math.abs(percentChange).toFixed(2)}%
              </Text>
            </View>
            {orderBook.bids.slice(0, 10).map((b, i) => (
              <TouchableOpacity
                key={`bid-${i}`}
                style={styles.obRow}
                onPress={() => {
                  setOrderType('limit');
                  setPriceInput(b.price.toFixed(pricePrecision));
                }}
                activeOpacity={0.7}
              >
                <View style={[styles.obBarBid, { width: `${b.pct * 100}%` }]} />
                <Text style={styles.obBidPrice}>{formatPrice(b.price, pricePrecision)}</Text>
                <Text style={styles.obQty}>{b.qty.toFixed(qtyPrecision)}</Text>
              </TouchableOpacity>
            ))}
          </View>
        </>
      ) : (
        <>
          <View style={styles.obColHeader}>
            <Text style={styles.obColLabel}>
              {t('spot.price') || '价格'}({quoteAsset})
            </Text>
            <Text style={[styles.obColLabel, { textAlign: 'center', flex: 1 }]}>
              {t('spot.qty') || '数量'}
            </Text>
            <Text style={[styles.obColLabel, { textAlign: 'right' }]}>
              {t('trading.time') || '时间'}
            </Text>
          </View>
          <View style={styles.obContent}>
            {trades.length === 0 ? (
              <Text style={styles.obEmpty}>{t('common.noData')}</Text>
            ) : (
              trades.map((tr) => (
                <View key={tr.id} style={styles.tradeRow}>
                  <Text
                    style={[
                      styles.tradePrice,
                      { color: tr.side === 'buy' ? Colors.up : Colors.down },
                    ]}
                  >
                    {formatPrice(tr.price, pricePrecision)}
                  </Text>
                  <Text style={styles.tradeQty}>{tr.qty.toFixed(qtyPrecision)}</Text>
                  <Text style={styles.tradeTime}>
                    {new Date(tr.timestamp).toLocaleTimeString(undefined, { hour12: false })}
                  </Text>
                </View>
              ))
            )}
          </View>
        </>
      )}
    </View>
  );

  /* ── Order panel ── */
  const renderOrderPanel = () => {
    const hintUnit = side === 'buy' ? quoteAsset : baseAsset;
    return (
      <View style={styles.orderCard}>
        {/* Buy/Sell tabs */}
        <View style={styles.sideRow}>
          <TouchableOpacity
            style={[styles.sideBtn, side === 'buy' && styles.sideBtnBuyActive]}
            onPress={() => {
              setSide('buy');
              setSliderPct(0);
            }}
            activeOpacity={0.7}
          >
            <Text
              style={[
                styles.sideText,
                side === 'buy' ? styles.sideTextActiveBuy : styles.sideTextInactive,
              ]}
            >
              {t('trading.spotBuy')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.sideBtn, side === 'sell' && styles.sideBtnSellActive]}
            onPress={() => {
              setSide('sell');
              setSliderPct(0);
            }}
            activeOpacity={0.7}
          >
            <Text
              style={[
                styles.sideText,
                side === 'sell' ? styles.sideTextActiveSell : styles.sideTextInactive,
              ]}
            >
              {t('trading.spotSell')}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Order type */}
        <View style={styles.typeRow}>
          <TouchableOpacity onPress={() => setOrderType('limit')} activeOpacity={0.7}>
            <Text
              style={[styles.typeText, orderType === 'limit' && styles.typeTextActive]}
            >
              {t('trading.limit') || '限价'}
            </Text>
            {orderType === 'limit' && <View style={styles.typeUnderline} />}
          </TouchableOpacity>
          <TouchableOpacity onPress={() => setOrderType('market')} activeOpacity={0.7}>
            <Text
              style={[styles.typeText, orderType === 'market' && styles.typeTextActive]}
            >
              {t('trading.marketOrder') || '市价'}
            </Text>
            {orderType === 'market' && <View style={styles.typeUnderline} />}
          </TouchableOpacity>
        </View>

        {/* Available + Transfer */}
        <View style={styles.availRow}>
          <Text style={styles.availLabel}>
            {t('spot.availableBalance') || '可用'}
          </Text>
          <View style={styles.availRight}>
            <Text style={styles.availValue}>
              {availableBalance.toFixed(side === 'buy' ? 2 : qtyPrecision)} {hintUnit}
            </Text>
            <TouchableOpacity
              style={styles.transferBtn}
              activeOpacity={0.7}
              onPress={() => {
                if (!user) {
                  Alert.alert(t('auth.notLoggedIn'));
                  return;
                }
                setShowTransferModal(true);
              }}
            >
              <Text style={styles.transferBtnText}>
                {t('assets.transferAction') || '划转'}
              </Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Price (limit only) */}
        {orderType === 'limit' ? (
          <View style={styles.inputGroup}>
            <Text style={styles.inputGroupLabel}>
              {t('spot.price') || '价格'}
            </Text>
            <View style={styles.inputRow}>
              <TextInput
                style={styles.input}
                value={priceInput}
                onChangeText={handlePriceChange}
                placeholder={currentPrice ? currentPrice.toFixed(pricePrecision) : '0.00'}
                keyboardType="decimal-pad"
                placeholderTextColor={Colors.textMuted}
              />
              <Text style={styles.inputUnit}>{quoteAsset}</Text>
            </View>
          </View>
        ) : (
          <View style={styles.marketPriceHint}>
            <Text style={styles.marketPriceText}>
              {t('trading.marketOrder') || '市价'} ≈ {formatPrice(currentPrice, pricePrecision)} {quoteAsset}
            </Text>
          </View>
        )}

        {/* Quantity */}
        <View style={styles.inputGroup}>
          <Text style={styles.inputGroupLabel}>{t('spot.qty') || '数量'}</Text>
          <View style={styles.inputRow}>
            <TextInput
              style={styles.input}
              value={qtyInput}
              onChangeText={handleQtyChange}
              placeholder="0.00"
              keyboardType="decimal-pad"
              placeholderTextColor={Colors.textMuted}
            />
            <Text style={styles.inputUnit}>{baseAsset}</Text>
          </View>
        </View>

        {/* Percent slider (与合约页一致) */}
        <View style={styles.pctSliderWrap}>
          {Platform.OS === 'web' ? (
            // @ts-ignore: react-native-web 支持原生 input
            <input
              type="range"
              min={0}
              max={100}
              step={1}
              value={sliderPct}
              onChange={(e: any) => handleSliderChange(Number(e.target.value))}
              style={{ width: '100%', height: 4, accentColor: '#C9A84C', cursor: 'pointer' }}
            />
          ) : (
            <View style={styles.pctChipRow}>
              {[0, 25, 50, 75, 100].map((p) => (
                <TouchableOpacity
                  key={p}
                  style={[styles.pctChip, sliderPct === p && styles.pctChipActive]}
                  onPress={() => handleSliderChange(p)}
                  activeOpacity={0.7}
                >
                  <Text
                    style={[styles.pctChipText, sliderPct === p && styles.pctChipTextActive]}
                  >
                    {p}%
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          )}
          <View style={styles.pctLabels}>
            {['0%', '25%', '50%', '75%', '100%'].map((p) => (
              <Text key={p} style={styles.pctLabelText}>
                {p}
              </Text>
            ))}
          </View>
        </View>

        {/* Amount */}
        <View style={styles.inputGroup}>
          <Text style={styles.inputGroupLabel}>{t('spot.amount') || '金额'}</Text>
          <View style={styles.inputRow}>
            <TextInput
              style={styles.input}
              value={amountInput}
              onChangeText={handleAmountChange}
              placeholder="0.00"
              keyboardType="decimal-pad"
              placeholderTextColor={Colors.textMuted}
            />
            <Text style={styles.inputUnit}>{quoteAsset}</Text>
          </View>
        </View>

        {/* Submit */}
        <TouchableOpacity
          style={[
            styles.submitBtn,
            side === 'buy' ? styles.submitBtnBuy : styles.submitBtnSell,
            placing && { opacity: 0.6 },
          ]}
          activeOpacity={0.85}
          disabled={placing}
          onPress={handlePlaceOrder}
        >
          <Text style={styles.submitBtnText}>
            {placing
              ? '…'
              : `${side === 'buy' ? t('trading.spotBuy') : t('trading.spotSell')} ${baseAsset}`}
          </Text>
        </TouchableOpacity>
      </View>
    );
  };

  /* ── Bottom orders table ── */
  const renderBottomTable = () => (
    <View style={styles.bottomCard}>
      <View style={styles.bottomTabRow}>
        {([
          { key: 'current', label: t('spot.currentOrders') || '当前委托' },
          { key: 'history', label: t('spot.orderHistory') || '历史委托' },
          { key: 'holdings', label: t('spot.holdings') || '资产持仓' },
        ] as const).map((tab) => (
          <TouchableOpacity
            key={tab.key}
            style={styles.bottomTab}
            onPress={() => setBottomTab(tab.key as any)}
            activeOpacity={0.7}
          >
            <Text
              style={[
                styles.bottomTabText,
                tab.key === bottomTab && styles.bottomTabTextActive,
              ]}
            >
              {tab.label}
            </Text>
            {tab.key === bottomTab && <View style={styles.bottomTabUnderline} />}
          </TouchableOpacity>
        ))}
      </View>

      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <View style={{ minWidth: 720 }}>
          {bottomTab === 'holdings' ? renderHoldingsTable() : renderOrderTable()}
        </View>
      </ScrollView>
    </View>
  );

  const renderOrderTable = () => {
    const rows = bottomTab === 'current' ? pendingOrders : historyOrders;
    const isPending = bottomTab === 'current';
    return (
      <>
        <View style={styles.tableHeader}>
          <Text style={[styles.thCell, { flex: 1.3 }]}>{t('trading.pair') || '交易对'}</Text>
          <Text style={[styles.thCell, { flex: 0.8 }]}>{t('trading.buy')}/{t('trading.sell')}</Text>
          <Text style={[styles.thCell, { flex: 0.8 }]}>{t('trading.limit')}/{t('trading.marketOrder')}</Text>
          <Text style={[styles.thCell, { flex: 1 }]}>{t('spot.price') || '价格'}</Text>
          <Text style={[styles.thCell, { flex: 1 }]}>{t('spot.qty') || '数量'}</Text>
          <Text style={[styles.thCell, { flex: 1 }]}>{t('spot.amount') || '金额'}</Text>
          <Text style={[styles.thCell, { flex: 1.4 }]}>{t('trading.time') || '时间'}</Text>
          {isPending && (
            <Text style={[styles.thCell, { flex: 0.7, textAlign: 'right' }]}>
              {t('common.noData') ? t('spot.cancelOrder') || '操作' : '操作'}
            </Text>
          )}
          {!isPending && (
            <Text style={[styles.thCell, { flex: 0.8, textAlign: 'right' }]}>
              {t('trading.pending') && t('trading.filled') ? '状态' : 'Status'}
            </Text>
          )}
        </View>
        {rows.length === 0 ? (
          <View style={styles.emptyRow}>
            <Text style={styles.emptyText}>{t('spot.noOrders') || t('common.noData')}</Text>
          </View>
        ) : (
          rows.map((o) => (
            <View key={o.id} style={styles.tableRow}>
              <Text style={[styles.tdCell, { flex: 1.3, color: Colors.textActive, fontWeight: '600' }]}>
                {toDisplaySymbol(o.symbol)}
              </Text>
              <Text
                style={[
                  styles.tdCell,
                  { flex: 0.8, color: o.side === 'buy' ? Colors.up : Colors.down, fontWeight: '700' },
                ]}
              >
                {o.side === 'buy' ? t('trading.spotBuy') : t('trading.spotSell')}
              </Text>
              <Text style={[styles.tdCell, { flex: 0.8 }]}>
                {o.order_type === 'market' ? t('trading.marketOrder') : t('trading.limit')}
              </Text>
              <Text style={[styles.tdCell, { flex: 1 }]}>
                {o.order_type === 'market'
                  ? o.filled_price
                    ? formatPrice(o.filled_price, pricePrecision)
                    : '--'
                  : formatPrice(o.price ?? 0, pricePrecision)}
              </Text>
              <Text style={[styles.tdCell, { flex: 1 }]}>
                {(+o.qty).toFixed(qtyPrecision)}
              </Text>
              <Text style={[styles.tdCell, { flex: 1 }]}>
                {(+o.quote_qty).toFixed(2)} {toDisplayQuote(o.quote_asset)}
              </Text>
              <Text style={[styles.tdCell, { flex: 1.4, fontSize: 11 }]}>
                {new Date(o.created_at).toLocaleString()}
              </Text>
              {isPending ? (
                <View style={{ flex: 0.7, alignItems: 'flex-end' }}>
                  <TouchableOpacity
                    onPress={() => handleCancel(o.id)}
                    style={styles.rowCancelBtn}
                    activeOpacity={0.7}
                  >
                    <Text style={styles.rowCancelText}>
                      {t('spot.cancelOrder') || t('common.cancel') || '撤单'}
                    </Text>
                  </TouchableOpacity>
                </View>
              ) : (
                <Text
                  style={[
                    styles.tdCell,
                    {
                      flex: 0.8,
                      textAlign: 'right',
                      color:
                        o.status === 'filled'
                          ? Colors.up
                          : o.status === 'cancelled' || o.status === 'rejected'
                          ? Colors.textMuted
                          : Colors.textActive,
                    },
                  ]}
                >
                  {t(`trading.${o.status}`) || o.status}
                </Text>
              )}
            </View>
          ))
        )}
      </>
    );
  };

  const renderHoldingsTable = () => {
    if (!account || account.holdings.length === 0) {
      return (
        <View style={styles.emptyRow}>
          <Text style={styles.emptyText}>{t('common.noData')}</Text>
        </View>
      );
    }
    return (
      <>
        <View style={styles.holdingsSummary}>
          <Text style={styles.holdingsSummaryLabel}>
            {t('trading.totalValue') || '总估值'}:
          </Text>
          <Text style={styles.holdingsSummaryValue}>
            {account.total_valuation_usdt.toFixed(2)} USDT
          </Text>
        </View>
        <View style={styles.tableHeader}>
          <Text style={[styles.thCell, { flex: 1 }]}>{t('assets.assetTableAsset') || '币种'}</Text>
          <Text style={[styles.thCell, { flex: 1 }]}>{t('assets.available') || '可用'}</Text>
          <Text style={[styles.thCell, { flex: 1 }]}>{t('assets.frozen') || '冻结'}</Text>
          <Text style={[styles.thCell, { flex: 1 }]}>
            {t('trading.totalValue') || '估值'}
          </Text>
          <Text style={[styles.thCell, { flex: 1 }]}>
            {t('assets.unrealizedPnl') || '未实现盈亏'}
          </Text>
        </View>
        {account.holdings.map((h) => (
          <View key={h.asset} style={styles.tableRow}>
            <Text style={[styles.tdCell, { flex: 1, color: Colors.textActive, fontWeight: '700' }]}>
              {h.asset}
            </Text>
            <Text style={[styles.tdCell, { flex: 1 }]}>{h.available.toFixed(6)}</Text>
            <Text style={[styles.tdCell, { flex: 1 }]}>{h.frozen.toFixed(6)}</Text>
            <Text style={[styles.tdCell, { flex: 1 }]}>
              {h.valuation_usdt.toFixed(2)} USDT
            </Text>
            <Text
              style={[
                styles.tdCell,
                {
                  flex: 1,
                  color:
                    (h.unrealized_pnl ?? 0) >= 0 ? Colors.up : Colors.down,
                },
              ]}
            >
              {h.unrealized_pnl != null
                ? `${h.unrealized_pnl >= 0 ? '+' : ''}${h.unrealized_pnl.toFixed(2)}`
                : '--'}
            </Text>
          </View>
        ))}
      </>
    );
  };

  /* ═════════════════════════════════════════
     Layout
     ═════════════════════════════════════════ */

  /* ── Transfer Modal ── */
  const renderTransferModal = () => {
    const amt = parseFloat(transferAmount);
    const available = account?.holdings.find((h) => h.asset === 'USDT')?.available ?? 0;
    const fromLabel =
      transferDirection === 'spot_to_futures'
        ? t('assets.distributionMain')
        : t('assets.distributionFutures');
    const toLabel =
      transferDirection === 'spot_to_futures'
        ? t('assets.distributionFutures')
        : t('assets.distributionMain');
    const canSubmit =
      !transferring && isFinite(amt) && amt > 0 && (transferDirection !== 'spot_to_futures' || amt <= available);
    return (
      <Modal
        visible={showTransferModal}
        transparent
        animationType="fade"
        onRequestClose={() => setShowTransferModal(false)}
      >
        <View style={styles.tfOverlay}>
          <View style={styles.tfCard}>
            <View style={styles.tfHeader}>
              <Text style={styles.tfTitle}>{t('assets.transferModalTitle') || '资金划转'}</Text>
              <TouchableOpacity
                onPress={() => setShowTransferModal(false)}
                activeOpacity={0.7}
                style={styles.tfClose}
              >
                <Text style={styles.tfCloseText}>✕</Text>
              </TouchableOpacity>
            </View>

            {/* Direction pill */}
            <View style={styles.tfDirectionRow}>
              <View style={styles.tfDirectionCard}>
                <Text style={styles.tfDirectionLabel}>
                  {t('assets.transferFromLabel') || '转出'}
                </Text>
                <Text style={styles.tfDirectionValue}>{fromLabel}</Text>
              </View>
              <TouchableOpacity
                style={styles.tfSwap}
                activeOpacity={0.7}
                onPress={() =>
                  setTransferDirection((d) =>
                    d === 'spot_to_futures' ? 'futures_to_spot' : 'spot_to_futures',
                  )
                }
              >
                <Text style={styles.tfSwapText}>⇅</Text>
              </TouchableOpacity>
              <View style={styles.tfDirectionCard}>
                <Text style={styles.tfDirectionLabel}>
                  {t('assets.transferToLabel') || '转入'}
                </Text>
                <Text style={styles.tfDirectionValue}>{toLabel}</Text>
              </View>
            </View>

            {/* Amount input */}
            <View style={styles.inputGroup}>
              <View style={styles.tfAmountHead}>
                <Text style={styles.inputGroupLabel}>
                  {t('assets.transferAmountLabel') || '划转金额 (USDT)'}
                </Text>
                <TouchableOpacity
                  onPress={() => setTransferAmount(available > 0 ? available.toFixed(2) : '')}
                  activeOpacity={0.7}
                >
                  <Text style={styles.tfMaxText}>
                    {t('assets.transferMaxAction') || '全部划转'}
                  </Text>
                </TouchableOpacity>
              </View>
              <View style={styles.inputRow}>
                <TextInput
                  style={styles.input}
                  value={transferAmount}
                  onChangeText={setTransferAmount}
                  placeholder={t('assets.transferAmountPlaceholder') || '输入划转金额'}
                  keyboardType="decimal-pad"
                  placeholderTextColor={Colors.textMuted}
                />
                <Text style={styles.inputUnit}>USDT</Text>
              </View>
              {transferDirection === 'spot_to_futures' && (
                <Text style={styles.tfHint}>
                  {t('assets.transferAvailableLabel') || '可用'}: {available.toFixed(2)} USDT
                </Text>
              )}
            </View>

            {/* Actions */}
            <View style={styles.tfActionsRow}>
              <TouchableOpacity
                style={styles.tfCancelBtn}
                activeOpacity={0.7}
                onPress={() => setShowTransferModal(false)}
              >
                <Text style={styles.tfCancelText}>{t('common.cancel') || '取消'}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.tfConfirmBtn, !canSubmit && styles.tfBtnDisabled]}
                activeOpacity={0.85}
                disabled={!canSubmit}
                onPress={handleTransfer}
              >
                <Text style={styles.tfConfirmText}>
                  {transferring
                    ? t('assets.transferSubmitting') || '划转中…'
                    : t('assets.transferConfirmAction') || '确认划转'}
                </Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    );
  };

  if (isDesktop) {
    return (
      <>
        <ScrollView
          style={styles.container}
          contentContainerStyle={{ padding: 12, gap: 10 }}
        >
          {/* Top bar: symbol + 24h stats */}
          <View style={styles.topBar}>
            <View style={{ zIndex: 20 }}>{renderSymbolDropdown()}</View>
            <View style={{ flex: 1 }}>{render24hStats()}</View>
          </View>

          {/* 3-col main area (chart + orderbook + order panel) */}
          <View style={styles.mainRow}>
            <View style={styles.centerCol}>{renderChart()}</View>
            <View style={styles.obCol}>{renderOrderBookPanel()}</View>
            <View style={styles.rightCol}>{renderOrderPanel()}</View>
          </View>

          {/* Bottom orders table */}
          {renderBottomTable()}
        </ScrollView>
        {renderTransferModal()}
        {renderSymbolPanel()}
      </>
    );
  }

  /* ── Mobile: single-column stack ── */
  return (
    <>
      <ScrollView
        style={styles.container}
        contentContainerStyle={{ padding: 10, gap: 10 }}
      >
        <View style={{ zIndex: 20 }}>{renderSymbolDropdown()}</View>
        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          {render24hStats()}
        </ScrollView>
        {renderChart()}
        <TouchableOpacity
          onPress={() => setObMobileOpen((v) => !v)}
          style={styles.mobileFoldBar}
          activeOpacity={0.7}
        >
          <Text style={styles.mobileFoldText}>
            {t('spot.orderBook') || '订单簿'} / {t('spot.recentTrades') || '最近成交'}
          </Text>
          <Text style={styles.chevron}>{obMobileOpen ? '▲' : '▼'}</Text>
        </TouchableOpacity>
        {obMobileOpen && renderOrderBookPanel()}
        {renderBottomTable()}
        {renderOrderPanel()}
      </ScrollView>
      {renderTransferModal()}
      {renderSymbolPanel()}
    </>
  );
}

/* ════════════════════════════════════════════
   Styles
   ════════════════════════════════════════════ */

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: Colors.background },

  /* ── Top bar ── */
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 20,
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: Colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    zIndex: 15,
  },
  stats24Row: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 4,
  },
  statItem: { minWidth: 100, paddingHorizontal: 8 },
  statLabel: { color: Colors.textMuted, fontSize: 10, marginBottom: 2 },
  statValue: { color: Colors.textActive, fontSize: 13, fontWeight: '600' },
  statDivider: { width: 1, height: 24, backgroundColor: Colors.border, marginHorizontal: 4 },

  /* ── Symbol dropdown ── */
  symbolDropdownWrap: {
    position: 'relative',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  symbolChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 8,
    backgroundColor: Colors.topBarBg,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  symbolText: { color: Colors.textActive, fontSize: 15, fontWeight: '700' },
  chevron: { color: Colors.textMuted, fontSize: 10 },
  priceBox: { flexDirection: 'row', alignItems: 'baseline', gap: 8 },
  priceValue: { fontSize: 18, fontWeight: '700' },

  /* ── Symbol side panel (与合约页 SymbolDropdown 一致) ── */
  sdOverlay: {
    flex: 1,
    flexDirection: 'row',
    backgroundColor: 'transparent',
  },
  sdBackdrop: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  sdPanel: {
    width: 380,
    maxWidth: '92%',
    height: '100%',
    backgroundColor: '#131313',
    borderRightWidth: 1,
    borderRightColor: Colors.border,
  },
  sdSearchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    gap: 8,
  },
  sdSearchIcon: { fontSize: 14, opacity: 0.5 },
  sdSearchInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 13,
    paddingVertical: 4,
    ...Platform.select({ web: { outlineWidth: 0 } as any }),
  },
  sdClose: {
    color: Colors.textMuted,
    fontSize: 16,
    padding: 4,
  },
  sdTabRow: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 8,
  },
  sdTab: {
    paddingVertical: 10,
    paddingHorizontal: 14,
  },
  sdTabActive: {
    borderBottomWidth: 2,
    borderBottomColor: Colors.primary,
  },
  sdTabText: {
    fontSize: 12,
    color: Colors.textMuted,
    fontWeight: '600',
  },
  sdTabTextActive: {
    color: Colors.primary,
  },
  sdListHeader: {
    flexDirection: 'row',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.05)',
  },
  sdHeaderText: {
    fontSize: 10,
    color: Colors.textMuted,
    fontWeight: '500',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  sdList: {
    flex: 1,
  },
  sdRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  sdRowActive: {
    backgroundColor: 'rgba(42,42,42,0.3)',
  },
  sdRowSymbol: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  sdRowName: {
    color: Colors.textMuted,
    fontSize: 10,
    marginTop: 2,
  },
  sdRowPrice: {
    color: Colors.textActive,
    fontSize: 12,
    textAlign: 'right',
    fontFamily: 'monospace',
  },
  sdRowChange: {
    fontSize: 12,
    textAlign: 'right',
    fontFamily: 'monospace',
  },
  sdEmpty: {
    paddingVertical: 40,
    alignItems: 'center',
  },
  sdEmptyText: {
    color: Colors.textMuted,
    fontSize: 13,
  },

  /* ── Desktop main row ── */
  mainRow: { flexDirection: 'row', gap: 10 },
  centerCol: { flex: 1, minWidth: 0 },
  obCol: { width: 240 },
  rightCol: { width: 320 },

  /* ── Chart ── */
  chartCard: {
    backgroundColor: Colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 8,
  },
  tfRow: { flexDirection: 'row', gap: 4, marginBottom: 8, flexWrap: 'wrap' },
  tfBtn: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 4 },
  tfBtnActive: { backgroundColor: Colors.primaryDim },
  tfText: { color: Colors.textMuted, fontSize: 12, fontWeight: '500' },
  tfTextActive: { color: Colors.primary, fontWeight: '700' },
  chartBox: { height: 460, ...Platform.select({ web: { overflow: 'hidden' as any } }) },
  chartPlaceholder: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  placeholderText: { color: Colors.textMuted, fontSize: 13 },

  /* ── Order book ── */
  obCard: {
    backgroundColor: Colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 0,
    overflow: 'hidden',
  },
  obTabRow: {
    flexDirection: 'row',
    gap: 18,
    paddingHorizontal: 10,
    paddingTop: 10,
  },
  obTabBtn: { paddingBottom: 4 },
  obTabText: { color: Colors.textMuted, fontSize: 12, fontWeight: '600' },
  obTabTextActive: { color: Colors.textActive, fontWeight: '700' },
  obTabUnderline: {
    height: 2,
    backgroundColor: Colors.primary,
    marginTop: 4,
  },
  obColHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  obColLabel: { fontSize: 10, color: Colors.textMuted, flex: 1 },
  obContent: { paddingHorizontal: 8, paddingVertical: 4, gap: 1 },
  obRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 2.5,
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
  obAskPrice: { fontSize: 11, color: Colors.down, fontVariant: ['tabular-nums'] },
  obBidPrice: { fontSize: 11, color: Colors.up, fontVariant: ['tabular-nums'] },
  obQty: { fontSize: 11, color: Colors.textActive, fontVariant: ['tabular-nums'] },
  obCurrentRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    paddingVertical: 6,
    paddingHorizontal: 4,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: Colors.border,
    marginVertical: 2,
  },
  obCurrentPrice: { fontSize: 15, fontWeight: '800' },
  obCurrentChange: { fontSize: 11, fontWeight: '600' },
  obEmpty: { color: Colors.textMuted, fontSize: 12, textAlign: 'center', paddingVertical: 30 },

  /* ── Trades ── */
  tradeRow: {
    flexDirection: 'row',
    paddingVertical: 3,
    paddingHorizontal: 4,
    gap: 8,
  },
  tradePrice: { fontSize: 11, flex: 1, fontVariant: ['tabular-nums'] },
  tradeQty: { fontSize: 11, color: Colors.textActive, flex: 1, textAlign: 'center', fontVariant: ['tabular-nums'] },
  tradeTime: { fontSize: 11, color: Colors.textMuted, flex: 1, textAlign: 'right' },

  /* ── Order panel ── */
  orderCard: {
    backgroundColor: Colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 10,
  },
  sideRow: { flexDirection: 'row', gap: 6 },
  sideBtn: {
    flex: 1,
    paddingVertical: 9,
    borderRadius: 6,
    backgroundColor: Colors.topBarBg,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
  },
  sideBtnBuyActive: { backgroundColor: Colors.up, borderColor: Colors.up },
  sideBtnSellActive: { backgroundColor: Colors.down, borderColor: Colors.down },
  sideText: { fontSize: 13, fontWeight: '700' },
  sideTextInactive: { color: Colors.textMuted },
  sideTextActiveBuy: { color: '#0a2e1f' },
  sideTextActiveSell: { color: '#3e0a0a' },

  typeRow: { flexDirection: 'row', gap: 18, paddingVertical: 2 },
  typeText: { color: Colors.textMuted, fontSize: 13, fontWeight: '600' },
  typeTextActive: { color: Colors.textActive, fontWeight: '700' },
  typeUnderline: { height: 2, backgroundColor: Colors.primary, marginTop: 3 },

  availRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  availLabel: { color: Colors.textMuted, fontSize: 11 },
  availRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  availValue: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  transferBtn: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 4,
    borderWidth: 1,
    borderColor: Colors.primary,
    backgroundColor: 'rgba(212,175,55,0.08)',
  },
  transferBtnText: { color: Colors.primary, fontSize: 11, fontWeight: '700' },

  inputGroup: { gap: 4 },
  inputGroupLabel: { color: Colors.textMuted, fontSize: 11 },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: Colors.topBarBg,
    borderRadius: 6,
    paddingHorizontal: 10,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  input: {
    flex: 1,
    paddingVertical: 9,
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '600',
    ...Platform.select({ web: { outlineWidth: 0 } as any }),
  },
  inputUnit: { color: Colors.textMuted, fontSize: 11, fontWeight: '600' },

  marketPriceHint: {
    backgroundColor: Colors.topBarBg,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingVertical: 9,
    paddingHorizontal: 10,
  },
  marketPriceText: { color: Colors.textMuted, fontSize: 12 },

  /* Slider（与合约页一致） */
  pctSliderWrap: { gap: 2, paddingVertical: 2 },
  pctLabels: { flexDirection: 'row', justifyContent: 'space-between' },
  pctLabelText: { fontSize: 9, color: Colors.textMuted },
  /* Native fallback chip row */
  pctChipRow: { flexDirection: 'row', gap: 6 },
  pctChip: {
    flex: 1,
    paddingVertical: 5,
    borderRadius: 4,
    backgroundColor: Colors.topBarBg,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
  },
  pctChipActive: { backgroundColor: Colors.primaryDim, borderColor: Colors.primary },
  pctChipText: { color: Colors.textMuted, fontSize: 11, fontWeight: '600' },
  pctChipTextActive: { color: Colors.primary, fontWeight: '700' },

  submitBtn: {
    paddingVertical: 12,
    borderRadius: 6,
    alignItems: 'center',
    marginTop: 4,
  },
  submitBtnBuy: { backgroundColor: Colors.up },
  submitBtnSell: { backgroundColor: Colors.down },
  submitBtnText: { color: '#0a2e1f', fontSize: 14, fontWeight: '800' },

  /* ── Bottom card ── */
  bottomCard: {
    backgroundColor: Colors.surface,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 10,
  },
  bottomTabRow: {
    flexDirection: 'row',
    gap: 20,
    paddingHorizontal: 4,
    marginBottom: 4,
  },
  bottomTab: { paddingVertical: 6 },
  bottomTabText: { color: Colors.textMuted, fontSize: 13, fontWeight: '600' },
  bottomTabTextActive: { color: Colors.textActive, fontWeight: '700' },
  bottomTabUnderline: {
    height: 2,
    backgroundColor: Colors.primary,
    marginTop: 4,
  },

  tableHeader: {
    flexDirection: 'row',
    gap: 6,
    paddingVertical: 8,
    paddingHorizontal: 6,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    backgroundColor: Colors.topBarBg,
  },
  thCell: { color: Colors.textMuted, fontSize: 11, fontWeight: '600' },
  tableRow: {
    flexDirection: 'row',
    gap: 6,
    paddingVertical: 10,
    paddingHorizontal: 6,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    alignItems: 'center',
  },
  tdCell: { color: Colors.textActive, fontSize: 12, fontVariant: ['tabular-nums'] },
  emptyRow: { paddingVertical: 40, alignItems: 'center' },
  emptyText: { color: Colors.textMuted, fontSize: 12 },

  rowCancelBtn: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderWidth: 1,
    borderColor: Colors.border,
    borderRadius: 4,
  },
  rowCancelText: { color: Colors.textMuted, fontSize: 11 },

  holdingsSummary: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'baseline',
    paddingVertical: 8,
    paddingHorizontal: 6,
  },
  holdingsSummaryLabel: { color: Colors.textMuted, fontSize: 12 },
  holdingsSummaryValue: { color: Colors.textActive, fontSize: 15, fontWeight: '700' },

  /* ── Mobile ── */
  mobileFoldBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: Colors.surface,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  mobileFoldText: { color: Colors.textActive, fontSize: 13, fontWeight: '600' },

  /* ── Transfer Modal ── */
  tfOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  tfCard: {
    width: '100%',
    maxWidth: 420,
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    gap: 14,
  },
  tfHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  tfTitle: { color: Colors.textActive, fontSize: 16, fontWeight: '800' },
  tfClose: { padding: 4 },
  tfCloseText: { color: Colors.textMuted, fontSize: 16 },
  tfDirectionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  tfDirectionCard: {
    flex: 1,
    backgroundColor: Colors.topBarBg,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 10,
    gap: 4,
  },
  tfDirectionLabel: { color: Colors.textMuted, fontSize: 10 },
  tfDirectionValue: { color: Colors.textActive, fontSize: 13, fontWeight: '700' },
  tfSwap: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primary,
  },
  tfSwapText: { color: Colors.primary, fontSize: 14, fontWeight: '800' },
  tfAmountHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  tfMaxText: { color: Colors.primary, fontSize: 11, fontWeight: '700' },
  tfHint: { color: Colors.textMuted, fontSize: 11 },
  tfActionsRow: { flexDirection: 'row', gap: 10 },
  tfCancelBtn: {
    flex: 1,
    paddingVertical: 11,
    borderRadius: 6,
    backgroundColor: Colors.topBarBg,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
  },
  tfCancelText: { color: Colors.textMuted, fontSize: 13, fontWeight: '600' },
  tfConfirmBtn: {
    flex: 1,
    paddingVertical: 11,
    borderRadius: 6,
    backgroundColor: Colors.primary,
    alignItems: 'center',
  },
  tfConfirmText: { color: Colors.background, fontSize: 13, fontWeight: '800' },
  tfBtnDisabled: { opacity: 0.5 },
});
