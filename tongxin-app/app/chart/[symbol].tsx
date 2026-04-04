import { useEffect, useState, useMemo } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  useWindowDimensions,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { SkeletonChart } from '../../components/Skeleton';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { useMarketStore } from '../../services/store/marketStore';
import TradingViewChart from '../../components/chart/TradingViewChart';

const TF_KEYS = [
  { key: 'chart.timeframe1m', value: '1' },
  { key: 'chart.timeframe5m', value: '5' },
  { key: 'chart.timeframe15m', value: '15' },
  { key: 'chart.timeframe1h', value: '60' },
  { key: 'chart.timeframe1d', value: '1D' },
  { key: 'chart.timeframe1w', value: '1W' },
];

export default function ChartDetailScreen() {
  const { t } = useTranslation();
  const { symbol } = useLocalSearchParams<{ symbol: string }>();
  const router = useRouter();
  const { width: screenWidth } = useWindowDimensions();
  const isDesktop = screenWidth >= 1180;

  const { klines, klinesLoading, loadKlines, quotes } = useMarketStore();
  const [selectedTf, setSelectedTf] = useState(4); // 日K

  const quote = quotes[symbol ?? ''];

  useEffect(() => {
    if (symbol) {
      loadKlines(symbol, TF_KEYS[selectedTf].value);
    }
  }, [symbol, selectedTf]);

  const ohlc = useMemo(() => {
    if (klines.length === 0) return null;
    const last = klines[klines.length - 1];
    // 24h 涨跌：用 quote 的 percent_change（后端基于 prev_close 计算）
    // 回退：用前一根K线的 close 作为基准
    const prevClose =
      quote?.prev_close ??
      (klines.length >= 2 ? klines[klines.length - 2].close : last.open);
    const change24h = last.close - prevClose;
    const changePct = prevClose !== 0 ? (change24h / prevClose) * 100 : 0;
    return {
      open: last.open,
      high: last.high,
      low: last.low,
      close: last.close,
      change: quote?.change ?? change24h,
      changePercent: quote?.percent_change ?? changePct,
    };
  }, [klines, quote]);

  return (
    <View style={styles.container}>
      {/* Nav Bar */}
      <View style={styles.navBar}>
        <TouchableOpacity onPress={() => router.back()} style={styles.navBtn}>
          <Text style={styles.navBtnText}>{'<'}</Text>
        </TouchableOpacity>
        <Text style={styles.symbolText}>{symbol}</Text>
        {quote?.name ? (
          <Text style={styles.nameText} numberOfLines={1}>
            {quote.name}
          </Text>
        ) : null}
        <View style={styles.spacer} />
        {/* Market badge */}
        {quote?.market ? (
          <View
            style={[
              styles.badge,
              { borderColor: Colors.accentGold + '40' },
            ]}
          >
            <Text style={[styles.badgeText, { color: Colors.accentGold }]}>
              {quote.market}
            </Text>
          </View>
        ) : null}
      </View>

      {/* Timeframe Bar */}
      <View style={styles.tfBar}>
        {TF_KEYS.map((tf, i) => (
          <TouchableOpacity
            key={tf.value}
            onPress={() => setSelectedTf(i)}
            style={[styles.tfBtn, selectedTf === i && styles.tfBtnActive]}
          >
            <Text
              style={[
                styles.tfLabel,
                selectedTf === i && styles.tfLabelActive,
              ]}
            >
              {t(tf.key)}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* Chart Area */}
      <View style={styles.chartArea}>
        {/* OHLC Overlay */}
        {ohlc && (
          <View style={styles.ohlcOverlay} pointerEvents="none">
            <Text style={styles.ohlcTitle}>
              {symbol} · {t(TF_KEYS[selectedTf].key)}
            </Text>
            <View style={styles.ohlcRow}>
              <OhlcItem label={t('market.open')} value={ohlc.open} change={ohlc.change} />
              <OhlcItem label={t('market.high')} value={ohlc.high} change={ohlc.change} />
              <OhlcItem label={t('market.low')} value={ohlc.low} change={ohlc.change} />
              <OhlcItem label={t('market.close')} value={ohlc.close} change={ohlc.change} />
              <Text
                style={[
                  styles.ohlcChange,
                  { color: ohlc.change >= 0 ? Colors.up : Colors.down },
                ]}
              >
                {ohlc.change >= 0 ? '+' : ''}
                {ohlc.change.toFixed(2)} ({ohlc.changePercent >= 0 ? '+' : ''}
                {ohlc.changePercent.toFixed(2)}%)
              </Text>
            </View>
          </View>
        )}

        {/* Chart */}
        {klinesLoading && klines.length === 0 ? (
          <SkeletonChart />
        ) : klines.length > 0 ? (
          <TradingViewChart klines={klines} symbol={symbol ?? ''} />
        ) : (
          <View style={styles.loading}>
            <Text style={styles.loadingText}>{t('common.noData')}</Text>
          </View>
        )}
      </View>
    </View>
  );
}

function OhlcItem({
  label,
  value,
  change,
}: {
  label: string;
  value: number;
  change: number;
}) {
  const color = change >= 0 ? Colors.up : Colors.down;
  return (
    <View style={styles.ohlcItem}>
      <Text style={styles.ohlcLabel}>{label}=</Text>
      <Text style={[styles.ohlcValue, { color }]}>{value.toFixed(2)}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  // Nav Bar
  navBar: {
    height: Sizes.navBarHeight,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.topBarBg,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 8,
  },
  navBtn: {
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  navBtnText: {
    color: Colors.textMuted,
    fontSize: 16,
  },
  symbolText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    fontFamily: 'monospace',
    marginLeft: 4,
  },
  nameText: {
    color: Colors.textMuted,
    fontSize: 12,
    marginLeft: 8,
    maxWidth: 180,
  },
  spacer: { flex: 1 },
  badge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    borderWidth: 1,
  },
  badgeText: {
    fontSize: 10,
    fontWeight: '600',
  },
  // Timeframe Bar
  tfBar: {
    height: Sizes.timeframeBarHeight,
    flexDirection: 'row',
    alignItems: 'stretch',
    backgroundColor: Colors.topBarBg,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    paddingHorizontal: 8,
  },
  tfBtn: {
    paddingHorizontal: 12,
    justifyContent: 'center',
  },
  tfBtnActive: {
    borderBottomWidth: 2,
    borderBottomColor: Colors.tabUnderline,
  },
  tfLabel: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '400',
  },
  tfLabelActive: {
    color: Colors.textActive,
    fontWeight: '700',
  },
  // Chart
  chartArea: {
    flex: 1,
    position: 'relative',
  },
  loading: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    color: Colors.textMuted,
    fontSize: 14,
  },
  // OHLC Overlay
  ohlcOverlay: {
    position: 'absolute',
    top: 8,
    left: 8,
    zIndex: 10,
    backgroundColor: 'rgba(19, 23, 34, 0.8)',
    borderRadius: 4,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  ohlcTitle: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  ohlcRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 2,
  },
  ohlcItem: {
    flexDirection: 'row',
    marginRight: 8,
  },
  ohlcLabel: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  ohlcValue: {
    fontSize: 11,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  ohlcChange: {
    fontSize: 11,
    fontWeight: '600',
    fontFamily: 'monospace',
    marginLeft: 4,
  },
});
