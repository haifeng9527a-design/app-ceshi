import { useEffect, useState, useCallback, useRef, useMemo, memo } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  TextInput,
  StyleSheet,
  useWindowDimensions,
  ActivityIndicator,
  RefreshControl,
  FlatList,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../../theme/colors';
import { useMarketStore } from '../../../services/store/marketStore';
import { marketWs } from '../../../services/websocket/marketWs';
import type { MarketQuote } from '../../../services/api/client';
import IndexCard from '../../../components/market/IndexCard';
import SentimentCard from '../../../components/market/SentimentCard';
import NewsCard from '../../../components/market/NewsCard';
import AssetListCard from '../../../components/market/AssetListCard';
import SearchDropdown from '../../../components/market/SearchDropdown';
import { Skeleton, SkeletonMarketItem, SkeletonCard } from '../../../components/Skeleton';
import AppIcon, { type AppIconName } from '../../../components/ui/AppIcon';

// Symbols synced with trading page
const DEFAULT_CRYPTO = [
  'BTC/USD','ETH/USD','SOL/USD','BNB/USD','XRP/USD','DOGE/USD','ADA/USD','AVAX/USD',
  'DOT/USD','MATIC/USD','LINK/USD','UNI/USD','SHIB/USD','LTC/USD','TRX/USD',
  'ATOM/USD','NEAR/USD','APT/USD','ARB/USD','OP/USD','FIL/USD','ICP/USD',
  'AAVE/USD','GRT/USD','MKR/USD','IMX/USD','INJ/USD','RUNE/USD','FTM/USD',
  'SUI/USD','SEI/USD','TIA/USD','JUP/USD','WIF/USD','BONK/USD','PEPE/USD',
];
const DEFAULT_FOREX = [
  'EUR/USD','GBP/USD','USD/JPY','AUD/USD','USD/CAD','USD/CHF','NZD/USD',
  'EUR/GBP','EUR/JPY','GBP/JPY','AUD/JPY','EUR/AUD','EUR/CAD',
];
const DEFAULT_STOCKS = [
  'AAPL','MSFT','GOOGL','AMZN','NVDA','META','TSLA','BRK.B','JPM','V',
  'UNH','JNJ','XOM','WMT','MA','PG','HD','CVX','MRK','ABBV',
  'LLY','PEP','KO','COST','AVGO','TMO','MCD','CSCO','ACN','ABT',
  'COIN','SQ','SHOP','PLTR','PYPL',
];
const DEFAULT_FUTURES = [
  'ES','NQ','YM','RTY','CL','GC','SI','HG','NG','ZB',
];
const DEFAULT_INDICES = ['DJI', 'SPX', 'IXIC', 'VIX'];

// Sub-tabs
type ViewMode = 'overview' | 'crypto' | 'forex' | 'stocks' | 'futures' | 'gainers';

