/**
 * 现货交易独立页（Spot Standalone Page）
 * --------------------------------------------------
 * 入口：左侧 Sidebar「现货」菜单。与合约页 /trading 完全隔离。
 *
 * 页面结构：
 *   ┌──────────────────────────────────────────────┐
 *   │ Symbol Dropdown（crypto + stocks）           │
 *   ├───────────────────────────┬──────────────────┤
 *   │ K 线图（TradingViewChart）│ 下单面板          │
 *   │                           │  • 市价 / 限价   │
 *   │                           │  • 买 / 卖       │
 *   │                           │  • 数量 / 金额   │
 *   ├───────────────────────────┴──────────────────┤
 *   │ Tabs: [当前订单] [历史订单] [持仓]            │
 *   └──────────────────────────────────────────────┘
 *
 * 符号格式映射：
 *   spotApi 返回的 symbol 为 "BTC/USDT" / "AAPL/USD"
 *   marketStore 存的是  "BTC/USD" / "AAPL"
 *   toMarketSymbol() 负责 display → market 的转换，用于 K 线 / 实时价
 */

import { useEffect, useMemo, useState, useCallback } from 'react';
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
import { Colors } from '../../theme/colors';

/* ════════════════════════════════════════════
   Helpers
   ════════════════════════════════════════════ */

const toMarketSymbol = (spotSymbol: string, category: SpotCategory): string => {
  if (category === 'crypto') {
    // BTC/USDT → BTC/USD
    return spotSymbol.replace('/USDT', '/USD');
  }
  // stocks: AAPL/USD → AAPL
  return spotSymbol.split('/')[0];
};

const formatPrice = (n: number | null | undefined, precision = 2): string => {
  if (n == null || !isFinite(n)) return '--';
  return n.toLocaleString(undefined, {
    minimumFractionDigits: precision,
    maximumFractionDigits: precision,
  });
};

/* ════════════════════════════════════════════
   Main component
   ════════════════════════════════════════════ */

