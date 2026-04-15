import { View, Text, TouchableOpacity, StyleSheet, Animated } from 'react-native';
import type { ReactNode } from 'react';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useMarketStore } from '../../services/store/marketStore';
import { usePriceFlash } from '../../hooks/usePriceFlash';
import type { MarketQuote } from '../../services/api/client';
import AppIcon from '../ui/AppIcon';

interface AssetListCardProps {
  title: string;
  subtitle?: string;
  icon: ReactNode;
  items: MarketQuote[];
  showViewAll?: boolean;
  onViewAll?: () => void;
  showWatchlistToggle?: boolean;
}

const AVATAR_COLORS: Record<string, string> = {
  BTC: '#F7931A', ETH: '#627EEA', SOL: '#9945FF', XRP: '#23292F',
  BNB: '#F0B90B', DOGE: '#C2A633', EUR: '#003399', GBP: '#CF142B',
  USD: '#3C7843', JPY: '#BC002D', AUD: '#00008B', AAPL: '#A2AAAD',
  GOOGL: '#4285F4', MSFT: '#00A4EF', TSLA: '#CC0000', AMZN: '#FF9900',
  NVDA: '#76B900', META: '#0081FB',
};

function getAvatarColor(symbol: string): string {
  const base = symbol.split('/')[0].replace('.', '');
  return AVATAR_COLORS[base] || Colors.primaryDim;
}

function getAvatarLetter(symbol: string): string {
  return symbol.split('/')[0].charAt(0).toUpperCase();
}

function formatPrice(price: number): string {
  if (price >= 10000) return price.toLocaleString('en-US', { maximumFractionDigits: 0 });
  if (price >= 100) return price.toFixed(2);
  if (price >= 1) return price.toFixed(4);
  return price.toFixed(6);
}

function AssetRow({ item, showWatchlistToggle }: { item: MarketQuote; showWatchlistToggle?: boolean }) {
  const router = useRouter();
  const { addWatchlist, removeWatchlist, watchlist } = useMarketStore();
  const isWatched = watchlist.includes(item.symbol);
  const pct = item.percent_change ?? 0;
  const isUp = pct >= 0;
  const color = isUp ? Colors.up : Colors.down;
  const bgColor = getAvatarColor(item.symbol);
  const flashBg = usePriceFlash(item.price);

  return (
    <Animated.View style={{ backgroundColor: flashBg, borderRadius: 8, marginHorizontal: -4, paddingHorizontal: 4 }}>
    <TouchableOpacity
      style={styles.row}
      activeOpacity={0.6}
      onPress={() =>
        router.push({
          pathname: '/(tabs)/trading',
          params: { symbol: item.symbol },
        })
      }
    >
      {/* Avatar */}
      <View style={[styles.avatar, { backgroundColor: bgColor + '20', borderColor: bgColor + '40' }]}>
        <Text style={[styles.avatarText, { color: bgColor }]}>
          {getAvatarLetter(item.symbol)}
        </Text>
      </View>

      {/* Symbol & Name */}
      <View style={styles.info}>
        <Text style={styles.symbol}>{item.symbol}</Text>
        {item.name ? (
          <Text style={styles.name} numberOfLines={1}>{item.name}</Text>
        ) : null}
      </View>

      {/* Price & Change */}
      <View style={styles.priceArea}>
        <Text style={[styles.price, { color }]}>
          {item.price != null && item.price !== 0 ? formatPrice(item.price) : '--'}
        </Text>
        <View style={[styles.changeBadge, { backgroundColor: isUp ? Colors.upDim : Colors.downDim }]}>
          <Text style={[styles.changeText, { color }]}>
            {isUp ? '+' : ''}{pct.toFixed(2)}%
          </Text>
        </View>
      </View>

      {/* Watchlist toggle */}
      {showWatchlistToggle && (
        <TouchableOpacity
          style={styles.starBtn}
          onPress={(e) => {
            e.stopPropagation?.();
            if (isWatched) {
              removeWatchlist(item.symbol);
            } else {
              addWatchlist(item.symbol);
            }
          }}
          hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
        >
          <AppIcon name="watchlist" size={16} color={isWatched ? Colors.primary : Colors.textMuted} />
        </TouchableOpacity>
      )}
    </TouchableOpacity>
    </Animated.View>
  );
}

export default function AssetListCard({
  title,
  subtitle,
  icon,
  items,
  showViewAll = true,
  onViewAll,
  showWatchlistToggle = false,
}: AssetListCardProps) {
  const { t } = useTranslation();

  return (
    <View style={styles.card}>
      <View style={styles.header}>
        <View style={{ flex: 1 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <View style={styles.headerIcon}>{icon}</View>
            <Text style={styles.headerTitle}>{title}</Text>
          </View>
          {subtitle ? (
            <Text style={styles.headerSubtitle}>{subtitle}</Text>
          ) : null}
        </View>
        {showViewAll && onViewAll && (
          <TouchableOpacity onPress={onViewAll}>
            <Text style={styles.viewAll}>{t('market.viewAll')} →</Text>
          </TouchableOpacity>
        )}
      </View>

      {items.length === 0 ? (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>--</Text>
        </View>
      ) : (
        items.map((item) => (
          <AssetRow
            key={item.symbol}
            item={item}
            showWatchlistToggle={showWatchlistToggle}
          />
        ))
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    flex: 1,
    minWidth: 280,
    backgroundColor: Colors.surface,
    borderRadius: Sizes.borderRadius,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    ...Shadows.card,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  headerIcon: {
    marginRight: 8,
    width: 18,
    alignItems: 'center',
  },
  headerTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  headerSubtitle: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginTop: 2,
    marginLeft: 24,
  },
  viewAll: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '600',
  },
  // Row
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  avatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    borderWidth: 1,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  avatarText: {
    fontSize: 14,
    fontWeight: '800',
  },
  info: {
    flex: 1,
  },
  symbol: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  name: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
  },
  priceArea: {
    alignItems: 'flex-end',
  },
  price: {
    fontSize: 14,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  changeBadge: {
    marginTop: 4,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 12,
  },
  changeText: {
    fontSize: 11,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  // Watchlist star
  starBtn: {
    marginLeft: 8,
    padding: 4,
  },
  star: {
    fontSize: 18,
    color: Colors.textMuted,
  },
  starActive: {
    color: Colors.primary,
  },
  empty: {
    paddingVertical: 32,
    alignItems: 'center',
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 14,
  },
});