export default function MarketScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { tab } = useLocalSearchParams<{ tab?: string }>();
  const { width: screenWidth } = useWindowDimensions();
  const isDesktop = screenWidth >= 768;
  const searchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Fine-grained selectors to avoid full-store re-renders
  const quotes = useMarketStore((s) => s.quotes);
  const indices = useMarketStore((s) => s.indices);
  const news = useMarketStore((s) => s.news);
  const newsLoading = useMarketStore((s) => s.newsLoading);
  const loadQuotes = useMarketStore((s) => s.loadQuotes);
  const loadCryptoQuotes = useMarketStore((s) => s.loadCryptoQuotes);
  const loadForexQuotes = useMarketStore((s) => s.loadForexQuotes);
  const loadFuturesQuotes = useMarketStore((s) => s.loadFuturesQuotes);
  const loadNews = useMarketStore((s) => s.loadNews);
  const loadIndices = useMarketStore((s) => s.loadIndices);
  const wsConnected = useMarketStore((s) => s.wsConnected);
  const updateQuote = useMarketStore((s) => s.updateQuote);
  const updateIndex = useMarketStore((s) => s.updateIndex);
  const setWsConnected = useMarketStore((s) => s.setWsConnected);
  const search = useMarketStore((s) => s.search);
  const searchResults = useMarketStore((s) => s.searchResults);
  const searchLoading = useMarketStore((s) => s.searchLoading);
  const clearSearch = useMarketStore((s) => s.clearSearch);

  const [viewMode, setViewMode] = useState<ViewMode>('overview');
  const [searchQuery, setSearchQuery] = useState('');
  const [searchFocused, setSearchFocused] = useState(false);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  // Switch to tab from URL param (e.g. sidebar Watchlist click)
  useEffect(() => {
    if (tab && ['overview', 'crypto', 'forex', 'stocks', 'futures', 'gainers'].includes(tab)) {
      setViewMode(tab as ViewMode);
    }
  }, [tab]);

  // Load all data
  const loadAllData = useCallback(async () => {
    setLoading(true);
    try {
      await Promise.allSettled([
        loadIndices(),
        loadCryptoQuotes(DEFAULT_CRYPTO),
        loadForexQuotes(DEFAULT_FOREX),
        loadQuotes(DEFAULT_STOCKS),
        loadFuturesQuotes(DEFAULT_FUTURES),
        loadNews(),
      ]);
    } catch (e) {
      console.error('Load error:', e);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    loadAllData();
  }, []);

  // Pull to refresh
  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadAllData();
    setRefreshing(false);
  }, [loadAllData]);

  // Search with debounce
  const handleSearchChange = useCallback((text: string) => {
    setSearchQuery(text);
    if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
    if (text.length >= 1) {
      searchTimerRef.current = setTimeout(() => {
        search(text);
      }, 400);
    } else {
      clearSearch();
    }
  }, []);

  // Listen for WS quote updates
  useEffect(() => {
    const handler = (data: Record<string, any>) => {
      if (data.type === 'connected') {
        setWsConnected(true);
        return;
      }
      if (data.type === 'quote' && data.symbol) {
        const payload = {
          price: data.price,
          open: data.open,
          high: data.high,
          low: data.low,
          volume: data.volume,
          change: data.change,
          percent_change: data.percent_change,
          prev_close: data.prev_close,
        };
        updateQuote(data.symbol, payload);
        // Also update indices if it's an index symbol
        if (DEFAULT_INDICES.includes(data.symbol)) {
          updateIndex(data.symbol, payload);
        }
      }
    };
    marketWs.onMessage(handler);
    return () => marketWs.offMessage(handler);
  }, []);

  // Subscribe to WS for all symbols
  useEffect(() => {
    const allSymbols = [...DEFAULT_CRYPTO, ...DEFAULT_FOREX, ...DEFAULT_STOCKS, ...DEFAULT_FUTURES, ...DEFAULT_INDICES];
    if (allSymbols.length > 0) {
      const handler = () => {};
      marketWs.subscribeMany(allSymbols, handler);
      return () => {
        for (const s of allSymbols) {
          marketWs.unsubscribe(s, handler);
        }
      };
    }
  }, []);

  // Build data arrays
  const cryptoItems = DEFAULT_CRYPTO.map((s) => quotes[s]).filter(Boolean);
  const forexItems = DEFAULT_FOREX.map((s) => quotes[s]).filter(Boolean);
  const stockItems = DEFAULT_STOCKS.map((s) => quotes[s]).filter(Boolean);
  const futuresItems = DEFAULT_FUTURES.map((s) => quotes[s]).filter(Boolean);
  // Calculate gainers/losers from all loaded quotes (real-time, no extra API needed)
  const { computedGainers, computedLosers } = useMemo(() => {
    const allItems = [...cryptoItems, ...forexItems, ...stockItems, ...futuresItems]
      .filter((q) => q.price != null && q.price > 0);
    // Sort descending by percent_change
    const sorted = [...allItems].sort((a, b) => (b.percent_change ?? 0) - (a.percent_change ?? 0));
    // Gainers: top 10 with positive change
    const g = sorted.filter((q) => (q.percent_change ?? 0) > 0).slice(0, 10);
    // Losers: bottom 10 with negative change (sort ascending = most negative first)
    const l = sorted.filter((q) => (q.percent_change ?? 0) < 0).reverse().slice(0, 10);
    return { computedGainers: g, computedLosers: l };
  }, [cryptoItems, forexItems, stockItems, futuresItems]);

  // Build index card data from store indices (BTC / DOW JONES / S&P 500 / NASDAQ / VIX)
  const formatIndexPrice = (p: number) =>
    p >= 10000 ? p.toLocaleString('en-US', { maximumFractionDigits: 0 })
    : p >= 100 ? p.toFixed(2)
    : p.toFixed(2);

  const btcQuote = quotes['BTC/USD'];
  const btcCard = btcQuote && btcQuote.price
    ? { name: 'BITCOIN', symbol: 'BTC/USD', price: formatIndexPrice(btcQuote.price), change: btcQuote.change ?? 0, changePct: btcQuote.percent_change ?? 0 }
    : { name: 'BITCOIN', symbol: 'BTC/USD', price: '--', change: 0, changePct: 0 };

  const indexData = [
    btcCard,
    ...(indices.length > 0
      ? indices.map((idx) => ({
          name: idx.name,
          symbol: idx.symbol,
          price: formatIndexPrice(idx.price),
          change: idx.change ?? 0,
          changePct: idx.percent_change ?? 0,
        }))
      : [
          { name: 'DOW JONES', symbol: 'DJI', price: '--', change: 0, changePct: 0 },
          { name: 'S&P 500', symbol: 'SPX', price: '--', change: 0, changePct: 0 },
          { name: 'NASDAQ', symbol: 'IXIC', price: '--', change: 0, changePct: 0 },
          { name: 'VIX VOLATILITY', symbol: 'VIX', price: '--', change: 0, changePct: 0 },
        ]),
  ];

  const SUB_TABS: { key: ViewMode; label: string }[] = [
    { key: 'overview', label: t('market.overview_tab') },
    { key: 'crypto', label: t('market.crypto') },
    { key: 'stocks', label: t('market.stocks') },
    { key: 'forex', label: t('market.forex') },
    { key: 'futures', label: t('market.futures', { defaultValue: '期货' }) },
    { key: 'gainers', label: t('market.gainersLosers') },
  ];

  // ─── Skeleton Loading State ─────────────────────────────────
  if (loading && cryptoItems.length === 0) {
    return (
      <View style={styles.container}>
        <View style={styles.topBar}>
          <View style={styles.searchBox}>
            <Skeleton width="100%" height={36} borderRadius={8} />
          </View>
        </View>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}>
          {/* Index cards skeleton */}
          <View style={{ flexDirection: 'row', paddingHorizontal: 12, gap: 8, marginTop: 12 }}>
            {[1, 2, 3, 4].map(i => (
              <View key={i} style={{ flex: 1, backgroundColor: '#1a1a1a', borderRadius: 8, padding: 12 }}>
                <Skeleton width={50} height={12} />
                <Skeleton width={70} height={18} style={{ marginTop: 8 }} />
                <Skeleton width={40} height={10} style={{ marginTop: 4 }} />
              </View>
            ))}
          </View>
          {/* Tab skeleton */}
          <View style={{ flexDirection: 'row', paddingHorizontal: 16, gap: 16, marginTop: 16, marginBottom: 8 }}>
            {[1, 2, 3, 4, 5].map(i => <Skeleton key={i} width={50} height={14} />)}
          </View>
          {/* List skeleton */}
          {[1, 2, 3, 4, 5, 6, 7, 8].map(i => <SkeletonMarketItem key={i} />)}
        </ScrollView>
      </View>
    );
  }

  // ─── Render ────────────────────────────────────────
  return (
    <View style={styles.container}>
      {/* ── Top Bar ── */}
      <View style={styles.topBar}>
        <View style={styles.searchBox}>
          <AppIcon name="search" size={14} color={Colors.textMuted} />
          <TextInput
            style={styles.searchInput}
            placeholder={t('market.searchPairs')}
            placeholderTextColor={Colors.textMuted}
            value={searchQuery}
            onChangeText={handleSearchChange}
            onFocus={() => setSearchFocused(true)}
            onBlur={() => setTimeout(() => setSearchFocused(false), 200)}
          />
          {searchQuery.length > 0 && (
            <TouchableOpacity onPress={() => { setSearchQuery(''); clearSearch(); }}>
              <Text style={styles.clearBtn}>✕</Text>
            </TouchableOpacity>
          )}
        </View>
        <View style={{ flex: 1 }} />
        <View style={styles.rightSection}>
          <View style={styles.statusBadge}>
            <View style={[styles.statusDot, { backgroundColor: wsConnected ? Colors.online : Colors.offline }]} />
            <Text style={styles.statusText}>
              {wsConnected ? t('market.wsConnected') : t('market.wsDisconnected')}
            </Text>
          </View>
          <TouchableOpacity style={styles.iconBtn}>
            <AppIcon name="bell" size={16} color={Colors.textSecondary} />
          </TouchableOpacity>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>S</Text>
          </View>
        </View>
      </View>

      {/* ── Search Dropdown ── */}
      {searchFocused && searchQuery.length >= 1 && (
        <SearchDropdown onSelect={() => { setSearchQuery(''); clearSearch(); setSearchFocused(false); }} />
      )}

      {/* ── Sub-tabs ── */}
      <View style={styles.subTabBar}>
        {SUB_TABS.map((tab) => (
          <TouchableOpacity
            key={tab.key}
            onPress={() => setViewMode(tab.key)}
            style={[styles.subTab, viewMode === tab.key && styles.subTabActive]}
          >
            <Text style={[styles.subTabLabel, viewMode === tab.key && styles.subTabLabelActive]}>
              {tab.label}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* ── Content ── */}
      {viewMode === 'crypto' ? (
        renderCategoryFlatList(cryptoItems, t('market.crypto'), 'bitcoin', true)
      ) : viewMode === 'stocks' ? (
        renderCategoryFlatList(stockItems, t('market.stocks'), 'market', true)
      ) : viewMode === 'forex' ? (
        renderCategoryFlatList(forexItems, t('market.forex'), 'forex', true)
      ) : viewMode === 'futures' ? (
        renderCategoryFlatList(futuresItems, t('market.futures', { defaultValue: '期货' }), 'futures', true)
      ) : (
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={onRefresh}
              tintColor={Colors.primary}
              colors={[Colors.primary]}
            />
          }
        >
          {viewMode === 'overview' && renderOverview()}
          {viewMode === 'gainers' && renderGainersLosers()}
        </ScrollView>
      )}
    </View>
  );

  // ─── Sub-renderers ─────────────────────────────────

  function renderOverview() {
    return (
      <>
        {/* Page Header */}
        <View style={styles.pageHeader}>
          <View>
            <Text style={styles.pageTitle}>{t('market.title')}</Text>
            <Text style={styles.pageSubtitle}>{t('market.overview')}</Text>
          </View>
          <View style={styles.networkBadge}>
            <View style={[styles.networkDot, { backgroundColor: wsConnected ? Colors.online : Colors.offline }]} />
            <Text style={styles.networkText}>
              {wsConnected ? t('market.networkOnline') : t('market.networkOffline')}
            </Text>
          </View>
        </View>

        {/* Index Cards */}
        <View style={[styles.indicesGrid, isDesktop && styles.indicesGridDesktop]}>
          {indexData.map((idx) => (
            <IndexCard
              key={idx.symbol}
              name={idx.name}
              symbol={idx.symbol}
              price={idx.price}
              change={idx.change}
              changePct={idx.changePct}
            />
          ))}
        </View>

        {/* Bento: Sentiment + News */}
        <View style={[styles.bentoRow, isDesktop && styles.bentoRowDesktop]}>
          <SentimentCard score={78} />
          <NewsCard items={news} loading={newsLoading} />
        </View>

        {/* Asset Lists */}
        <View style={[styles.assetGrid, isDesktop && styles.assetGridDesktop]}>
          <AssetListCard
            title={t('market.forex')}
            subtitle={t('marketCard.globalMajors')}
            icon={<AppIcon name="forex" size={18} color={Colors.primary} />}
            items={forexItems.slice(0, 4)}
            showWatchlistToggle
            onViewAll={() => setViewMode('forex')}
          />
          <AssetListCard
            title={t('market.stocks')}
            subtitle={t('marketCard.activeNyse')}
            icon={<AppIcon name="market" size={18} color={Colors.primary} />}
            items={stockItems.slice(0, 4)}
            showWatchlistToggle
            onViewAll={() => setViewMode('stocks')}
          />
          <AssetListCard
            title={t('market.crypto')}
            subtitle={t('marketCard.liquidityPool')}
            icon={<AppIcon name="bitcoin" size={18} color={Colors.primary} />}
            items={cryptoItems.slice(0, 4)}
            showWatchlistToggle
            onViewAll={() => setViewMode('crypto')}
          />
          <AssetListCard
            title={t('market.futures', { defaultValue: '期货' })}
            subtitle={t('marketCard.futuresDesk')}
            icon={<AppIcon name="futures" size={18} color={Colors.primary} />}
            items={futuresItems.slice(0, 4)}
            showWatchlistToggle
            onViewAll={() => setViewMode('futures')}
          />
        </View>
      </>
    );
  }

  function renderCategoryHeader(items: MarketQuote[], title: string, icon: AppIconName, showStar: boolean) {
    return (
      <>
        <View style={styles.categoryHeader}>
          <TouchableOpacity onPress={() => setViewMode('overview')} style={styles.backBtn}>
            <View style={styles.backTextWrap}>
              <AppIcon name="back" size={16} color={Colors.textMuted} />
              <Text style={styles.backText}>{t('market.title')}</Text>
            </View>
          </TouchableOpacity>
          <View style={styles.categoryTitleWrap}>
            <AppIcon name={icon} size={18} color={Colors.primary} />
            <Text style={styles.categoryTitle}>{title}</Text>
          </View>
          <Text style={styles.categoryCount}>{items.length} {t('market.pair')}</Text>
        </View>
        {/* Column headers */}
        <View style={styles.colHeader}>
          <Text style={[styles.colText, { flex: 1 }]}>{t('market.pair')}</Text>
          <Text style={[styles.colText, { width: 100, textAlign: 'right' }]}>{t('market.lastPrice')}</Text>
          <Text style={[styles.colText, { width: 80, textAlign: 'right' }]}>{t('market.change')}</Text>
          {showStar && <Text style={[styles.colText, { width: 30 }]} />}
        </View>
      </>
    );
  }

  function renderCategoryFlatList(items: MarketQuote[], title: string, icon: AppIconName, showStar: boolean) {
    return (
      <FlatList
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={Colors.primary}
            colors={[Colors.primary]}
          />
        }
        data={items}
        keyExtractor={(item) => item.symbol}
        renderItem={({ item }) => <FullListRow item={item} showStar={showStar} />}
        ListHeaderComponent={renderCategoryHeader(items, title, icon, showStar)}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>{t('common.noData')}</Text>
          </View>
        }
        initialNumToRender={15}
        windowSize={5}
        maxToRenderPerBatch={10}
        removeClippedSubviews
      />
    );
  }

  function renderGainersLosers() {
    return (
      <>
        <View style={styles.categoryHeader}>
          <TouchableOpacity onPress={() => setViewMode('overview')} style={styles.backBtn}>
            <View style={styles.backTextWrap}>
              <AppIcon name="back" size={16} color={Colors.textMuted} />
              <Text style={styles.backText}>{t('market.title')}</Text>
            </View>
          </TouchableOpacity>
          <View style={styles.categoryTitleWrap}>
            <AppIcon name="flame" size={18} color={Colors.primary} />
            <Text style={styles.categoryTitle}>{t('market.gainersLosers')}</Text>
          </View>
        </View>

        <View style={[styles.glGrid, isDesktop && styles.glGridDesktop]}>
          {/* Gainers */}
          <View style={styles.glCard}>
            <View style={styles.glHeader}>
              <View style={styles.glTitleWrap}>
                <AppIcon name="trend-up" size={16} color={Colors.up} />
                <Text style={[styles.glTitle, { color: Colors.up }]}>{t('market.topGainers')}</Text>
              </View>
            </View>
            {computedGainers.length === 0 ? (
              <Text style={styles.emptyText}>{t('common.noData')}</Text>
            ) : (
              computedGainers.map((item, i) => (
                <TouchableOpacity
                  key={item.symbol}
                  style={styles.glRow}
                  onPress={() => router.push({ pathname: '/(tabs)/trading', params: { symbol: item.symbol } })}
                >
                  <Text style={styles.glRank}>#{i + 1}</Text>
                  <Text style={styles.glSymbol}>{item.symbol}</Text>
                  {item.name ? <Text style={styles.glName}>{item.name}</Text> : null}
                  <View style={{ flex: 1 }} />
                  <Text style={[styles.glPrice, { color: Colors.up }]}>
                    {formatPrice(item.price ?? 0)}
                  </Text>
                  <View style={[styles.glBadge, { backgroundColor: Colors.upDim }]}>
                    <Text style={[styles.glPct, { color: Colors.up }]}>
                      +{(item.percent_change ?? 0).toFixed(2)}%
                    </Text>
                  </View>
                </TouchableOpacity>
              ))
            )}
          </View>

          {/* Losers */}
          <View style={styles.glCard}>
            <View style={styles.glHeader}>
              <View style={styles.glTitleWrap}>
                <AppIcon name="trend-down" size={16} color={Colors.down} />
                <Text style={[styles.glTitle, { color: Colors.down }]}>{t('market.topLosers')}</Text>
              </View>
            </View>
            {computedLosers.length === 0 ? (
              <Text style={styles.emptyText}>{t('common.noData')}</Text>
            ) : (
              computedLosers.map((item, i) => (
                <TouchableOpacity
                  key={item.symbol}
                  style={styles.glRow}
                  onPress={() => router.push({ pathname: '/(tabs)/trading', params: { symbol: item.symbol } })}
                >
                  <Text style={styles.glRank}>#{i + 1}</Text>
                  <Text style={styles.glSymbol}>{item.symbol}</Text>
                  {item.name ? <Text style={styles.glName}>{item.name}</Text> : null}
                  <View style={{ flex: 1 }} />
                  <Text style={[styles.glPrice, { color: Colors.down }]}>
                    {formatPrice(item.price ?? 0)}
                  </Text>
                  <View style={[styles.glBadge, { backgroundColor: Colors.downDim }]}>
                    <Text style={[styles.glPct, { color: Colors.down }]}>
                      {(item.percent_change ?? 0).toFixed(2)}%
                    </Text>
                  </View>
                </TouchableOpacity>
              ))
            )}
          </View>
        </View>
      </>
    );
  }
}

