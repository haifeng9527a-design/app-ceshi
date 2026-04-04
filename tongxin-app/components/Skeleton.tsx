import { useEffect, useRef } from 'react';
import { View, Animated, StyleSheet, ViewStyle } from 'react-native';

interface SkeletonProps {
  width?: number | string;
  height?: number;
  borderRadius?: number;
  style?: ViewStyle;
}

/** Single skeleton block with shimmer animation */
export function Skeleton({ width = '100%', height = 16, borderRadius = 4, style }: SkeletonProps) {
  const opacity = useRef(new Animated.Value(0.3)).current;

  useEffect(() => {
    const anim = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0.7, duration: 800, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 0.3, duration: 800, useNativeDriver: true }),
      ])
    );
    anim.start();
    return () => anim.stop();
  }, []);

  return (
    <Animated.View
      style={[
        { width: width as any, height, borderRadius, backgroundColor: '#2a2a2a', opacity },
        style,
      ]}
    />
  );
}

/** Skeleton row: icon circle + text lines */
export function SkeletonRow({ lines = 2 }: { lines?: number }) {
  return (
    <View style={sk.row}>
      <Skeleton width={40} height={40} borderRadius={20} />
      <View style={sk.rowText}>
        <Skeleton width="60%" height={14} />
        {lines >= 2 && <Skeleton width="40%" height={12} style={{ marginTop: 6 }} />}
      </View>
    </View>
  );
}

/** Skeleton card: mimics a content card */
export function SkeletonCard() {
  return (
    <View style={sk.card}>
      <Skeleton width="70%" height={14} />
      <Skeleton width="50%" height={12} style={{ marginTop: 8 }} />
      <Skeleton width="90%" height={12} style={{ marginTop: 6 }} />
    </View>
  );
}

/** Market list item skeleton */
export function SkeletonMarketItem() {
  return (
    <View style={sk.marketItem}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, flex: 1 }}>
        <Skeleton width={32} height={32} borderRadius={16} />
        <View style={{ flex: 1 }}>
          <Skeleton width={60} height={14} />
          <Skeleton width={40} height={10} style={{ marginTop: 4 }} />
        </View>
      </View>
      <View style={{ alignItems: 'flex-end' }}>
        <Skeleton width={70} height={14} />
        <Skeleton width={50} height={10} style={{ marginTop: 4 }} />
      </View>
    </View>
  );
}

/** Chart skeleton */
export function SkeletonChart() {
  return (
    <View style={sk.chart}>
      <View style={sk.chartBars}>
        {[40, 65, 50, 80, 55, 70, 45, 60, 75, 50, 65, 55, 70, 45, 60].map((h, i) => (
          <Skeleton key={i} width={8} height={h} borderRadius={2} style={{ alignSelf: 'flex-end' }} />
        ))}
      </View>
    </View>
  );
}

/** Position card skeleton */
export function SkeletonPosition() {
  return (
    <View style={sk.card}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 10 }}>
        <Skeleton width={100} height={16} />
        <Skeleton width={70} height={16} />
      </View>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
        {[1, 2, 3, 4, 5, 6].map((i) => (
          <View key={i} style={{ width: '30%' }}>
            <Skeleton width="60%" height={10} />
            <Skeleton width="80%" height={12} style={{ marginTop: 4 }} />
          </View>
        ))}
      </View>
    </View>
  );
}

/** Message conversation skeleton */
export function SkeletonConversation() {
  return (
    <View style={sk.row}>
      <Skeleton width={44} height={44} borderRadius={22} />
      <View style={sk.rowText}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
          <Skeleton width={80} height={14} />
          <Skeleton width={40} height={10} />
        </View>
        <Skeleton width="70%" height={12} style={{ marginTop: 6 }} />
      </View>
    </View>
  );
}

const sk = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 12,
  },
  rowText: {
    flex: 1,
    gap: 0,
  },
  card: {
    backgroundColor: '#1a1a1a',
    borderRadius: 8,
    padding: 14,
    marginHorizontal: 12,
    marginVertical: 6,
  },
  marketItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  chart: {
    height: 200,
    paddingHorizontal: 16,
    paddingVertical: 20,
    justifyContent: 'flex-end',
  },
  chartBars: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    height: 100,
    gap: 6,
  },
});
