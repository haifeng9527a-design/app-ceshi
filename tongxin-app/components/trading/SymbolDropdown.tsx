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

import { useEffect, useState } from 'react';
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
import { Colors } from '../../theme/colors';
import type { MarketQuote } from '../../services/api/client';

export type SymbolMeta = {
  /** Optional sub-label shown below the symbol (e.g. company name for stocks). */
  subLabel?: string;
  /** Symbol string rendered in the row (defaults to `symbol`). */
  displaySymbol?: string;
  /** Key used to look up `quotes[...]` (defaults to `symbol`). */
  quoteSymbol?: string;
  /** Override price precision for this row. */
  pricePrecision?: number;
};

export type SymbolTab = { key: string; label: string };

export type SymbolDropdownProps = {
  visible: boolean;
  selectedSymbol: string;
  tabs: SymbolTab[];
  /** Symbol lists keyed by tab. Caller filters to just the tabs they want. */
  symbolsByTab: Record<string, string[]>;
  quotes: Record<string, MarketQuote>;
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

export default function SymbolDropdown({
  visible,
  selectedSymbol,
  tabs,
  symbolsByTab,
  quotes,
  initialTab,
  onSelect,
  onClose,
  getMeta,
}: SymbolDropdownProps) {
  const { t } = useTranslation();

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

  // Reset tab + search each time the panel becomes visible.
  useEffect(() => {
    if (visible) {
      setActiveTab(resolveTab());
      setFilter('');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, selectedSymbol]);

  if (!visible) return null;

  const list = symbolsByTab[activeTab] ?? [];
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
          {tabs.map((tab) => (
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
              const displaySymbol = meta?.displaySymbol ?? sym;
              const lookupKey = meta?.quoteSymbol ?? sym;
              const q = quotes[lookupKey];
              const isActive = selectedSymbol === sym;
              const pct = q?.percent_change;
              return (
                <TouchableOpacity
                  key={sym}
                  style={[styles.row, isActive && styles.rowActive]}
                  onPress={() => {
                    onSelect(sym);
                    onClose();
                  }}
                  activeOpacity={0.6}
                >
                  <View style={styles.rowLeft}>
                    <Text
                      style={[
                        styles.rowSymbol,
                        isActive && { color: Colors.primary },
                      ]}
                      numberOfLines={1}
                    >
                      {displaySymbol}
                    </Text>
                    {meta?.subLabel ? (
                      <Text style={styles.rowSubLabel} numberOfLines={1}>
                        {meta.subLabel}
                      </Text>
                    ) : null}
                  </View>
                  <Text style={styles.rowPrice} numberOfLines={1}>
                    {defaultFormatPrice(q?.price ?? 0, meta?.pricePrecision)}
                  </Text>
                  <Text style={[styles.rowChange, { color: changeColor(pct) }]}>
                    {formatChange(pct)}
                  </Text>
                </TouchableOpacity>
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
  empty: {
    paddingVertical: 40,
    alignItems: 'center',
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 13,
  },
});
