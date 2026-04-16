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
  Platform,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import TradingViewChart from '../../components/chart/TradingViewChart';
import TransferModal, {
  type TransferDirection,
} from '../../components/assets/TransferModal';
import SymbolDropdown, {
  type SymbolTab,
  type SymbolMeta,
} from '../../components/trading/SymbolDropdown';
import SpotFillReceiptModal from '../../components/trading/SpotFillReceiptModal';
import AssetSymbolIcon from '../../components/ui/AssetSymbolIcon';
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
import { tradingWs } from '../../services/websocket/tradingWs';
import {
  getSpotFillReceiptMuted,
  setSpotFillReceiptMuted,
} from '../../services/storage/preferences';
import { Colors, Shadows } from '../../theme/colors';
import { showAlert as showDialogAlert } from '../../services/utils/dialog';

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

const showAlert = (title: string, message?: string) => {
  showDialogAlert(message ?? title, message ? title : undefined);
};

/**
 * 现货手续费率（展示 + 滑块预留）。
 * 后端冻结时按 qty*price*(1+fee) 扣，若前端滑块 100% 把全部 quote 余额都填进 amount，
 * 冻结量 = amount*(1+fee) 就会超出可用余额，返回 "insufficient balance"。
 * 所以买单方向的滑块必须基于 availableBalance/(1+fee) 计算，给手续费留位置。
 */
