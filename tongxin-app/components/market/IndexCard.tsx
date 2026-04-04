import { View, Text, TouchableOpacity, StyleSheet, Animated } from 'react-native';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import { usePriceFlash } from '../../hooks/usePriceFlash';

interface IndexCardProps {
  name: string;
  symbol: string;
  price: string;
  change: number;
  changePct: number;
}

/** Sparkline area chart using View-based bars */
function Sparkline({ isUp }: { isUp: boolean }) {
  const color = isUp ? Colors.up : Colors.down;
  // Simulate a smooth sparkline with many narrow bars
  const points = isUp
    ? [30, 35, 28, 40, 38, 50, 45, 55, 48, 60, 52, 65, 58, 70, 62, 75, 68, 80, 72, 78]
    : [75, 70, 78, 65, 68, 55, 60, 50, 58, 45, 52, 40, 48, 35, 42, 30, 38, 25, 32, 28];

  const max = Math.max(...points);
  const min = Math.min(...points);
  const range = max - min || 1;

  return (
    <View style={sparkStyles.container}>
      {points.map((val, i) => {
        const normalized = ((val - min) / range) * 28;
        return (
          <View
            key={i}
            style={[
              sparkStyles.bar,
              {
                height: normalized + 2,
                backgroundColor: color,
                opacity: 0.3 + (i / points.length) * 0.7,
              },
            ]}
          />
        );
      })}
    </View>
  );
}

const sparkStyles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    height: 30,
    gap: 1,
  },
  bar: {
    width: 2,
    borderRadius: 1,
  },
});

export default function IndexCard({ name, symbol, price, change, changePct }: IndexCardProps) {
  const isUp = changePct >= 0;
  const color = isUp ? Colors.up : Colors.down;
  const sign = isUp ? '+' : '';
  const arrow = isUp ? '\u2197' : '\u2198'; // ↗ ↘
  const flashBg = usePriceFlash(parseFloat(price) || undefined);

  return (
    <Animated.View style={{ flex: 1, backgroundColor: flashBg, borderRadius: Sizes.borderRadius }}>
    <TouchableOpacity style={styles.card} activeOpacity={0.7}>
      {/* Header: name + trend arrow */}
      <View style={styles.header}>
        <View style={{ flex: 1 }}>
          <Text style={styles.name} numberOfLines={1}>{name}</Text>
          <Text style={styles.todayLabel}>Today</Text>
        </View>
        <View style={[styles.arrowBadge, { backgroundColor: isUp ? Colors.upDim : Colors.downDim }]}>
          <Text style={[styles.arrowText, { color }]}>{arrow}</Text>
        </View>
      </View>

      {/* Price */}
      <Text style={styles.price}>{price}</Text>

      {/* Footer: change + sparkline */}
      <View style={styles.footer}>
        <View>
          <Text style={[styles.change, { color }]}>
            {sign}{change.toFixed(2)}
          </Text>
          <Text style={[styles.pct, { color }]}>
            {sign}{changePct.toFixed(2)}%
          </Text>
        </View>
        <Sparkline isUp={isUp} />
      </View>
    </TouchableOpacity>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  card: {
    flex: 1,
    minWidth: 140,
    backgroundColor: Colors.surface,
    borderRadius: Sizes.borderRadius,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    ...Shadows.card,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 10,
  },
  name: {
    color: Colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  todayLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    marginTop: 2,
  },
  arrowBadge: {
    width: 24,
    height: 24,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  arrowText: {
    fontSize: 14,
    fontWeight: '700',
  },
  price: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '700',
    fontFamily: 'monospace',
    marginBottom: 10,
  },
  footer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
  },
  change: {
    fontSize: 12,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  pct: {
    fontSize: 11,
    fontWeight: '600',
    fontFamily: 'monospace',
    marginTop: 1,
  },
});