// ─── Full list row (used in category views) ──────────

const FullListRow = memo(function FullListRow({ item, showStar }: { item: MarketQuote; showStar?: boolean }) {
  const router = useRouter();
  const addWatchlist = useMarketStore((s) => s.addWatchlist);
  const removeWatchlist = useMarketStore((s) => s.removeWatchlist);
  const isWatched = useMarketStore((s) => s.watchlist.includes(item.symbol));
  const pct = item.percent_change ?? 0;
  const isUp = pct >= 0;
  const color = isUp ? Colors.up : Colors.down;

  return (
    <TouchableOpacity
      style={styles.fullRow}
      activeOpacity={0.6}
      onPress={() => router.push({ pathname: '/(tabs)/trading', params: { symbol: item.symbol } })}
    >
      <View style={styles.fullRowLeft}>
        <Text style={styles.fullSymbol}>{item.symbol}</Text>
        {item.name ? <Text style={styles.fullName} numberOfLines={1}>{item.name}</Text> : null}
      </View>
      <Text style={[styles.fullPrice, { color }]}>
        {item.price != null && item.price !== 0 ? formatPrice(item.price) : '--'}
      </Text>
      <View style={[styles.fullChangeBadge, { backgroundColor: isUp ? Colors.upDim : Colors.downDim }]}>
        <Text style={[styles.fullChangeText, { color }]}>
          {isUp ? '+' : ''}{pct.toFixed(2)}%
        </Text>
      </View>
      {showStar && (
        <TouchableOpacity
          style={styles.fullStar}
          onPress={() => isWatched ? removeWatchlist(item.symbol) : addWatchlist(item.symbol)}
          hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
        >
          <AppIcon name="watchlist" size={16} color={isWatched ? Colors.primary : Colors.textMuted} />
        </TouchableOpacity>
      )}
    </TouchableOpacity>
  );
});