const SPOT_FEE_RATE = 0.001; // 0.1%

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

  const selectedMeta = useMemo(
    () => symbols.find((s) => s.symbol === selectedSymbol),
    [symbols, selectedSymbol],
  );

  const marketSymbol = useMemo(
    () => toMarketSymbol(selectedSymbol, selectedMeta?.category || 'crypto'),
    [selectedSymbol, selectedMeta],
  );

  /* ── Shared SymbolDropdown props (spot: crypto + stocks only, no forex/futures) ── */
  const symbolDropdownTabs = useMemo<SymbolTab[]>(
    () => [
      { key: 'crypto', label: t('trading.crypto') },
      { key: 'stocks', label: t('trading.stock') },
    ],
    [t],
  );
  const symbolsByTab = useMemo<Record<string, string[]>>(() => {
    const byTab: Record<string, string[]> = { crypto: [], stocks: [] };
    for (const s of symbols) {
      if (s.category === 'crypto' || s.category === 'stocks') {
        byTab[s.category].push(s.symbol);
      }
    }
    return byTab;
  }, [symbols]);
  // Lookup map keyed by raw symbol so `getSymbolMeta` is O(1)
  const symbolMetaMap = useMemo(() => {
    const m = new Map<string, SpotSupportedSymbol>();
    for (const s of symbols) m.set(s.symbol, s);
    return m;
  }, [symbols]);
  const assetCategoryMap = useMemo(() => {
    const m = new Map<string, 'crypto' | 'stock'>();
    for (const s of symbols) {
      const category = s.category === 'stocks' ? 'stock' : 'crypto';
      m.set(s.base_asset, category);
      if (s.category === 'crypto') {
        m.set(s.quote_asset, 'crypto');
      }
    }
    return m;
  }, [symbols]);
  const getSymbolMeta = useCallback(
    (sym: string): SymbolMeta | undefined => {
      const meta = symbolMetaMap.get(sym);
      if (!meta) return undefined;
      return {
        subLabel: meta.display_name || undefined,
        displaySymbol: toDisplaySymbol(meta.symbol),
        quoteSymbol: toMarketSymbol(meta.symbol, meta.category),
        pricePrecision: meta.price_precision,
        category: meta.category === 'stocks' ? 'stock' : 'crypto',
      };
    },
    [symbolMetaMap],
  );
  const initialDropdownTab: string = selectedMeta?.category === 'stocks' ? 'stocks' : 'crypto';
  const handleSymbolSelect = useCallback((sym: string) => {
    setSelectedSymbol(sym);
    setShowSymbolDropdown(false);
    setPriceInput('');
    setQtyInput('');
    setAmountInput('');
    setSliderPct(0);
  }, []);

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
  // spot page defaults to pulling funds from futures → spot; modal owns its
  // own direction swap after opening.
  const [showTransferModal, setShowTransferModal] = useState(false);
  const transferDefaultDirection: TransferDirection = 'futures_to_spot';

  /* ── Market fill receipt modal ──
     市价成交后的回执弹窗：告诉用户「买/卖了多少币」并展示手续费、总额等关键信息。
     限价单不弹（限价要等撮合，弹了也没数据）。用户可勾选「下次不再提示」，
     偏好用 AsyncStorage 持久化（key: tongxin_spot_fill_receipt_muted）。 */
  const [showFillReceipt, setShowFillReceipt] = useState(false);
  const [fillReceiptOrder, setFillReceiptOrder] = useState<SpotOrder | null>(null);
  const [fillReceiptMuted, setFillReceiptMutedState] = useState(false);
  useEffect(() => {
    let cancelled = false;
    getSpotFillReceiptMuted().then((v) => {
      if (!cancelled) setFillReceiptMutedState(v);
    });
    return () => {
      cancelled = true;
    };
  }, []);
  const handleFillReceiptMutedChange = useCallback((muted: boolean) => {
    setFillReceiptMutedState(muted);
    // 持久化失败静默（preferences.ts 内部已 try/catch），不影响 UX
    setSpotFillReceiptMuted(muted);
  }, []);

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
      // 限价单：若用户未输入价格，自动用当前市价回填 priceInput
      // 否则 handlePlaceOrder 会因为 priceInput 为空而 Alert 拦截，
      // 而 RN Web 的 Alert.alert 是 no-op，用户看到的就是「点了没反应」。
      if (orderType === 'limit' && !priceInput && currentPrice > 0) {
        setPriceInput(currentPrice.toFixed(pricePrecision));
      }
      if (side === 'buy') {
        // 后端严格用 needed = qty × price × (1 + fee) 冻结（见 spot_repo.go ExecuteSpotLimitPlace / MarketOrder）
        // 所以必须：先算「扣完 fee 的 quoteCost 上限」，再求 qty 并向下截断精度，保证反推 needed ≤ availableBalance。
        // 反过来（先算 amount 再除价格）会因为 qty 精度截断丢精度 → qty*price 变小、但加 fee 后可能仍超 availableBalance。
        const maxQuoteCost = availableBalance / (1 + SPOT_FEE_RATE);
        const rawQty = ((maxQuoteCost * pct) / 100) / effectivePrice;
        const factor = Math.pow(10, qtyPrecision);
        // 向下截断到 qtyPrecision，和后端 roundDown 对齐
        let qty = Math.floor(rawQty * factor) / factor;
        if (qty <= 0) {
          setQtyInput('');
          setAmountInput('');
          return;
        }
        // 余额刷新有 WS 延迟，100% 时再退一档精度做安全垫，避免边界浮点尾数翻车
        if (pct === 100) {
          qty = Math.max(0, qty - 1 / factor);
          qty = Math.floor(qty * factor) / factor;
        }
        if (qty <= 0) {
          setQtyInput('');
          setAmountInput('');
          return;
        }
        const quoteCost = qty * effectivePrice;
        setQtyInput(qty.toFixed(qtyPrecision));
        setAmountInput(quoteCost.toFixed(2));
      } else {
        // 卖：滑块百分比作用于可用 base 持仓，同样向下截断精度
        const factor = Math.pow(10, qtyPrecision);
        let qty = Math.floor(((availableBalance * pct) / 100) * factor) / factor;
        if (qty <= 0) {
          setQtyInput('');
          setAmountInput('');
          return;
        }
        if (pct === 100) {
          qty = Math.max(0, qty - 1 / factor);
          qty = Math.floor(qty * factor) / factor;
        }
        if (qty <= 0) {
          setQtyInput('');
          setAmountInput('');
          return;
        }
        setQtyInput(qty.toFixed(qtyPrecision));
        setAmountInput((qty * effectivePrice).toFixed(2));
      }
    },
    [availableBalance, effectivePrice, side, qtyPrecision, orderType, priceInput, currentPrice, pricePrecision],
  );

  /* ═════════════════════════════════════════
     Submit order
     ═════════════════════════════════════════ */
  const handlePlaceOrder = async () => {
    if (!user) {
      showAlert(t('auth.notLoggedIn'));
      return;
    }
    const qtyNum = parseFloat(qtyInput);
    const amtNum = parseFloat(amountInput);
    const hasQty = qtyInput && isFinite(qtyNum) && qtyNum > 0;
    const hasAmt = amountInput && isFinite(amtNum) && amtNum > 0;
    if (!hasQty && !hasAmt) {
      showAlert(t('trading.enterQuantity') || '请输入数量');
      return;
    }

    const req: any = {
      symbol: selectedSymbol,
      side,
      order_type: orderType,
    };

    // 市价买单：传 quote_qty（要花多少 USDT），让后端按实时成交价反推 qty。
    // 如果前端自己先按 currentPrice 算 qty 再传过去，后端实时取价时行情如果微涨，
    // qty × backendPrice × (1+fee) 会超出 availableBalance 触发 insufficient balance。
    if (orderType === 'market' && side === 'buy' && hasAmt) {
      req.quote_qty = amtNum;
    } else if (hasQty) {
      req.qty = qtyNum;
    } else {
      // 限价单必须有 qty；市价卖单也必须有 qty
      showAlert(t('trading.enterQuantity') || '请输入数量');
      return;
    }

    if (orderType === 'limit') {
      const p = parseFloat(priceInput);
      if (!priceInput || !isFinite(p) || p <= 0) {
        showAlert(t('trading.enterLimitPrice') || '请输入限价');
        return;
      }
      req.price = p;
    }

    setPlacing(true);
    try {
      const placed = await spotApi.placeOrder(req);
      // 市价成交 + 用户没 mute → 弹回执（限价单走 alert，因为此刻还没成交，弹回执没数据）
      const isMarketFilled =
        placed && placed.order_type === 'market' && placed.status === 'filled';
      if (isMarketFilled && !fillReceiptMuted) {
        setFillReceiptOrder(placed);
        setShowFillReceipt(true);
      } else {
        showAlert(t('trading.spotOrderPlaced'));
      }
      setQtyInput('');
      setAmountInput('');
      setSliderPct(0);
      refreshPending();
      refreshAccount();
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || t('trading.spotInsufficientBalance');
      showAlert(msg);
    } finally {
      setPlacing(false);
    }
  };

  /* ═════════════════════════════════════════
     Transfer 划转 (logic lives in components/assets/TransferModal.tsx)
     ═════════════════════════════════════════ */
  const handleTransferSuccess = useCallback(
    (amount: number) => {
      refreshAccount();
      showAlert(
        t('assets.transferSuccessTitle'),
        t('assets.transferSuccessBody', { amount: amount.toFixed(2) }),
      );
    },
    [refreshAccount, t],
  );

  const handleCancel = async (orderId: string) => {
    try {
      await spotApi.cancelOrder(orderId);
      refreshPending();
      refreshAccount();
    } catch (e: any) {
      showAlert(e?.response?.data?.error || e?.message || t('common.error') || '撤单失败');
    }
  };

  /* ═════════════════════════════════════════
     Render sub-sections
     ═════════════════════════════════════════ */

  /* ── Hero Bar: symbol chip + 大号价格 + 24h 卡片组 ── */
  const renderHeroBar = () => {
    const isCrypto = selectedMeta?.category === 'crypto';
    const turnover = currentQuote?.volume && currentPrice
      ? currentQuote.volume * currentPrice
      : undefined;
    const up = percentChange >= 0;
    const changeColor = up ? Colors.up : Colors.down;
    const changeBg = up ? Colors.upDim : Colors.downDim;
    // 币种 / 股票徽标：用 base 首字母（简洁、零依赖）
    const badge = (baseAsset || displaySymbol.charAt(0)).slice(0, 3).toUpperCase();

    const stats: { label: string; value: string; accent?: string }[] = [
      {
        label: t('trading.high24h'),
        value: formatPrice(currentQuote?.high, pricePrecision),
      },
      {
        label: t('trading.low24h'),
        value: formatPrice(currentQuote?.low, pricePrecision),
      },
    ];
    if (isCrypto) {
      stats.push(
        {
          label: `${t('trading.volume24h')}(${baseAsset || '--'})`,
          value: formatCompact(currentQuote?.volume),
        },
        {
          label: `${t('trading.turnover24h')}(${quoteAsset})`,
          value: formatCompact(turnover),
        },
      );
    }

    return (
      <View style={styles.heroBar}>
        {/* ── Left: symbol identity + big price ── */}
        <View style={styles.heroLeft}>
          <TouchableOpacity
            style={styles.heroSymbolChip}
            activeOpacity={0.7}
            onPress={() => setShowSymbolDropdown(true)}
          >
            <View style={[styles.heroBadge, { backgroundColor: Colors.primaryDim }]}>
              <Text style={styles.heroBadgeText}>{badge}</Text>
            </View>
            <View style={{ gap: 2 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                <Text style={styles.heroSymbol}>{displaySymbol}</Text>
                <Text style={styles.heroChevron}>▾</Text>
              </View>
              {!!selectedMeta?.display_name && (
                <Text style={styles.heroSymbolSub} numberOfLines={1}>
                  {selectedMeta.display_name}
                </Text>
              )}
            </View>
          </TouchableOpacity>

          <View style={styles.heroPriceBlock}>
            <Text style={[styles.heroPrice, { color: changeColor }]}>
              {formatPrice(currentPrice, pricePrecision)}
            </Text>
            <View style={[styles.heroChangePill, { backgroundColor: changeBg, borderColor: changeColor + '55' }]}>
              <Text style={[styles.heroChangePillText, { color: changeColor }]}>
                {up ? '▲' : '▼'} {up ? '+' : ''}{percentChange.toFixed(2)}%
              </Text>
            </View>
          </View>
        </View>

        {/* ── Right: 24h stat cards ── */}
        <View style={styles.heroStatGrid}>
          {stats.map((s) => (
            <View key={s.label} style={styles.heroStatCard}>
              <Text style={styles.heroStatLabel} numberOfLines={1}>{s.label}</Text>
              <Text style={styles.heroStatValue} numberOfLines={1}>{s.value}</Text>
            </View>
          ))}
        </View>
      </View>
    );
  };

  /* ── Chart ── */
  const renderChart = () => {
    const tfLabel: Record<string, string> = {
      '1min': '1m',
      '5min': '5m',
      '15min': '15m',
      '1h': '1H',
      '4h': '4H',
      '1day': '1D',
    };
    return (
      <View style={styles.chartCard}>
        <View style={styles.chartHeader}>
          <View style={styles.chartTitleWrap}>
            <Text style={styles.chartTitle}>{marketSymbol}</Text>
            <View style={styles.chartLiveDot} />
            <Text style={styles.chartTitleSub}>
              {klinesLoading ? t('common.loading') : 'Live'}
            </Text>
          </View>
          <View style={styles.tfRow}>
            {['1min', '5min', '15min', '1h', '4h', '1day'].map((tf) => (
              <TouchableOpacity
                key={tf}
                onPress={() => setTimeframe(tf)}
                style={[styles.tfBtn, tf === timeframe && styles.tfBtnActive]}
                activeOpacity={0.7}
              >
                <Text style={[styles.tfText, tf === timeframe && styles.tfTextActive]}>
                  {tfLabel[tf] || tf}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
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
                {klinesLoading ? t('common.loading') : `${marketSymbol} ${tfLabel[timeframe] || timeframe}`}
              </Text>
            </View>
          )}
        </View>
      </View>
    );
  };

  /* ── Order book panel ── */
  const renderOrderBookPanel = () => {
    // Spread: 最优 ask - 最优 bid（asks 已倒序，最优是最后一个；bids 最优是第一个）
    const bestAsk = orderBook.asks.length ? orderBook.asks[orderBook.asks.length - 1].price : 0;
    const bestBid = orderBook.bids.length ? orderBook.bids[0].price : 0;
    const spread = bestAsk && bestBid ? bestAsk - bestBid : 0;
    const spreadPct = bestAsk && bestBid ? (spread / bestAsk) * 100 : 0;

    return (
      <View style={styles.obCard}>
        <View style={styles.obTabRow}>
          <TouchableOpacity
            onPress={() => setObTab('orderbook')}
            style={[styles.obTabPill, obTab === 'orderbook' && styles.obTabPillActive]}
            activeOpacity={0.7}
          >
            <Text
              style={[styles.obTabPillText, obTab === 'orderbook' && styles.obTabPillTextActive]}
            >
              {t('spot.orderBook') || '订单簿'}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => setObTab('trades')}
            style={[styles.obTabPill, obTab === 'trades' && styles.obTabPillActive]}
            activeOpacity={0.7}
          >
            <Text
              style={[styles.obTabPillText, obTab === 'trades' && styles.obTabPillTextActive]}
            >
              {t('spot.recentTrades') || '最近成交'}
            </Text>
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
                <View style={styles.obSpreadBox}>
                  <Text style={styles.obSpreadLabel}>Spread</Text>
                  <Text style={styles.obSpreadValue}>
                    {spread > 0 ? `${spreadPct.toFixed(3)}%` : '--'}
                  </Text>
                </View>
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
                <View style={styles.emptyState}>
                  <Text style={styles.emptyStateIcon}>⟳</Text>
                  <Text style={styles.obEmpty}>{t('common.noData')}</Text>
                </View>
              ) : (
                trades.map((tr) => (
                  <View key={tr.id} style={styles.tradeRow}>
                    <View style={[styles.tradeDot, { backgroundColor: tr.side === 'buy' ? Colors.up : Colors.down }]} />
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
  };

  /* ── Order panel ── */
  const renderOrderPanel = () => {
    const hintUnit = side === 'buy' ? quoteAsset : baseAsset;
    // Estimate: 数量 × 有效价格；limit 用输入价，market 用当前价
    const effectivePrice =
      orderType === 'market'
        ? currentPrice
        : parseFloat(priceInput || '0') || currentPrice;
    const estQty = parseFloat(qtyInput || '0');
    const estAmount =
      parseFloat(amountInput || '0') || (estQty && effectivePrice ? estQty * effectivePrice : 0);
    const feeRate = SPOT_FEE_RATE; // 展示性估算；与滑块预留保持一致
    const estFee = estAmount * feeRate;
    const receiveQty = side === 'buy' ? estQty : 0;
    const receiveAmt = side === 'sell' ? estAmount - estFee : 0;

    return (
      <View style={styles.orderCard}>
        {/* Buy/Sell segmented */}
        <View style={styles.sideSegment}>
          <TouchableOpacity
            style={[styles.sideSegBtn, side === 'buy' && styles.sideSegBtnBuyActive]}
            onPress={() => {
              setSide('buy');
              setSliderPct(0);
            }}
            activeOpacity={0.85}
          >
            <Text
              style={[
                styles.sideSegText,
                side === 'buy' ? styles.sideSegTextBuyActive : styles.sideSegTextInactive,
              ]}
            >
              {t('trading.spotBuy')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.sideSegBtn, side === 'sell' && styles.sideSegBtnSellActive]}
            onPress={() => {
              setSide('sell');
              setSliderPct(0);
            }}
            activeOpacity={0.85}
          >
            <Text
              style={[
                styles.sideSegText,
                side === 'sell' ? styles.sideSegTextSellActive : styles.sideSegTextInactive,
              ]}
            >
              {t('trading.spotSell')}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Order type pill group */}
        <View style={styles.typePillRow}>
          {(['limit', 'market'] as const).map((ot) => (
            <TouchableOpacity
              key={ot}
              style={[styles.typePill, orderType === ot && styles.typePillActive]}
              onPress={() => setOrderType(ot)}
              activeOpacity={0.8}
            >
              <Text style={[styles.typePillText, orderType === ot && styles.typePillTextActive]}>
                {ot === 'limit' ? t('trading.limit') || '限价' : t('trading.marketOrder') || '市价'}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* Available + Transfer */}
        <View style={styles.availCard}>
          <View style={{ flex: 1 }}>
            <Text style={styles.availLabel}>
              {t('spot.availableBalance') || '可用'}
            </Text>
            <Text style={styles.availValueBig} numberOfLines={1}>
              {availableBalance.toFixed(side === 'buy' ? 2 : qtyPrecision)}{' '}
              <Text style={styles.availUnit}>{hintUnit}</Text>
            </Text>
          </View>
          <TouchableOpacity
            style={styles.transferBtn}
            activeOpacity={0.7}
            onPress={() => {
              if (!user) {
                showAlert(t('auth.notLoggedIn'));
                return;
              }
              setShowTransferModal(true);
            }}
          >
            <Text style={styles.transferBtnText}>
              ⇅ {t('assets.transferAction') || '划转'}
            </Text>
          </TouchableOpacity>
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
              {t('trading.marketOrder') || '市价'} ≈{' '}
              <Text style={{ color: Colors.textActive, fontWeight: '700' }}>
                {formatPrice(currentPrice, pricePrecision)}
              </Text>{' '}
              {quoteAsset}
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

        {/* Percent slider */}
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
              style={{ width: '100%', height: 4, accentColor: Colors.primary, cursor: 'pointer' }}
            />
          ) : null}
          <View style={styles.pctChipRow}>
            {[25, 50, 75, 100].map((p) => (
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

        {/* Estimate card */}
        {estAmount > 0 && (
          <View style={styles.estimateCard}>
            <View style={styles.estimateRow}>
              <Text style={styles.estimateLabel}>
                {t('trading.totalValue') || '总额'}
              </Text>
              <Text style={styles.estimateValue}>
                ≈ {estAmount.toFixed(2)} {quoteAsset}
              </Text>
            </View>
            <View style={styles.estimateRow}>
              <Text style={styles.estimateLabel}>
                {t('trading.fee') || '手续费'} · 0.10%
              </Text>
              <Text style={styles.estimateValue}>
                ≈ {estFee.toFixed(4)} {quoteAsset}
              </Text>
            </View>
            <View style={[styles.estimateRow, styles.estimateRowEmph]}>
              <Text style={styles.estimateLabel}>
                {side === 'buy' ? t('trading.receive') || '获得' : t('trading.receive') || '获得'}
              </Text>
              <Text style={[styles.estimateValueEmph, { color: side === 'buy' ? Colors.up : Colors.down }]}>
                {side === 'buy'
                  ? `${receiveQty.toFixed(qtyPrecision)} ${baseAsset}`
                  : `${receiveAmt.toFixed(2)} ${quoteAsset}`}
              </Text>
            </View>
          </View>
        )}

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
  const renderBottomTable = () => {
    const tabs = [
      {
        key: 'current' as const,
        label: t('spot.currentOrders') || '当前委托',
        count: pendingOrders.length,
      },
      {
        key: 'history' as const,
        label: t('spot.orderHistory') || '历史委托',
        count: historyOrders.length,
      },
      {
        key: 'holdings' as const,
        label: t('spot.holdings') || '资产持仓',
        count: account?.holdings.length || 0,
      },
    ];
    return (
      <View style={styles.bottomCard}>
        <View style={styles.bottomTabRow}>
          {tabs.map((tab) => {
            const active = tab.key === bottomTab;
            return (
              <TouchableOpacity
                key={tab.key}
                style={[styles.bottomTabPill, active && styles.bottomTabPillActive]}
                onPress={() => setBottomTab(tab.key)}
                activeOpacity={0.8}
              >
                <Text
                  style={[
                    styles.bottomTabPillText,
                    active && styles.bottomTabPillTextActive,
                  ]}
                >
                  {tab.label}
                </Text>
                {tab.count > 0 && (
                  <View style={[styles.tabCountBadge, active && styles.tabCountBadgeActive]}>
                    <Text
                      style={[
                        styles.tabCountBadgeText,
                        active && styles.tabCountBadgeTextActive,
                      ]}
                    >
                      {tab.count}
                    </Text>
                  </View>
                )}
              </TouchableOpacity>
            );
          })}
        </View>

        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          <View style={{ minWidth: 780 }}>
            {bottomTab === 'holdings' ? renderHoldingsTable() : renderOrderTable()}
          </View>
        </ScrollView>
      </View>
    );
  };

  const renderOrderTable = () => {
    const rows = bottomTab === 'current' ? pendingOrders : historyOrders;
    const isPending = bottomTab === 'current';

    // Status pill color map
    const statusStyle = (status: string) => {
      switch (status) {
        case 'filled':
          return { bg: Colors.upDim, color: Colors.up, label: t('trading.filled') || '已成交' };
        case 'pending':
          return { bg: Colors.primaryDim, color: Colors.primary, label: t('trading.pending') || '待成交' };
        case 'cancelled':
          return {
            bg: 'rgba(107,107,128,0.15)',
            color: Colors.textMuted,
            label: t('trading.cancelled') || '已撤销',
          };
        case 'rejected':
          return { bg: Colors.downDim, color: Colors.down, label: t('trading.rejected') || '已拒绝' };
        default:
          return { bg: 'rgba(107,107,128,0.15)', color: Colors.textSecondary, label: status };
      }
    };

    // Parse display symbol → base/quote for unit labels
    const splitSymbol = (sym: string): [string, string] => {
      const parts = toDisplaySymbol(sym).split('/');
      return [parts[0] || '', parts[1] || ''];
    };

    // Format time into two lines: date + time
    const formatTimeLines = (ts: number | string): [string, string] => {
      const d = new Date(ts);
      const date = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
        d.getDate(),
      ).padStart(2, '0')}`;
      const time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(
        2,
        '0',
      )}:${String(d.getSeconds()).padStart(2, '0')}`;
      return [date, time];
    };

    return (
      <>
        <View style={styles.tableHeader}>
          <Text style={[styles.thCell, { flex: 1.7 }]}>{t('trading.pair') || '交易对'}</Text>
          <Text style={[styles.thCell, { flex: 1.3 }]}>{t('spot.price') || '价格'}</Text>
          <Text style={[styles.thCell, { flex: 1.2 }]}>{t('spot.qty') || '数量'}</Text>
          <Text style={[styles.thCell, { flex: 1.2 }]}>{t('spot.amount') || '金额'}</Text>
          <Text style={[styles.thCell, { flex: 1.3 }]}>{t('trading.time') || '时间'}</Text>
          <Text style={[styles.thCell, { flex: 1, textAlign: 'right' }]}>
            {isPending ? t('spot.cancelOrder') || '操作' : '状态'}
          </Text>
        </View>
        {rows.length === 0 ? (
          <View style={styles.emptyStateFull}>
            <Text style={styles.emptyStateIconLg}>📋</Text>
            <Text style={styles.emptyText}>{t('spot.noOrders') || t('common.noData')}</Text>
          </View>
        ) : (
          rows.map((o) => {
            const st = statusStyle(o.status);
            const [base, quote] = splitSymbol(o.symbol);
            const [dateStr, timeStr] = formatTimeLines(o.created_at);
            const isBuy = o.side === 'buy';
            const sideColor = isBuy ? Colors.up : Colors.down;
            const sideBg = isBuy ? Colors.upDim : Colors.downDim;
            const typeLabel =
              o.order_type === 'market' ? t('trading.marketOrder') || '市价' : t('trading.limit') || '限价';
            const priceText =
              o.order_type === 'market'
                ? o.filled_price
                  ? formatPrice(o.filled_price, pricePrecision)
                  : '--'
                : formatPrice(o.price ?? 0, pricePrecision);
            return (
              <View key={o.id} style={styles.tableRow}>
                {/* Left accent stripe — color coded by side */}
                <View style={[styles.rowAccent, { backgroundColor: sideColor }]} />

                {/* Symbol + side pill (stacked) */}
                <View style={styles.rowSymbolCol}>
                  <View style={styles.rowSymbolLine}>
                    <View style={[styles.tableSymbolDot, { backgroundColor: sideColor }]} />
                    <Text style={styles.rowSymbolText}>{toDisplaySymbol(o.symbol)}</Text>
                  </View>
                  <View style={[styles.sidePill, { backgroundColor: sideBg }]}>
                    <Text style={[styles.sidePillText, { color: sideColor }]}>
                      {isBuy ? t('trading.spotBuy') || '买入' : t('trading.spotSell') || '卖出'}
                    </Text>
                  </View>
                </View>

                {/* Price + order type (stacked) */}
                <View style={[styles.rowStackedCol, { flex: 1.3 }]}>
                  <Text style={styles.rowStackedMain}>{priceText}</Text>
                  <Text style={styles.rowStackedSub}>{typeLabel}</Text>
                </View>

                {/* Qty + base asset (stacked) */}
                <View style={[styles.rowStackedCol, { flex: 1.2 }]}>
                  <Text style={styles.rowStackedMain}>{(+o.qty).toFixed(qtyPrecision)}</Text>
                  <Text style={styles.rowStackedSub}>{base}</Text>
                </View>

                {/* Amount + quote asset (stacked) */}
                <View style={[styles.rowStackedCol, { flex: 1.2 }]}>
                  <Text style={styles.rowStackedMain}>{(+o.quote_qty).toFixed(2)}</Text>
                  <Text style={styles.rowStackedSub}>{toDisplayQuote(o.quote_asset) || quote}</Text>
                </View>

                {/* Date + time (stacked) */}
                <View style={[styles.rowStackedCol, { flex: 1.3 }]}>
                  <Text style={styles.rowStackedTimeMain}>{dateStr}</Text>
                  <Text style={styles.rowStackedTimeSub}>{timeStr}</Text>
                </View>

                {/* Action or status */}
                <View style={styles.rowActionCol}>
                  {isPending ? (
                    <TouchableOpacity
                      onPress={() => handleCancel(o.id)}
                      style={styles.rowCancelBtn}
                      activeOpacity={0.7}
                    >
                      <Text style={styles.rowCancelText}>
                        {t('spot.cancelOrder') || t('common.cancel') || '撤单'}
                      </Text>
                    </TouchableOpacity>
                  ) : (
                    <View style={[styles.statusPill, { backgroundColor: st.bg }]}>
                      <Text style={[styles.statusPillText, { color: st.color }]}>
                        {st.label}
                      </Text>
                    </View>
                  )}
                </View>
              </View>
            );
          })
        )}
      </>
    );
  };

  const renderHoldingsTable = () => {
    if (!account || account.holdings.length === 0) {
      return (
        <View style={styles.emptyStateFull}>
          <Text style={styles.emptyStateIconLg}>💼</Text>
          <Text style={styles.emptyText}>{t('common.noData')}</Text>
        </View>
      );
    }
    return (
      <>
        <View style={styles.holdingsSummary}>
          <View>
            <Text style={styles.holdingsSummaryLabel}>
              {t('trading.totalValue') || '总估值'}
            </Text>
            <Text style={styles.holdingsSummaryValue}>
              {account.total_valuation_usdt.toFixed(2)}
              <Text style={styles.holdingsSummaryUnit}> USDT</Text>
            </Text>
          </View>
          <View style={styles.holdingsMeta}>
            <Text style={styles.holdingsMetaLabel}>
              {account.holdings.length} {t('spot.assets') || '资产'}
            </Text>
          </View>
        </View>
        <View style={styles.tableHeader}>
          <Text style={[styles.thCell, { flex: 1.5 }]}>{t('assets.assetTableAsset') || '币种'}</Text>
          <Text style={[styles.thCell, { flex: 1.3 }]}>{t('assets.available') || '可用'}</Text>
          <Text style={[styles.thCell, { flex: 1.2 }]}>{t('assets.frozen') || '冻结'}</Text>
          <Text style={[styles.thCell, { flex: 1.3 }]}>
            {t('trading.totalValue') || '估值'}
          </Text>
          <Text style={[styles.thCell, { flex: 1.2, textAlign: 'right' }]}>
            {t('assets.unrealizedPnl') || '未实现盈亏'}
          </Text>
        </View>
        {account.holdings.map((h) => {
          const pnl = h.unrealized_pnl ?? null;
          const pnlUp = pnl != null && pnl >= 0;
          const holdingCategory = assetCategoryMap.get(h.asset);
          return (
            <View key={h.asset} style={styles.tableRow}>
              {/* Asset + symbol stacked */}
              <View style={[styles.rowSymbolCol, { flex: 1.5 }]}>
                <View style={styles.rowSymbolLine}>
                  <AssetSymbolIcon
                    symbol={h.asset}
                    category={holdingCategory}
                    size={30}
                    style={styles.holdingAssetIcon}
                  />
                  <Text style={styles.rowSymbolText}>{h.asset}</Text>
                </View>
              </View>
              {/* Available */}
              <View style={[styles.rowStackedCol, { flex: 1.3 }]}>
                <Text style={styles.rowStackedMain}>{h.available.toFixed(6)}</Text>
                <Text style={styles.rowStackedSub}>{h.asset}</Text>
              </View>
              {/* Frozen */}
              <View style={[styles.rowStackedCol, { flex: 1.2 }]}>
                <Text style={[styles.rowStackedMain, { color: Colors.textSecondary }]}>
                  {h.frozen.toFixed(6)}
                </Text>
                <Text style={styles.rowStackedSub}>{h.asset}</Text>
              </View>
              {/* Valuation */}
              <View style={[styles.rowStackedCol, { flex: 1.3 }]}>
                <Text style={styles.rowStackedMain}>{h.valuation_usdt.toFixed(2)}</Text>
                <Text style={styles.rowStackedSub}>USDT</Text>
              </View>
              {/* PnL */}
              <View style={[styles.rowActionCol, { flex: 1.2 }]}>
                {pnl != null ? (
                  <View
                    style={[
                      styles.pnlPill,
                      { backgroundColor: pnlUp ? Colors.upDim : Colors.downDim },
                    ]}
                  >
                    <Text
                      style={[
                        styles.pnlPillText,
                        { color: pnlUp ? Colors.up : Colors.down },
                      ]}
                    >
                      {pnlUp ? '+' : ''}
                      {pnl.toFixed(2)}
                    </Text>
                  </View>
                ) : (
                  <Text style={[styles.tdCell, { color: Colors.textMuted }]}>--</Text>
                )}
              </View>
            </View>
          );
        })}
      </>
    );
  };

  /* ═════════════════════════════════════════
     Layout
     ═════════════════════════════════════════ */

  /* ── Transfer Modal: shared component from components/assets/TransferModal.tsx ── */
  const transferModal = (
    <TransferModal
      visible={showTransferModal}
      onClose={() => setShowTransferModal(false)}
      onSuccess={handleTransferSuccess}
      defaultDirection={transferDefaultDirection}
    />
  );

  /* ── Market fill receipt modal ── */
  const fillReceiptModal = (
    <SpotFillReceiptModal
      visible={showFillReceipt}
      order={fillReceiptOrder}
      muted={fillReceiptMuted}
      onMutedChange={handleFillReceiptMutedChange}
      onClose={() => setShowFillReceipt(false)}
    />
  );

  if (isDesktop) {
    return (
      <>
        <ScrollView
          style={styles.container}
          contentContainerStyle={{ padding: 12, gap: 10 }}
        >
          {/* Hero bar: symbol + price + 24h stat cards */}
          <View style={{ zIndex: 20 }}>{renderHeroBar()}</View>

          {/* 3-col main area (chart + orderbook + order panel) */}
          <View style={styles.mainRow}>
            <View style={styles.centerCol}>{renderChart()}</View>
            <View style={styles.obCol}>{renderOrderBookPanel()}</View>
            <View style={styles.rightCol}>{renderOrderPanel()}</View>
          </View>

          {/* Bottom orders table */}
          {renderBottomTable()}
        </ScrollView>
        {transferModal}
        {fillReceiptModal}
        <SymbolDropdown
          visible={showSymbolDropdown}
          selectedSymbol={selectedSymbol}
          tabs={symbolDropdownTabs}
          symbolsByTab={symbolsByTab}
          quotes={quotes}
          initialTab={initialDropdownTab}
          onSelect={handleSymbolSelect}
          onClose={() => setShowSymbolDropdown(false)}
          getMeta={getSymbolMeta}
        />
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
        <View style={{ zIndex: 20 }}>{renderHeroBar()}</View>
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
      {transferModal}
      {fillReceiptModal}
      <SymbolDropdown
        visible={showSymbolDropdown}
        selectedSymbol={selectedSymbol}
        tabs={symbolDropdownTabs}
        symbolsByTab={symbolsByTab}
        quotes={quotes}
        initialTab={initialDropdownTab}
        onSelect={handleSymbolSelect}
        onClose={() => setShowSymbolDropdown(false)}
        getMeta={getSymbolMeta}
      />
    </>
  );
}

/* ════════════════════════════════════════════
   Styles
   ════════════════════════════════════════════ */

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: Colors.background },

  /* ══════════════════════════════════════
     Hero bar (顶部 symbol + 价格 + 24h 卡片)
     ══════════════════════════════════════ */
  heroBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 18,
    paddingHorizontal: 16,
    paddingVertical: 14,
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    zIndex: 20,
    ...Shadows.card,
  },
  heroLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    flexShrink: 0,
  },
  heroSymbolChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingRight: 6,
  },
  heroBadge: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  heroBadgeText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 0.4,
  },
  heroSymbol: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
    letterSpacing: 0.3,
  },
  heroChevron: {
    color: Colors.textMuted,
    fontSize: 11,
    marginLeft: 4,
  },
  heroSymbolSub: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
    maxWidth: 180,
  },
  heroPriceBlock: {
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: 4,
    paddingLeft: 16,
    borderLeftWidth: 1,
    borderLeftColor: Colors.border,
  },
  heroPrice: {
    fontSize: 26,
    fontWeight: '800',
    fontVariant: ['tabular-nums'],
    lineHeight: 30,
  },
  heroChangePill: {
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 999,
    borderWidth: 1,
  },
  heroChangePillText: {
    fontSize: 11,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
  },
  heroStatGrid: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'stretch',
    gap: 10,
    flexWrap: 'wrap',
  },
  heroStatCard: {
    flex: 1,
    minWidth: 92,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
    gap: 4,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  heroStatLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  heroStatValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
  },

  chevron: { color: Colors.textMuted, fontSize: 10 },

  /* ── Desktop main row ── */
  mainRow: { flexDirection: 'row', gap: 10 },
  centerCol: { flex: 1, minWidth: 0 },
  obCol: { width: 240 },
  rightCol: { width: 320 },

  /* ══════════════════════════════════════
     Chart card
     ══════════════════════════════════════ */
  chartCard: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 10,
    ...Shadows.card,
  },
  chartHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    marginBottom: 8,
    flexWrap: 'wrap',
  },
  chartTitleWrap: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexShrink: 1,
    minWidth: 0,
  },
  chartTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  chartLiveDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.up,
    ...Platform.select({
      web: { boxShadow: '0 0 6px rgba(102,228,185,0.6)' as any },
    }),
  },
  chartTitleSub: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  tfRow: {
    flexDirection: 'row',
    gap: 2,
    flexWrap: 'wrap',
    backgroundColor: Colors.topBarBg,
    borderRadius: 8,
    padding: 3,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  tfBtn: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 6,
  },
  tfBtnActive: { backgroundColor: Colors.primaryDim },
  tfText: { color: Colors.textMuted, fontSize: 11, fontWeight: '600' },
  tfTextActive: { color: Colors.primary, fontWeight: '800' },
  chartBox: { height: 460, ...Platform.select({ web: { overflow: 'hidden' as any } }) },
  chartPlaceholder: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  placeholderText: { color: Colors.textMuted, fontSize: 13 },

  /* ══════════════════════════════════════
     Order book + trades
     ══════════════════════════════════════ */
  obCard: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 0,
    overflow: 'hidden',
    ...Shadows.card,
  },
  obTabRow: {
    flexDirection: 'row',
    gap: 6,
    paddingHorizontal: 10,
    paddingTop: 10,
    paddingBottom: 6,
  },
  obTabPill: {
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: Colors.topBarBg,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  obTabPillActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  obTabPillText: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  obTabPillTextActive: {
    color: Colors.primary,
  },
  obColHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  obColLabel: { fontSize: 10, color: Colors.textMuted, flex: 1, letterSpacing: 0.4, textTransform: 'uppercase' },
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
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 8,
    paddingHorizontal: 10,
    marginVertical: 3,
    marginHorizontal: 6,
    borderRadius: 8,
    backgroundColor: Colors.topBarBg,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  obCurrentPrice: { fontSize: 15, fontWeight: '800', fontVariant: ['tabular-nums'] },
  obSpreadBox: {
    alignItems: 'flex-end',
    gap: 1,
  },
  obSpreadLabel: {
    color: Colors.textMuted,
    fontSize: 9,
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  obSpreadValue: {
    color: Colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  obEmpty: { color: Colors.textMuted, fontSize: 12, textAlign: 'center' },

  /* ── Trades ── */
  tradeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 3,
    paddingHorizontal: 4,
    gap: 8,
  },
  tradeDot: {
    width: 5,
    height: 5,
    borderRadius: 2.5,
  },
  tradePrice: { fontSize: 11, flex: 1, fontVariant: ['tabular-nums'] },
  tradeQty: { fontSize: 11, color: Colors.textActive, flex: 1, textAlign: 'center', fontVariant: ['tabular-nums'] },
  tradeTime: { fontSize: 11, color: Colors.textMuted, flex: 1, textAlign: 'right' },

  /* ── Empty state (compact) ── */
  emptyState: {
    paddingVertical: 30,
    alignItems: 'center',
    gap: 6,
  },
  emptyStateIcon: {
    fontSize: 20,
    opacity: 0.35,
  },

  /* ══════════════════════════════════════
     Order panel
     ══════════════════════════════════════ */
  orderCard: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 12,
    ...Shadows.card,
  },

  /* Side segmented control (Buy / Sell) */
  sideSegment: {
    flexDirection: 'row',
    height: 44,
    backgroundColor: Colors.topBarBg,
    borderRadius: 10,
    padding: 3,
    gap: 4,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  sideSegBtn: {
    flex: 1,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sideSegBtnBuyActive: {
    backgroundColor: Colors.up,
  },
  sideSegBtnSellActive: {
    backgroundColor: Colors.down,
  },
  sideSegText: {
    fontSize: 13,
    fontWeight: '800',
    letterSpacing: 0.4,
  },
  sideSegTextBuyActive: { color: '#0a2e1f' },
  sideSegTextSellActive: { color: '#3e0a0a' },
  sideSegTextInactive: { color: Colors.textMuted },

  /* Order type pills (Limit / Market) */
  typePillRow: {
    flexDirection: 'row',
    gap: 6,
  },
  typePill: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: Colors.topBarBg,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  typePillActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  typePillText: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  typePillTextActive: {
    color: Colors.primary,
  },

  /* Available balance card */
  availCard: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
    padding: 10,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  availLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    letterSpacing: 0.5,
    textTransform: 'uppercase',
    marginBottom: 3,
  },
  availValueBig: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
  },
  availUnit: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '600',
  },
  transferBtn: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  transferBtnText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.3,
  },

  /* Inputs */
  inputGroup: { gap: 5 },
  inputGroupLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    letterSpacing: 0.5,
    textTransform: 'uppercase',
    fontWeight: '600',
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: Colors.topBarBg,
    borderRadius: 8,
    paddingHorizontal: 10,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  input: {
    flex: 1,
    paddingVertical: 10,
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
    ...Platform.select({ web: { outlineWidth: 0 } as any }),
  },
  inputUnit: { color: Colors.textMuted, fontSize: 11, fontWeight: '700' },

  marketPriceHint: {
    backgroundColor: Colors.topBarBg,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.border,
    borderStyle: 'dashed',
    paddingVertical: 10,
    paddingHorizontal: 10,
  },
  marketPriceText: { color: Colors.textMuted, fontSize: 12, fontStyle: 'italic' },

  /* Percentage chips */
  pctSliderWrap: { paddingVertical: 2 },
  pctChipRow: { flexDirection: 'row', gap: 6 },
  pctChip: {
    flex: 1,
    paddingVertical: 6,
    borderRadius: 6,
    backgroundColor: Colors.topBarBg,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
  },
  pctChipActive: { backgroundColor: Colors.primaryDim, borderColor: Colors.primaryBorder },
  pctChipText: { color: Colors.textMuted, fontSize: 11, fontWeight: '700' },
  pctChipTextActive: { color: Colors.primary, fontWeight: '800' },

  /* Estimate card (total / fee / receive) */
  estimateCard: {
    backgroundColor: Colors.topBarBg,
    borderRadius: 10,
    padding: 12,
    gap: 8,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  estimateRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  estimateRowEmph: {
    borderTopWidth: 1,
    borderTopColor: Colors.border,
    paddingTop: 8,
  },
  estimateLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '600',
  },
  estimateValue: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  estimateValueEmph: {
    fontSize: 14,
    fontWeight: '800',
    fontVariant: ['tabular-nums'],
  },

  /* Submit button */
  submitBtn: {
    paddingVertical: 13,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 2,
    ...Shadows.card,
  },
  submitBtnBuy: { backgroundColor: Colors.up },
  submitBtnSell: { backgroundColor: Colors.down },
  submitBtnText: {
    color: '#0a2e1f',
    fontSize: 14,
    fontWeight: '800',
    letterSpacing: 0.4,
  },

  /* ══════════════════════════════════════
     Bottom card (tabs + table)
     ══════════════════════════════════════ */
  bottomCard: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 12,
    ...Shadows.card,
  },
  bottomTabRow: {
    flexDirection: 'row',
    gap: 8,
    paddingHorizontal: 2,
    marginBottom: 10,
  },
  bottomTabPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 999,
    backgroundColor: Colors.topBarBg,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  bottomTabPillActive: {
    backgroundColor: Colors.primaryDim,
    borderColor: Colors.primaryBorder,
  },
  bottomTabPillText: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  bottomTabPillTextActive: {
    color: Colors.primary,
  },
  tabCountBadge: {
    minWidth: 20,
    height: 18,
    borderRadius: 9,
    paddingHorizontal: 5,
    backgroundColor: Colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
  },
  tabCountBadgeActive: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  tabCountBadgeText: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '800',
    lineHeight: 12,
  },
  tabCountBadgeTextActive: {
    color: Colors.textOnPrimary,
  },

  /* Table */
  tableHeader: {
    flexDirection: 'row',
    gap: 8,
    paddingVertical: 10,
    paddingLeft: 14,
    paddingRight: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    backgroundColor: Colors.topBarBg,
    borderTopLeftRadius: 8,
    borderTopRightRadius: 8,
  },
  thCell: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  tableRow: {
    flexDirection: 'row',
    gap: 8,
    paddingVertical: 14,
    paddingLeft: 14,
    paddingRight: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    alignItems: 'center',
    position: 'relative',
  },
  tdCell: { color: Colors.textActive, fontSize: 12, fontVariant: ['tabular-nums'] },

  /* Row: colored side accent stripe (absolute left) */
  rowAccent: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: 3,
    borderTopRightRadius: 2,
    borderBottomRightRadius: 2,
  },
  /* Row: symbol column (dot + bold symbol + side pill stacked) */
  rowSymbolCol: {
    flex: 1.7,
    gap: 6,
    justifyContent: 'center',
  },
  rowSymbolLine: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  rowSymbolText: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '800',
    letterSpacing: 0.3,
  },
  /* Row: stacked price/qty/amount column */
  rowStackedCol: {
    flex: 1.2,
    gap: 3,
    justifyContent: 'center',
  },
  rowStackedMain: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
  },
  rowStackedSub: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 0.3,
  },
  rowStackedTimeMain: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  rowStackedTimeSub: {
    color: Colors.textMuted,
    fontSize: 11,
    fontVariant: ['tabular-nums'],
  },
  /* Row: action/status column (right aligned) */
  rowActionCol: {
    flex: 1,
    alignItems: 'flex-end',
    justifyContent: 'center',
  },
  emptyText: { color: Colors.textMuted, fontSize: 12 },
  emptyStateFull: {
    paddingVertical: 48,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
  },
  emptyStateIconLg: {
    fontSize: 36,
    opacity: 0.35,
  },

  /* Row decorations */
  tableSymbolDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.primary,
  },
  sidePill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  sidePillText: {
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.3,
  },
  statusPill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  statusPillText: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.3,
  },

  rowCancelBtn: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderRadius: 6,
    backgroundColor: Colors.topBarBg,
  },
  rowCancelText: { color: Colors.textSecondary, fontSize: 11, fontWeight: '700' },

  /* Holdings */
  holdingsSummary: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
    paddingVertical: 10,
    paddingHorizontal: 10,
    marginBottom: 8,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  holdingsSummaryLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    letterSpacing: 0.5,
    textTransform: 'uppercase',
    marginBottom: 2,
  },
  holdingsSummaryValue: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
    fontVariant: ['tabular-nums'],
  },
  holdingsSummaryUnit: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
  },
  holdingsMeta: {
    alignItems: 'flex-end',
  },
  holdingsMetaLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '600',
  },
  holdingAssetBadge: {
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: Colors.primaryDim,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  holdingAssetBadgeText: {
    color: Colors.primary,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.3,
  },
  holdingAssetIcon: {
    marginRight: 2,
  },
  pnlPill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  pnlPillText: {
    fontSize: 11,
    fontWeight: '800',
    fontVariant: ['tabular-nums'],
  },

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
});