export default function SpotPage() {
  const { t } = useTranslation();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 1024;
  const user = useAuthStore((s) => s.user);

  /* ── Symbol list ── */
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

  /* ── Market data (K-line + real-time price) ── */
  const klines = useMarketStore((s) => s.klines);
  const klinesLoading = useMarketStore((s) => s.klinesLoading);
  const loadKlines = useMarketStore((s) => s.loadKlines);
  const quotes = useMarketStore((s) => s.quotes);
  const loadCryptoQuotes = useMarketStore((s) => s.loadCryptoQuotes);
  const loadQuotes = useMarketStore((s) => s.loadQuotes);

  const [timeframe, setTimeframe] = useState('1h');

  const currentQuote = quotes[marketSymbol];
  const currentPrice = currentQuote?.price ?? 0;
  const klineData = klines;

  /* ── Order form state ── */
  const [side, setSide] = useState<'buy' | 'sell'>('buy');
  const [orderType, setOrderType] = useState<'market' | 'limit'>('market');
  // base = 按数量下单（market/limit 都支持）；quote = 按金额（仅 market buy 支持）
  const [qtyMode, setQtyMode] = useState<'base' | 'quote'>('base');
  const [qtyInput, setQtyInput] = useState('');
  const [priceInput, setPriceInput] = useState('');
  const [placing, setPlacing] = useState(false);

  /* ── Orders + account ── */
  const [pendingOrders, setPendingOrders] = useState<SpotOrder[]>([]);
  const [historyOrders, setHistoryOrders] = useState<SpotOrder[]>([]);
  const [account, setAccount] = useState<SpotAccountInfo | null>(null);
  const [activeTab, setActiveTab] = useState<'pending' | 'history' | 'holdings'>('pending');

  /* ─────────────────────────────────────────
     Load symbol list (crypto + stocks)
     ───────────────────────────────────────── */
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

  /* ─────────────────────────────────────────
     Load klines + quote when symbol/timeframe changes
     ───────────────────────────────────────── */
  useEffect(() => {
    if (!marketSymbol) return;
    loadKlines(marketSymbol, timeframe);
    if (selectedMeta?.category === 'crypto') {
      loadCryptoQuotes([marketSymbol]);
    } else {
      loadQuotes([marketSymbol]);
    }
  }, [marketSymbol, timeframe, selectedMeta?.category, loadKlines, loadCryptoQuotes, loadQuotes]);

  /* ─────────────────────────────────────────
     Poll orders + account (5s / 15s)
     ───────────────────────────────────────── */
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

  useEffect(() => {
    if (!user) {
      setPendingOrders([]);
      setHistoryOrders([]);
      setAccount(null);
      return;
    }
    refreshPending();
    refreshHistory();
    refreshAccount();

    const pendingInterval = setInterval(refreshPending, 5000);
    const historyInterval = setInterval(refreshHistory, 10000);
    const accountInterval = setInterval(refreshAccount, 15000);

    return () => {
      clearInterval(pendingInterval);
      clearInterval(historyInterval);
      clearInterval(accountInterval);
    };
  }, [user, refreshPending, refreshHistory, refreshAccount]);

  /* ─────────────────────────────────────────
     Submit order
     ───────────────────────────────────────── */
  const handlePlaceOrder = async () => {
    if (!user) {
      Alert.alert(t('auth.notLoggedIn'));
      return;
    }
    const qtyNum = parseFloat(qtyInput);
    if (!qtyInput || !isFinite(qtyNum) || qtyNum <= 0) {
      Alert.alert(t('trading.qtyMustBePositive') || '数量必须大于 0');
      return;
    }

    const req: any = {
      symbol: selectedSymbol,
      side,
      order_type: orderType,
    };

    // 按金额仅允许 market buy
    if (qtyMode === 'quote' && orderType === 'market' && side === 'buy') {
      req.quote_qty = qtyNum;
    } else {
      req.qty = qtyNum;
    }

    if (orderType === 'limit') {
      const p = parseFloat(priceInput);
      if (!priceInput || !isFinite(p) || p <= 0) {
        Alert.alert(t('trading.priceMustBePositive') || '价格必须大于 0');
        return;
      }
      req.price = p;
    }

    setPlacing(true);
    try {
      await spotApi.placeOrder(req);
      Alert.alert(t('trading.spotOrderPlaced'));
      setQtyInput('');
      setPriceInput('');
      refreshPending();
      refreshAccount();
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || t('trading.spotInsufficientBalance');
      Alert.alert(msg);
    } finally {
      setPlacing(false);
    }
  };

  const handleCancel = async (orderId: string) => {
    try {
      await spotApi.cancelOrder(orderId);
      refreshPending();
      refreshAccount();
    } catch (e: any) {
      Alert.alert(e?.response?.data?.error || e?.message || t('common.error'));
    }
  };

  /* ═════════════════════════════════════════
     Render sub-sections
     ═════════════════════════════════════════ */

  /* ── Symbol dropdown ── */
  const renderSymbolDropdown = () => (
    <View style={styles.symbolRow}>
      <TouchableOpacity
        style={styles.symbolChip}
        activeOpacity={0.7}
        onPress={() => setShowSymbolDropdown(!showSymbolDropdown)}
      >
        <Text style={styles.symbolText}>{selectedSymbol}</Text>
        <Text style={styles.chevron}>{showSymbolDropdown ? '▲' : '▼'}</Text>
      </TouchableOpacity>
      <View style={styles.priceBox}>
        <Text style={styles.priceValue}>{formatPrice(currentPrice, selectedMeta?.price_precision ?? 2)}</Text>
        {currentQuote && (
          <Text
            style={[
              styles.priceChange,
              { color: (currentQuote.percent_change ?? 0) >= 0 ? Colors.up : Colors.down },
            ]}
          >
            {(currentQuote.percent_change ?? 0) >= 0 ? '+' : ''}
            {(currentQuote.percent_change ?? 0).toFixed(2)}%
          </Text>
        )}
      </View>

      {showSymbolDropdown && (
        <View style={styles.dropdownPanel}>
          <ScrollView style={{ maxHeight: 320 }}>
            {(['crypto', 'stocks'] as SpotCategory[]).map((cat) => {
              const items = symbols.filter((s) => s.category === cat);
              if (items.length === 0) return null;
              return (
                <View key={cat}>
                  <Text style={styles.dropdownHeader}>
                    {cat === 'crypto' ? t('trading.crypto') || '加密货币' : t('trading.stock') || '股票'}
                  </Text>
                  {items.map((s) => (
                    <TouchableOpacity
                      key={s.symbol}
                      style={[
                        styles.dropdownItem,
                        s.symbol === selectedSymbol && styles.dropdownItemActive,
                      ]}
                      onPress={() => {
                        setSelectedSymbol(s.symbol);
                        setShowSymbolDropdown(false);
                      }}
                      activeOpacity={0.7}
                    >
                      <Text style={styles.dropdownSymbol}>{s.symbol}</Text>
                      <Text style={styles.dropdownName}>{s.display_name}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              );
            })}
          </ScrollView>
        </View>
      )}
    </View>
  );

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
            klines={klineData}
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

  /* ── Order panel ── */
  const renderOrderPanel = () => {
    const baseAsset = selectedMeta?.base_asset || '';
    const quoteAsset = selectedMeta?.quote_asset || 'USDT';
    const usdtHolding = account?.holdings.find((h) => h.asset === quoteAsset);
    const baseHolding = account?.holdings.find((h) => h.asset === baseAsset);
    const isQuoteMode = qtyMode === 'quote' && orderType === 'market' && side === 'buy';

    return (
      <View style={styles.orderCard}>
        {/* Buy/Sell tabs */}
        <View style={styles.sideRow}>
          <TouchableOpacity
            style={[styles.sideBtn, side === 'buy' && styles.sideBtnBuyActive]}
            onPress={() => setSide('buy')}
            activeOpacity={0.7}
          >
            <Text style={[styles.sideText, side === 'buy' && styles.sideTextActive]}>
              {t('trading.spotBuy')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.sideBtn, side === 'sell' && styles.sideBtnSellActive]}
            onPress={() => setSide('sell')}
            activeOpacity={0.7}
          >
            <Text style={[styles.sideText, side === 'sell' && styles.sideTextActive]}>
              {t('trading.spotSell')}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Order type tabs */}
        <View style={styles.tabRow}>
          <TouchableOpacity onPress={() => setOrderType('market')} activeOpacity={0.7}>
            <Text style={[styles.tabText, orderType === 'market' && styles.tabTextActive]}>
              {t('trading.marketOrder') || '市价'}
            </Text>
            {orderType === 'market' && <View style={styles.tabUnderline} />}
          </TouchableOpacity>
          <TouchableOpacity onPress={() => setOrderType('limit')} activeOpacity={0.7}>
            <Text style={[styles.tabText, orderType === 'limit' && styles.tabTextActive]}>
              {t('trading.limit') || '限价'}
            </Text>
            {orderType === 'limit' && <View style={styles.tabUnderline} />}
          </TouchableOpacity>
        </View>

        {/* Available */}
        <View style={styles.availRow}>
          <Text style={styles.availLabel}>{t('trading.available') || '可用'}</Text>
          <Text style={styles.availValue}>
            {side === 'buy'
              ? `${(usdtHolding?.available ?? 0).toFixed(2)} ${quoteAsset}`
              : `${(baseHolding?.available ?? 0).toFixed(6)} ${baseAsset}`}
          </Text>
        </View>

        {/* Limit price */}
        {orderType === 'limit' && (
          <View style={styles.inputRow}>
            <Text style={styles.inputLabel}>{t('trading.price') || '价格'}</Text>
            <TextInput
              style={styles.input}
              value={priceInput}
              onChangeText={setPriceInput}
              placeholder={currentPrice ? currentPrice.toString() : '0.00'}
              keyboardType="decimal-pad"
              placeholderTextColor={Colors.textMuted}
            />
            <Text style={styles.inputUnit}>{quoteAsset}</Text>
          </View>
        )}

        {/* Quantity */}
        <View style={styles.inputRow}>
          <Text style={styles.inputLabel}>
            {isQuoteMode ? t('trading.amount') || '金额' : t('trading.quantity') || '数量'}
          </Text>
          <TextInput
            style={styles.input}
            value={qtyInput}
            onChangeText={setQtyInput}
            placeholder="0.00"
            keyboardType="decimal-pad"
            placeholderTextColor={Colors.textMuted}
          />
          <Text style={styles.inputUnit}>{isQuoteMode ? quoteAsset : baseAsset}</Text>
        </View>

        {/* Market buy: toggle base/quote mode */}
        {orderType === 'market' && side === 'buy' && (
          <View style={styles.modeRow}>
            <TouchableOpacity
              onPress={() => {
                setQtyMode('base');
                setQtyInput('');
              }}
              activeOpacity={0.7}
            >
              <Text style={[styles.modeText, qtyMode === 'base' && styles.modeTextActive]}>
                {t('trading.byQty') || '按数量'}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              onPress={() => {
                setQtyMode('quote');
                setQtyInput('');
              }}
              activeOpacity={0.7}
            >
              <Text style={[styles.modeText, qtyMode === 'quote' && styles.modeTextActive]}>
                {t('trading.byAmount') || '按金额'}
              </Text>
            </TouchableOpacity>
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
              ? '...'
              : `${side === 'buy' ? t('trading.spotBuy') : t('trading.spotSell')} ${baseAsset}`}
          </Text>
        </TouchableOpacity>

        {/* Fee rate (optional) */}
        {selectedMeta && (
          <Text style={styles.feeHint}>
            {t('trading.minQty') || '最小数量'}: {selectedMeta.min_qty} {baseAsset}
          </Text>
        )}
      </View>
    );
  };

  /* ── Orders / history / holdings tab ── */
  const renderBottomTabs = () => (
    <View style={styles.bottomCard}>
      <View style={styles.bottomTabRow}>
        {(['pending', 'history', 'holdings'] as const).map((tab) => (
          <TouchableOpacity
            key={tab}
            style={styles.bottomTab}
            onPress={() => setActiveTab(tab)}
            activeOpacity={0.7}
          >
            <Text style={[styles.bottomTabText, tab === activeTab && styles.bottomTabTextActive]}>
              {tab === 'pending'
                ? t('trading.currentOrders') || '当前订单'
                : tab === 'history'
                ? t('trading.orderHistory') || '历史订单'
                : t('trading.holdings') || '持仓'}
            </Text>
            {tab === activeTab && <View style={styles.bottomTabUnderline} />}
          </TouchableOpacity>
        ))}
      </View>

      <View style={styles.bottomContent}>
        {activeTab === 'pending' && renderPendingList()}
        {activeTab === 'history' && renderHistoryList()}
        {activeTab === 'holdings' && renderHoldingsList()}
      </View>
    </View>
  );

  const renderPendingList = () => {
    if (pendingOrders.length === 0) {
      return <Text style={styles.emptyText}>{t('common.noData')}</Text>;
    }
    return pendingOrders.map((o) => (
      <View key={o.id} style={styles.listRow}>
        <View style={{ flex: 1 }}>
          <Text style={styles.listSymbol}>
            {o.symbol}{' '}
            <Text style={{ color: o.side === 'buy' ? Colors.up : Colors.down }}>
              {o.side === 'buy' ? t('trading.spotBuy') : t('trading.spotSell')}
            </Text>
          </Text>
          <Text style={styles.listMeta}>
            {o.order_type === 'market' ? t('trading.marketOrder') : t('trading.limit')}{' '}
            · {o.qty} @ {o.price ?? '-'} · {new Date(o.created_at).toLocaleString()}
          </Text>
        </View>
        <TouchableOpacity style={styles.cancelBtn} onPress={() => handleCancel(o.id)} activeOpacity={0.7}>
          <Text style={styles.cancelBtnText}>{t('common.cancel')}</Text>
        </TouchableOpacity>
      </View>
    ));
  };

  const renderHistoryList = () => {
    if (historyOrders.length === 0) {
      return <Text style={styles.emptyText}>{t('common.noData')}</Text>;
    }
    return historyOrders.map((o) => (
      <View key={o.id} style={styles.listRow}>
        <View style={{ flex: 1 }}>
          <Text style={styles.listSymbol}>
            {o.symbol}{' '}
            <Text style={{ color: o.side === 'buy' ? Colors.up : Colors.down }}>
              {o.side === 'buy' ? t('trading.spotBuy') : t('trading.spotSell')}
            </Text>
          </Text>
          <Text style={styles.listMeta}>
            {o.qty} {o.base_asset} @ {o.filled_price ?? o.price ?? '-'} · {o.status} ·{' '}
            {new Date(o.created_at).toLocaleString()}
          </Text>
        </View>
        <Text style={styles.listValue}>
          {o.quote_qty.toFixed(2)} {o.quote_asset}
        </Text>
      </View>
    ));
  };

  const renderHoldingsList = () => {
    if (!account || account.holdings.length === 0) {
      return <Text style={styles.emptyText}>{t('common.noData')}</Text>;
    }
    return (
      <>
        <View style={styles.holdingsHeader}>
          <Text style={styles.holdingsTotal}>
            {t('trading.totalValue') || '总估值'}: {account.total_valuation_usdt.toFixed(2)} USDT
          </Text>
        </View>
        {account.holdings.map((h) => (
          <View key={h.asset} style={styles.listRow}>
            <View style={{ flex: 1 }}>
              <Text style={styles.listSymbol}>{h.asset}</Text>
              <Text style={styles.listMeta}>
                {h.available.toFixed(6)} + {h.frozen.toFixed(6)} ({t('trading.frozenLabel') || '冻结'})
              </Text>
            </View>
            <Text style={styles.listValue}>{h.valuation_usdt.toFixed(2)} USDT</Text>
          </View>
        ))}
      </>
    );
  };

  /* ═════════════════════════════════════════
     Layout
     ═════════════════════════════════════════ */

  if (isDesktop) {
    return (
      <ScrollView style={styles.container} contentContainerStyle={{ padding: 16, gap: 12 }}>
        {renderSymbolDropdown()}
        <View style={{ flexDirection: 'row', gap: 12 }}>
          <View style={{ flex: 2 }}>{renderChart()}</View>
          <View style={{ flex: 1, minWidth: 320 }}>{renderOrderPanel()}</View>
        </View>
        {renderBottomTabs()}
      </ScrollView>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={{ padding: 12, gap: 12 }}>
      {renderSymbolDropdown()}
      {renderChart()}
      {renderOrderPanel()}
      {renderBottomTabs()}
    </ScrollView>
  );
}

/* ════════════════════════════════════════════
   Styles
   ════════════════════════════════════════════ */

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: Colors.background },

  /* Symbol row */
  symbolRow: { flexDirection: 'row', alignItems: 'center', gap: 12, position: 'relative', zIndex: 10 },
  symbolChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 8,
    backgroundColor: Colors.surface, borderRadius: 8,
    borderWidth: 1, borderColor: Colors.border,
  },
  symbolText: { color: Colors.textActive, fontSize: 16, fontWeight: '700' },
  chevron: { color: Colors.textMuted, fontSize: 10 },
  priceBox: { flexDirection: 'row', alignItems: 'baseline', gap: 8 },
  priceValue: { color: Colors.textActive, fontSize: 20, fontWeight: '700' },
  priceChange: { fontSize: 13, fontWeight: '600' },

  dropdownPanel: {
    position: 'absolute', top: 44, left: 0, width: 260,
    backgroundColor: Colors.surface, borderRadius: 8,
    borderWidth: 1, borderColor: Colors.border,
    ...Platform.select({ web: { boxShadow: '0 4px 20px rgba(0,0,0,0.4)' } as any }),
  },
  dropdownHeader: {
    paddingHorizontal: 12, paddingVertical: 6,
    color: Colors.textMuted, fontSize: 11, fontWeight: '700', letterSpacing: 1,
    backgroundColor: Colors.topBarBg,
  },
  dropdownItem: { paddingHorizontal: 12, paddingVertical: 10, flexDirection: 'row', justifyContent: 'space-between' },
  dropdownItemActive: { backgroundColor: Colors.primaryDim },
  dropdownSymbol: { color: Colors.textActive, fontSize: 14, fontWeight: '600' },
  dropdownName: { color: Colors.textMuted, fontSize: 12 },

  /* Chart */
  chartCard: {
    backgroundColor: Colors.surface, borderRadius: 10,
    borderWidth: 1, borderColor: Colors.border, padding: 8,
  },
  tfRow: { flexDirection: 'row', gap: 4, marginBottom: 8 },
  tfBtn: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 4 },
  tfBtnActive: { backgroundColor: Colors.primaryDim },
  tfText: { color: Colors.textMuted, fontSize: 12, fontWeight: '500' },
  tfTextActive: { color: Colors.primary, fontWeight: '700' },
  chartBox: { height: 420, ...Platform.select({ web: { overflow: 'hidden' as any } }) },
  chartPlaceholder: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  placeholderText: { color: Colors.textMuted, fontSize: 13 },

  /* Order card */
  orderCard: {
    backgroundColor: Colors.surface, borderRadius: 10,
    borderWidth: 1, borderColor: Colors.border, padding: 14, gap: 10,
  },
  sideRow: { flexDirection: 'row', gap: 6 },
  sideBtn: {
    flex: 1, paddingVertical: 8, borderRadius: 6,
    backgroundColor: Colors.topBarBg, alignItems: 'center',
    borderWidth: 1, borderColor: Colors.border,
  },
  sideBtnBuyActive: { backgroundColor: Colors.up, borderColor: Colors.up },
  sideBtnSellActive: { backgroundColor: Colors.down, borderColor: Colors.down },
  sideText: { color: Colors.textMuted, fontSize: 13, fontWeight: '700' },
  sideTextActive: { color: '#fff' },

  tabRow: { flexDirection: 'row', gap: 20, paddingVertical: 4 },
  tabText: { color: Colors.textMuted, fontSize: 13, fontWeight: '600' },
  tabTextActive: { color: Colors.textActive, fontWeight: '700' },
  tabUnderline: { height: 2, backgroundColor: Colors.primary, marginTop: 2 },

  availRow: { flexDirection: 'row', justifyContent: 'space-between' },
  availLabel: { color: Colors.textMuted, fontSize: 12 },
  availValue: { color: Colors.textActive, fontSize: 12, fontWeight: '600' },

  inputRow: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: Colors.topBarBg, borderRadius: 6, paddingHorizontal: 10,
    borderWidth: 1, borderColor: Colors.border,
  },
  inputLabel: { color: Colors.textMuted, fontSize: 12, minWidth: 36 },
  input: {
    flex: 1, paddingVertical: 10,
    color: Colors.textActive, fontSize: 14, fontWeight: '600',
    ...Platform.select({ web: { outlineWidth: 0 } as any }),
  },
  inputUnit: { color: Colors.textMuted, fontSize: 12, fontWeight: '600' },

  modeRow: { flexDirection: 'row', gap: 16 },
  modeText: { color: Colors.textMuted, fontSize: 12 },
  modeTextActive: { color: Colors.primary, fontWeight: '700' },

  submitBtn: { paddingVertical: 12, borderRadius: 6, alignItems: 'center', marginTop: 4 },
  submitBtnBuy: { backgroundColor: Colors.up },
  submitBtnSell: { backgroundColor: Colors.down },
  submitBtnText: { color: '#fff', fontSize: 14, fontWeight: '700' },

  feeHint: { color: Colors.textMuted, fontSize: 11, textAlign: 'center' },

  /* Bottom tabs */
  bottomCard: {
    backgroundColor: Colors.surface, borderRadius: 10,
    borderWidth: 1, borderColor: Colors.border, padding: 12,
  },
  bottomTabRow: { flexDirection: 'row', gap: 20, marginBottom: 8 },
  bottomTab: { paddingVertical: 6 },
  bottomTabText: { color: Colors.textMuted, fontSize: 13, fontWeight: '600' },
  bottomTabTextActive: { color: Colors.textActive, fontWeight: '700' },
  bottomTabUnderline: { height: 2, backgroundColor: Colors.primary, marginTop: 4 },

  bottomContent: { minHeight: 120 },
  emptyText: { color: Colors.textMuted, textAlign: 'center', fontSize: 13, paddingVertical: 20 },

  holdingsHeader: { paddingVertical: 6, paddingHorizontal: 4 },
  holdingsTotal: { color: Colors.textActive, fontSize: 14, fontWeight: '700' },

  listRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: Colors.border,
  },
  listSymbol: { color: Colors.textActive, fontSize: 13, fontWeight: '700' },
  listMeta: { color: Colors.textMuted, fontSize: 11, marginTop: 2 },
  listValue: { color: Colors.textActive, fontSize: 13, fontWeight: '600' },

  cancelBtn: {
    paddingHorizontal: 10, paddingVertical: 6,
    borderRadius: 4, borderWidth: 1, borderColor: Colors.border,
  },
  cancelBtnText: { color: Colors.textMuted, fontSize: 12 },
});
