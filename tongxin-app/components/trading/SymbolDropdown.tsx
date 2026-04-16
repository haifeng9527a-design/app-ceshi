/**
 * SymbolDropdown — shared symbol switcher used by futures (trading.tsx) and spot (spot.tsx).
 *
 * Visual: side-sliding panel (width 380) with search + tabs + price/change rows.
 * Composition:
 *   - caller provides `tabs` and `symbolsByTab` (Record<tabKey, symbolStrings[]>)
 *   - caller optionally provides `getMeta(symbol)` to surface sub-label, custom
 *     display symbol, price precision, or a distinct quote-store lookup key.
 *
 * For spot, callers typically pre-filter `symbolsByTab` to only include the
 * categories they want (e.g. crypto + stocks, dropping forex + futures).
 */

import { memo, useCallback, useEffect, useMemo, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import AppIcon from '../ui/AppIcon';
import AssetSymbolIcon from '../ui/AssetSymbolIcon';
import { Colors } from '../../theme/colors';
import type { MarketQuote } from '../../services/api/client';
import { useMarketStore } from '../../services/store/marketStore';

export type SymbolMeta = {
  /** Optional sub-label shown below the symbol (e.g. company name for stocks). */
  subLabel?: string;
  /** Symbol string rendered in the row (defaults to `symbol`). */
  displaySymbol?: string;
  /** Key used to look up `quotes[...]` (defaults to `symbol`). */
  quoteSymbol?: string;
  /** Override price precision for this row. */
  pricePrecision?: number;
  /** Explicit icon category when row lives in synthetic tabs like watchlist. */
  category?: 'stock' | 'crypto';
};

export type SymbolTab = { key: string; label: string };

export type SymbolDropdownProps = {
  visible: boolean;
  selectedSymbol: string;
  tabs: SymbolTab[];
  /** Symbol lists keyed by tab. Caller filters to just the tabs they want. */
  symbolsByTab: Record<string, string[]>;
  /**
   * Optional quote snapshot. Kept for backward compatibility; rows now subscribe
   * to the market store directly so only symbols whose quote actually changed
   * re-render (prevents flicker from 50ms global flushes hitting 100+ rows).
   */
  quotes?: Record<string, MarketQuote>;
  /** Defaults to the first tab whose list contains `selectedSymbol`. */
  initialTab?: string;
  onSelect: (symbol: string) => void;
  onClose: () => void;
  getMeta?: (symbol: string) => SymbolMeta | undefined;
};

/* ── Defaults ─────────────────────────────────────────── */

function defaultFormatPrice(price: number, precision?: number): string {
  if (!price || price <= 0) return '--';
  if (precision != null && precision >= 0) return price.toFixed(precision);
  if (price >= 10000)
    return price.toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  if (price >= 1) return price.toFixed(2);
  if (price >= 0.01) return price.toFixed(4);
  if (price >= 0.0001) return price.toFixed(6);
  return price.toFixed(8);
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

/* ── Component ────────────────────────────────────────── */

/** Per-row subscriber: only rerenders when THIS symbol's quote changes.
 *  Zustand's `===` equality means unchanged symbols (the common case during a
 *  50ms batch flush) skip their render entirely. */
const QuoteRow = memo(function QuoteRow({
  sym,
  displaySymbol,
  lookupKey,
  subLabel,
  pricePrecision,
  category,
  isActive,
  onPress,
}: {
  sym: string;
  displaySymbol: string;
  lookupKey: string;
  subLabel?: string;
  pricePrecision?: number;
  category?: 'stock' | 'crypto';
  isActive: boolean;
  onPress: (sym: string) => void;
}) {
  const q = useMarketStore((s) => s.quotes[lookupKey]);
  const watchlist = useMarketStore((s) => s.watchlist);
  const addWatchlist = useMarketStore((s) => s.addWatchlist);
  const removeWatchlist = useMarketStore((s) => s.removeWatchlist);
  const pct = q?.percent_change;
  const isWatched = watchlist.includes(lookupKey);
  const toggleWatchlist = useCallback(() => {
    if (isWatched) removeWatchlist(lookupKey);
    else addWatchlist(lookupKey);
  }, [isWatched, removeWatchlist, addWatchlist, lookupKey]);
  return (
    <TouchableOpacity
      style={[styles.row, isActive && styles.rowActive]}
      onPress={() => onPress(sym)}
      activeOpacity={0.6}
    >
      <AssetSymbolIcon
        symbol={displaySymbol}
        category={category}
        size={28}
        style={styles.rowIcon}
      />
      <View style={styles.rowLeft}>
        <Text
          style={[styles.rowSymbol, isActive && { color: Colors.primary }]}
          numberOfLines={1}
        >
          {displaySymbol}
        </Text>
        {subLabel ? (
          <Text style={styles.rowSubLabel} numberOfLines={1}>
            {subLabel}
          </Text>
        ) : null}
      </View>
      <Text style={styles.rowPrice} numberOfLines={1}>
        {defaultFormatPrice(q?.price ?? 0, pricePrecision)}
      </Text>
      <Text style={[styles.rowChange, { color: changeColor(pct) }]}>
        {formatChange(pct)}
      </Text>
      <TouchableOpacity
        style={styles.starBtn}
        onPress={(e) => {
          e?.stopPropagation?.();
          toggleWatchlist();
        }}
        activeOpacity={0.7}
      >
        <AppIcon
          name="watchlist"
          size={15}
          color={isWatched ? Colors.primary : Colors.textMuted}
        />
      </TouchableOpacity>
    </TouchableOpacity>
  );
});

export default function SymbolDropdown({
  visible,
  selectedSymbol,
  tabs,
  symbolsByTab,
  initialTab,
  onSelect,
  onClose,
  getMeta,
}: SymbolDropdownProps) {
  const { t } = useTranslation();
  const watchlist = useMarketStore((s) => s.watchlist);

  // Auto-pick the tab that contains the currently selected symbol on open.
  const resolveTab = (): string => {
    if (initialTab && symbolsByTab[initialTab]) return initialTab;
    for (const tab of tabs) {
      if (symbolsByTab[tab.key]?.includes(selectedSymbol)) return tab.key;
    }
    return tabs[0]?.key ?? '';
  };

  const [activeTab, setActiveTab] = useState<string>(resolveTab);
  const [filter, setFilter] = useState('');

  const symbolLookupByWatchKey = useCallback(
    (watchKey: string): string | null => {
      for (const [, symbolList] of Object.entries(symbolsByTab)) {
        for (const sym of symbolList) {
          const meta = getMeta?.(sym);
          if ((meta?.quoteSymbol ?? sym) === watchKey) return sym;
        }
      }
      return null;
    },
    [symbolsByTab, getMeta],
  );

  const watchlistSymbols = useMemo(() => {
    const deduped: string[] = [];
    const seen = new Set<string>();
    for (const watchKey of watchlist) {
      const sym = symbolLookupByWatchKey(watchKey);
      if (sym && !seen.has(sym)) {
        seen.add(sym);
        deduped.push(sym);
      }
    }
    return deduped;
  }, [watchlist, symbolLookupByWatchKey]);

  const effectiveTabs = useMemo<SymbolTab[]>(() => {
    if (watchlistSymbols.length === 0) return tabs;
    return [{ key: 'watchlist', label: t('market.watchlist') }, ...tabs];
  }, [tabs, watchlistSymbols.length, t]);

  // Stable row-press handler so <QuoteRow memo> doesn't reset on every parent render.
  const handleRowPress = useCallback(
    (s: string) => {
      onSelect(s);
      onClose();
    },
    [onSelect, onClose],
  );

  // Reset tab + search each time the panel becomes visible.
  useEffect(() => {
    if (visible) {
      setActiveTab(resolveTab());
      setFilter('');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, selectedSymbol]);

  useEffect(() => {
    if (activeTab === 'watchlist' && watchlistSymbols.length === 0) {
      setActiveTab(resolveTab());
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeTab, watchlistSymbols.length]);

  if (!visible) return null;

  const list = activeTab === 'watchlist' ? watchlistSymbols : symbolsByTab[activeTab] ?? [];
  const filtered = filter
    ? list.filter((sym) => {
        const lower = filter.toLowerCase();
        if (sym.toLowerCase().includes(lower)) return true;
        const meta = getMeta?.(sym);
        return meta?.subLabel?.toLowerCase().includes(lower) ?? false;
      })
    : list;

  return (
    <View style={styles.overlay}>
      <TouchableOpacity style={styles.backdrop} onPress={onClose} activeOpacity={1} />
      <View style={styles.panel}>
        {/* Search */}
        <View style={styles.searchRow}>
          <AppIcon name="search" size={15} color={Colors.textMuted} />
          <TextInput
            style={styles.searchInput}
            placeholder={t('trading.searchPairs')}
            placeholderTextColor={Colors.textMuted}
            value={filter}
            onChangeText={setFilter}
            autoFocus
          />
          <TouchableOpacity onPress={onClose}>
            <Text style={styles.closeBtn}>✕</Text>
          </TouchableOpacity>
        </View>

        {/* Tabs */}
        <View style={styles.tabRow}>
          {effectiveTabs.map((tab) => (
            <TouchableOpacity
              key={tab.key}
              style={[styles.tab, activeTab === tab.key && styles.tabActive]}
              onPress={() => {
                setActiveTab(tab.key);
                setFilter('');
              }}
              activeOpacity={0.7}
            >
              <Text
                style={[styles.tabText, activeTab === tab.key && styles.tabTextActive]}
              >
                {tab.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* List header */}
        <View style={styles.listHeader}>
          <Text style={styles.headerText}>{t('trading.pair')}</Text>
          <Text style={[styles.headerText, { textAlign: 'right' }]}>
            {t('trading.price')}
          </Text>
          <Text style={[styles.headerText, { textAlign: 'right' }]}>
            {t('trading.changePercent')}
          </Text>
        </View>

        {/* List */}
        <ScrollView style={styles.list} keyboardShouldPersistTaps="handled">
          {filtered.length === 0 ? (
            <View style={styles.empty}>
              <Text style={styles.emptyText}>{t('trading.noMatch')}</Text>
            </View>
          ) : (
            filtered.map((sym) => {
              const meta = getMeta?.(sym);
              return (
                <QuoteRow
                  key={sym}
                  sym={sym}
                  displaySymbol={meta?.displaySymbol ?? sym}
                  lookupKey={meta?.quoteSymbol ?? sym}
                  subLabel={meta?.subLabel}
                  pricePrecision={meta?.pricePrecision}
                  category={
                    activeTab === 'stocks'
                      ? 'stock'
                      : activeTab === 'crypto'
                        ? 'crypto'
                        : meta?.category
                  }
                  isActive={selectedSymbol === sym}
                  onPress={handleRowPress}
                />
              );
            })
          )}
        </ScrollView>
      </View>
    </View>
  );
}

/* ── Styles ───────────────────────────────────────────── */

const styles = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 100,
  },
  backdrop: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  panel: {
    position: 'absolute',
    top: 0,
    left: 0,
    bottom: 0,
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
  rowIcon: {
    marginRight: 10,
  },
  rowLeft: {
    flex: 1,
    minWidth: 0,
  },
  rowSymbol: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  rowSubLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    marginTop: 2,
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
  starBtn: {
    marginLeft: 10,
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.02)',
  },
  empty: {
    paddingVertical: 40,
    alignItems: 'center',
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 13,
  },
});
