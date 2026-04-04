import { useEffect, useCallback, useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  TextInput,
  StyleSheet,
  RefreshControl,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useMarketStore } from '../../services/store/marketStore';
import { marketWs } from '../../services/websocket/marketWs';
import type { MarketQuote } from '../../services/api/client';
import { Skeleton, SkeletonMarketItem } from '../../components/Skeleton';

export default function WatchlistScreen() {
  const { t } = useTranslation();
  const router = useRouter();

  const {
    quotes,
    watchlist,
    loadQuotes,
    loadCryptoQuotes,
    loadForexQuotes,
    addWatchlist,
    removeWatchlist,
    updateQuote,
    search,
    searchResults,
    searchLoading,
    clearSearch,
  } = useMarketStore();

  const [searchQuery, setSearchQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  // Classify and load watchlist quotes
  const loadWatchlistQuotes = useCallback(async () => {
    if (watchlist.length === 0) return;
    const crypto: string[] = [];
    const forex: string[] = [];
    const stocks: string[] = [];
    for (const s of watchlist) {
      if (s.includes('/')) {
        if (s.endsWith('/USD') && !['EUR/USD','GBP/USD','USD/JPY','AUD/USD','USD/CAD','USD/CHF','NZD/USD'].includes(s)) {
          crypto.push(s);
        } else {
          forex.push(s);
        }
      } else {
        stocks.push(s);
      }
    }
    const tasks: Promise<void>[] = [];
    if (crypto.length > 0) tasks.push(loadCryptoQuotes(crypto));
    if (forex.length > 0) tasks.push(loadForexQuotes(forex));
    if (stocks.length > 0) tasks.push(loadQuotes(stocks));
    await Promise.allSettled(tasks);
  }, [watchlist]);

  useEffect(() => {
    setLoading(true);
    loadWatchlistQuotes().finally(() => setLoading(false));
  }, []);

  // Subscribe to WS for watchlist symbols
  useEffect(() => {
    if (watchlist.length === 0) return;
    const handler = (data: Record<string, any>) => {
      if (data.type === 'quote' && data.symbol && watchlist.includes(data.symbol)) {
        updateQuote(data.symbol, {
          price: data.price,
          open: data.open,
          high: data.high,
          low: data.low,
          volume: data.volume,
          change: data.change,
          percent_change: data.percent_change,
          prev_close: data.prev_close,
        });
      }
    };
    marketWs.onMessage(handler);
    const subHandler = () => {};
    marketWs.subscribeMany(watchlist, subHandler);
    return () => {
      marketWs.offMessage(handler);
      for (const s of watchlist) {
        marketWs.unsubscribe(s, subHandler);
      }
    };
  }, [watchlist]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadWatchlistQuotes();
    setRefreshing(false);
  }, [loadWatchlistQuotes]);

  // Search
  const handleSearchChange = (text: string) => {
    setSearchQuery(text);
    if (text.length >= 1) {
      search(text);
    } else {
      clearSearch();
    }
  };

  const handleAddSymbol = (symbol: string) => {
    addWatchlist(symbol);
    setSearchQuery('');
    clearSearch();
    // Load quote for the newly added symbol
    if (symbol.includes('/')) {
      if (symbol.endsWith('/USD') && !['EUR/USD','GBP/USD','USD/JPY','AUD/USD','USD/CAD','USD/CHF','NZD/USD'].includes(symbol)) {
        loadCryptoQuotes([symbol]);
      } else {
        loadForexQuotes([symbol]);
      }
    } else {
      loadQuotes([symbol]);
    }
  };

  const watchlistItems = watchlist.map((s) => quotes[s]).filter(Boolean);

  // Skeleton loading
  if (loading && watchlistItems.length === 0) {
    return (
      <View style={styles.container}>
        <View style={styles.topBar}>
          <Text style={styles.pageTitle}>⭐ {t('market.watchlist')}</Text>
        </View>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16 }}>
          {[1, 2, 3, 4].map((i) => <SkeletonMarketItem key={i} />)}
        </ScrollView>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Top Bar */}
      <View style={styles.topBar}>
        <Text style={styles.pageTitle}>⭐ {t('market.watchlist')}</Text>
        <Text style={styles.countBadge}>{watchlist.length}</Text>
        <View style={{ flex: 1 }} />
      </View>

      {/* Search to add */}
      <View style={styles.searchArea}>
        <View style={styles.searchBox}>
          <Text style={styles.searchIcon}>🔍</Text>
          <TextInput
            style={styles.searchInput}
            placeholder={t('market.searchPairs')}
            placeholderTextColor={Colors.textMuted}
            value={searchQuery}
            onChangeText={handleSearchChange}
          />
          {searchQuery.length > 0 && (
            <TouchableOpacity onPress={() => { setSearchQuery(''); clearSearch(); }}>
              <Text style={styles.clearBtn}>✕</Text>
            </TouchableOpacity>
          )}
        </View>
      </View>

      {/* Search Results Dropdown */}
      {searchQuery.length >= 1 && (
        <View style={styles.searchResults}>
          {searchLoading ? (
            <View style={styles.searchLoading}>
              <Text style={styles.mutedText}>{t('common.loading')}</Text>
            </View>
          ) : searchResults.length === 0 ? (
            <View style={styles.searchLoading}>
              <Text style={styles.mutedText}>{t('common.noData')}</Text>
            </View>
          ) : (
            searchResults.slice(0, 10).map((item) => {
              const isWatched = watchlist.includes(item.symbol);
              return (
                <TouchableOpacity
                  key={item.symbol}
                  style={styles.searchRow}
                  onPress={() => !isWatched && handleAddSymbol(item.symbol)}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={styles.searchSymbol}>{item.symbol}</Text>
                    {item.name ? <Text style={styles.searchName}>{item.name}</Text> : null}
                  </View>
                  <Text style={{ color: isWatched ? Colors.primary : Colors.textMuted, fontSize: 18 }}>
                    {isWatched ? '★' : '☆'}
                  </Text>
                </TouchableOpacity>
              );
            })
          )}
        </View>
      )}

      {/* Watchlist Content */}
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={Colors.primary}
          />
        }
      >
        {watchlistItems.length === 0 && watchlist.length === 0 ? (
          <View style={styles.emptyState}>
            <Text style={styles.emptyIcon}>⭐</Text>
            <Text style={styles.emptyTitle}>{t('market.noWatchlist')}</Text>
            <Text style={styles.emptyHint}>
              {t('market.watchlistHint', { defaultValue: '搜索并添加您关注的交易对' })}
            </Text>
          </View>
        ) : (
          <>
            {/* Column Headers */}
            <View style={styles.colHeader}>
              <Text style={[styles.colText, { flex: 1 }]}>{t('market.pair')}</Text>
              <Text style={[styles.colText, { width: 100, textAlign: 'right' }]}>{t('market.lastPrice')}</Text>
              <Text style={[styles.colText, { width: 80, textAlign: 'right' }]}>{t('market.change')}</Text>
              <Text style={[styles.colText, { width: 40 }]} />
            </View>

            {/* Watchlist Items */}
            {watchlist.map((sym) => {
              const item = quotes[sym];
              if (!item) {
                return (
                  <View key={sym} style={styles.fullRow}>
                    <View style={styles.fullRowLeft}>
                      <Text style={styles.fullSymbol}>{sym}</Text>
                      <Text style={styles.loadingHint}>{t('common.loading')}</Text>
                    </View>
                    <View style={{ flex: 1 }} />
                    <TouchableOpacity
                      onPress={() => removeWatchlist(sym)}
                      hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
                    >
                      <Text style={{ fontSize: 16, color: Colors.primary }}>★</Text>
                    </TouchableOpacity>
                  </View>
                );
              }
              const pct = item.percent_change ?? 0;
              const isUp = pct >= 0;
              const color = isUp ? Colors.up : Colors.down;
              return (
                <TouchableOpacity
                  key={sym}
                  style={styles.fullRow}
                  activeOpacity={0.6}
                  onPress={() => router.push({ pathname: '/chart/[symbol]', params: { symbol: sym } })}
                >
                  <View style={styles.fullRowLeft}>
                    <Text style={styles.fullSymbol}>{item.symbol}</Text>
                    {item.name ? <Text style={styles.fullName} numberOfLines={1}>{item.name}</Text> : null}
                  </View>
                  <Text style={[styles.fullPrice, { color }]}>
                    {item.price != null && item.price > 0 ? formatPrice(item.price) : '--'}
                  </Text>
                  <View style={[styles.changeBadge, { backgroundColor: isUp ? Colors.upDim : Colors.downDim }]}>
                    <Text style={[styles.changeText, { color }]}>
                      {isUp ? '+' : ''}{pct.toFixed(2)}%
                    </Text>
                  </View>
                  <TouchableOpacity
                    style={styles.starBtn}
                    onPress={(e) => {
                      e.stopPropagation?.();
                      removeWatchlist(sym);
                    }}
                    hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
                  >
                    <Text style={{ fontSize: 16, color: Colors.primary }}>★</Text>
                  </TouchableOpacity>
                </TouchableOpacity>
              );
            })}
          </>
        )}
      </ScrollView>
    </View>
  );
}