function formatPrice(price: number): string {
  if (price >= 10000) return price.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (price >= 1) return price.toFixed(2);
  if (price >= 0.01) return price.toFixed(4);
  if (price >= 0.0001) return price.toFixed(6);
  return price.toFixed(8);
}

// ─── Styles ──────────────────────────────────────────

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  scrollView: { flex: 1 },
  scrollContent: { padding: 20, paddingBottom: 40 },

  // Loading
  loadingWrap: { flex: 1, justifyContent: 'center', alignItems: 'center', gap: 16 },
  loadingText: { color: Colors.textMuted, fontSize: 14 },

  // ── Top Bar ──
  topBar: {
    height: Sizes.topBarHeight,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.topBarBg,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 20,
    gap: 16,
    zIndex: 50,
  },
  searchBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 12,
    height: 40,
    minWidth: 240,
    maxWidth: 360,
  },
  searchInput: { flex: 1, color: Colors.textActive, fontSize: 14 },
  clearBtn: { color: Colors.textMuted, fontSize: 14, paddingLeft: 8 },
  rightSection: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  statusBadge: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: Colors.surface, borderRadius: 20,
    paddingHorizontal: 10, paddingVertical: 5,
    borderWidth: 1, borderColor: Colors.border,
  },
  statusDot: { width: 6, height: 6, borderRadius: 3, marginRight: 6 },
  statusText: { color: Colors.textSecondary, fontSize: 11, fontWeight: '500' },
  iconBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: Colors.surface, borderWidth: 1, borderColor: Colors.border,
    justifyContent: 'center', alignItems: 'center',
  },
  avatar: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: Colors.primaryDim, borderWidth: 1, borderColor: Colors.primaryBorder,
    justifyContent: 'center', alignItems: 'center',
  },
  avatarText: { color: Colors.primary, fontSize: 14, fontWeight: '700' },

  // ── Sub-tabs ──
  subTabBar: {
    flexDirection: 'row',
    backgroundColor: Colors.topBarBg,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 16,
  },
  subTab: {
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  subTabActive: {
    borderBottomWidth: 2,
    borderBottomColor: Colors.primary,
  },
  subTabLabel: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '500',
  },
  subTabLabelActive: {
    color: Colors.primary,
    fontWeight: '700',
  },

  // ── Page Header ──
  pageHeader: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start',
    marginBottom: 24,
  },
  pageTitle: { color: Colors.textActive, fontSize: 28, fontWeight: '800', letterSpacing: -0.5 },
  pageSubtitle: { color: Colors.textMuted, fontSize: 14, marginTop: 4 },
  networkBadge: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: Colors.surface, borderRadius: 20,
    paddingHorizontal: 12, paddingVertical: 6,
    borderWidth: 1, borderColor: Colors.border,
  },
  networkDot: { width: 6, height: 6, borderRadius: 3, marginRight: 6 },
  networkText: { color: Colors.textSecondary, fontSize: 12, fontWeight: '500' },

  // ── Indices Grid ──
  indicesGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, marginBottom: 20 },
  indicesGridDesktop: { flexWrap: 'nowrap' },

  // ── Bento ──
  bentoRow: { gap: 12, marginBottom: 20 },
  bentoRowDesktop: { flexDirection: 'row' },

  // ── Asset Grid ──
  assetGrid: { gap: 12 },
  assetGridDesktop: { flexDirection: 'row' },

  // ── Category View ──
  categoryHeader: { marginBottom: 16 },
  backBtn: { marginBottom: 8 },
  backTextWrap: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  backText: { color: Colors.primary, fontSize: 13, fontWeight: '600' },
  categoryTitleWrap: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  categoryTitle: { color: Colors.textActive, fontSize: 24, fontWeight: '800' },
  categoryCount: { color: Colors.textMuted, fontSize: 12, marginTop: 4 },

  colHeader: {
    flexDirection: 'row', paddingVertical: 8, paddingHorizontal: 4,
    borderBottomWidth: 1, borderBottomColor: Colors.border, marginBottom: 4,
  },
  colText: { color: Colors.textMuted, fontSize: 11 },

  // ── Full List Row ──
  fullRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 14, paddingHorizontal: 4,
    borderBottomWidth: 1, borderBottomColor: Colors.border,
  },
  fullRowLeft: { flex: 1 },
  fullSymbol: { color: Colors.textActive, fontSize: 15, fontWeight: '600', fontFamily: 'monospace' },
  fullName: { color: Colors.textMuted, fontSize: 11, marginTop: 2 },
  fullPrice: { width: 100, textAlign: 'right', fontSize: 15, fontWeight: '600', fontFamily: 'monospace' },
  fullChangeBadge: {
    width: 80, paddingVertical: 4, paddingHorizontal: 8,
    borderRadius: 4, alignItems: 'center', marginLeft: 8,
  },
  fullChangeText: { fontSize: 13, fontWeight: '600', fontFamily: 'monospace' },
  fullStar: { marginLeft: 8, padding: 4 },

  // ── Empty ──
  emptyState: { paddingVertical: 60, alignItems: 'center', gap: 8 },
  emptyText: { color: Colors.textMuted, fontSize: 14 },
  emptyHint: { color: Colors.textMuted, fontSize: 12 },

  // ── Gainers/Losers ──
  glGrid: { gap: 16 },
  glGridDesktop: { flexDirection: 'row' },
  glCard: {
    flex: 1,
    backgroundColor: Colors.surface, borderRadius: Sizes.borderRadius,
    borderWidth: 1, borderColor: Colors.border, padding: 16,
    ...Shadows.card,
  },
  glHeader: { marginBottom: 12, paddingBottom: 8, borderBottomWidth: 1, borderBottomColor: Colors.border },
  glTitleWrap: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  glTitle: { fontSize: 16, fontWeight: '700' },
  glRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: Colors.border,
  },
  glRank: { color: Colors.textMuted, fontSize: 12, fontWeight: '700', width: 28 },
  glSymbol: { color: Colors.textActive, fontSize: 14, fontWeight: '600', fontFamily: 'monospace' },
  glName: { color: Colors.textMuted, fontSize: 11, marginLeft: 8, maxWidth: 120 },
  glPrice: { fontSize: 14, fontWeight: '600', fontFamily: 'monospace', marginRight: 8 },
  glBadge: { paddingHorizontal: 8, paddingVertical: 3, borderRadius: 12 },
  glPct: { fontSize: 12, fontWeight: '700', fontFamily: 'monospace' },
});