function formatPrice(price: number): string {
  if (price >= 10000) return price.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (price >= 1) return price.toFixed(2);
  if (price >= 0.01) return price.toFixed(4);
  if (price >= 0.0001) return price.toFixed(6);
  return price.toFixed(8);
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  topBar: {
    height: Sizes.topBarHeight,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.topBarBg,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 20,
    gap: 8,
  },
  pageTitle: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
  },
  countBadge: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 10,
    overflow: 'hidden',
  },
  searchArea: {
    backgroundColor: Colors.topBarBg,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
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
  },
  searchIcon: { fontSize: 13, marginRight: 8 },
  searchInput: { flex: 1, color: Colors.textActive, fontSize: 14 },
  clearBtn: { color: Colors.textMuted, fontSize: 14, paddingLeft: 8 },
  searchResults: {
    backgroundColor: Colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    maxHeight: 300,
  },
  searchLoading: {
    padding: 16,
    alignItems: 'center',
  },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  searchSymbol: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  searchName: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
  },
  mutedText: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  scrollView: { flex: 1 },
  scrollContent: { padding: 16, paddingBottom: 40 },
  colHeader: {
    flexDirection: 'row',
    paddingVertical: 8,
    paddingHorizontal: 4,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    marginBottom: 4,
  },
  colText: { color: Colors.textMuted, fontSize: 11 },
  fullRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 4,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  fullRowLeft: { flex: 1 },
  fullSymbol: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  fullName: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
  },
  loadingHint: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
  },
  fullPrice: {
    width: 100,
    textAlign: 'right',
    fontSize: 15,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  changeBadge: {
    width: 80,
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderRadius: 4,
    alignItems: 'center',
    marginLeft: 8,
  },
  changeText: {
    fontSize: 13,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  starBtn: {
    marginLeft: 8,
    padding: 4,
  },
  emptyState: {
    paddingVertical: 80,
    alignItems: 'center',
    gap: 12,
  },
  emptyIcon: {
    fontSize: 48,
  },
  emptyTitle: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
  },
  emptyHint: {
    color: Colors.textMuted,
    fontSize: 14,
  },
});
