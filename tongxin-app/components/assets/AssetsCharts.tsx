import { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Defs, LinearGradient, Line, Path, Rect, Stop } from 'react-native-svg';
import { Colors } from '../../theme/colors';
import type { AssetChangePoint, AssetPnlCalendarResponse } from '../../services/api/assetsApi';

type DistributionItem = {
  key: string;
  label: string;
  value: number;
  color: string;
};

export function DistributionChart({ items }: { items: DistributionItem[] }) {
  const total = items.reduce((sum, item) => sum + Math.max(item.value, 0), 0);

  return (
    <View style={styles.card}>
      <View style={styles.barWrap}>
        {items.map((item) => {
          const ratio = total > 0 ? item.value / total : 0;
          return (
            <View
              key={item.key}
              style={[
                styles.barSegment,
                {
                  backgroundColor: item.color,
                  flex: Math.max(ratio, 0.05),
                  opacity: item.value > 0 ? 1 : 0.25,
                },
              ]}
            />
          );
        })}
      </View>

      <View style={styles.legendList}>
        {items.map((item) => {
          const ratio = total > 0 ? item.value / total : 0;
          return (
            <View key={item.key} style={styles.legendItem}>
              <View style={[styles.legendDot, { backgroundColor: item.color }]} />
              <View style={styles.legendTextWrap}>
                <Text style={styles.legendLabel}>{item.label}</Text>
                <Text style={styles.legendValue}>
                  {item.value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} USDT
                </Text>
              </View>
              <Text style={styles.legendRatio}>{(ratio * 100).toFixed(1)}%</Text>
            </View>
          );
        })}
      </View>
    </View>
  );
}

export function ChangeSeriesChart({ points }: { points: AssetChangePoint[] }) {
  const width = 320;
  const height = 160;
  const paddingX = 18;
  const paddingY = 18;
  const [chartWidth, setChartWidth] = useState(width);
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);

  if (!points.length) {
    return (
      <View style={[styles.card, styles.chartEmpty]}>
        <Text style={styles.emptyText}>--</Text>
      </View>
    );
  }

  const values = points.map((point) => point.equity);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = Math.max(max - min, 1);

  const coords = points.map((point, index) => {
    const x = paddingX + (index * (width - paddingX * 2)) / Math.max(points.length - 1, 1);
    const y = height - paddingY - ((point.equity - min) / range) * (height - paddingY * 2);
    return { x, y, ...point };
  });

  const linePath = coords
    .map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`)
    .join(' ');
  const areaPath = `${linePath} L ${coords[coords.length - 1].x} ${height - paddingY} L ${coords[0].x} ${height - paddingY} Z`;
  const activeIndex = hoverIndex ?? points.length - 1;
  const activePoint = coords[Math.max(0, Math.min(activeIndex, coords.length - 1))];
  const activeChange = activePoint?.net_change ?? 0;
  const activeTooltipLeft = activePoint
    ? Math.max(8, Math.min((activePoint.x / width) * chartWidth - 72, chartWidth - 144))
    : 8;
  const activeTooltipTop = activePoint
    ? Math.max(6, ((activePoint.y / height) * height) - 58)
    : 6;

  const pickNearestIndex = useMemo(
    () => (locationX: number) => {
      if (!coords.length || chartWidth <= 0) return null;
      let nearest = 0;
      let minDistance = Number.POSITIVE_INFINITY;
      for (let index = 0; index < coords.length; index += 1) {
        const actualX = (coords[index].x / width) * chartWidth;
        const distance = Math.abs(actualX - locationX);
        if (distance < minDistance) {
          minDistance = distance;
          nearest = index;
        }
      }
      return nearest;
    },
    [chartWidth, coords],
  );

  const handlePointerAt = (locationX?: number | null) => {
    if (locationX == null) return;
    const nearest = pickNearestIndex(locationX);
    if (nearest != null) {
      setHoverIndex(nearest);
    }
  };

  const handleWebPointer = (event: any) => {
    const native = event?.nativeEvent ?? {};
    if (typeof native.locationX === 'number') {
      handlePointerAt(native.locationX);
      return;
    }
    if (typeof native.offsetX === 'number') {
      handlePointerAt(native.offsetX);
      return;
    }
    const rect = event?.currentTarget?.getBoundingClientRect?.();
    if (rect && typeof native.clientX === 'number') {
      handlePointerAt(native.clientX - rect.left);
    }
  };

  return (
    <View style={styles.card}>
      <View
        style={styles.chartStage}
        onLayout={(event) => {
          const nextWidth = event.nativeEvent.layout.width;
          if (nextWidth > 0) {
            setChartWidth(nextWidth);
          }
        }}
      >
        <Svg width="100%" height={height} viewBox={`0 0 ${width} ${height}`}>
          <Defs>
            <LinearGradient id="equityFill" x1="0" y1="0" x2="0" y2="1">
              <Stop offset="0%" stopColor={Colors.primary} stopOpacity="0.32" />
              <Stop offset="100%" stopColor={Colors.primary} stopOpacity="0.02" />
            </LinearGradient>
          </Defs>
          <Line x1={paddingX} y1={height - paddingY} x2={width - paddingX} y2={height - paddingY} stroke={Colors.border} strokeWidth="1" />
          <Path d={areaPath} fill="url(#equityFill)" />
          <Path d={linePath} stroke={Colors.primary} strokeWidth="3" fill="none" />
          {hoverIndex !== null && activePoint ? (
            <Line
              x1={activePoint.x}
              y1={paddingY}
              x2={activePoint.x}
              y2={height - paddingY}
              stroke={Colors.primary}
              strokeOpacity="0.28"
              strokeWidth="1"
              strokeDasharray="4 4"
            />
          ) : null}
          {coords.map((point, index) => (
            <Rect
              key={`${point.date}-${point.label}`}
              x={point.x - (index === activeIndex ? 4 : 2.5)}
              y={point.y - (index === activeIndex ? 4 : 2.5)}
              width={index === activeIndex ? 8 : 5}
              height={index === activeIndex ? 8 : 5}
              rx={index === activeIndex ? 4 : 2.5}
              fill={point.net_change >= 0 ? Colors.up : Colors.down}
            />
          ))}
        </Svg>

        <Pressable
          style={styles.chartHitArea}
          onPressIn={(event) => handlePointerAt(event.nativeEvent.locationX)}
          onPressOut={() => setHoverIndex(null)}
          // @ts-ignore react-native-web mouse events
          onMouseEnter={handleWebPointer}
          // @ts-ignore react-native-web mouse events
          onMouseMove={handleWebPointer}
          // @ts-ignore react-native-web mouse events
          onMouseLeave={() => setHoverIndex(null)}
        />

        {activePoint && hoverIndex !== null ? (
          <View style={[styles.chartTooltip, { left: activeTooltipLeft, top: activeTooltipTop }]}>
            <Text style={styles.chartTooltipLabel}>{activePoint.label}</Text>
            <Text style={styles.chartTooltipValue}>
              {activePoint.equity.toLocaleString(undefined, {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2,
              })}{' '}
              USDT
            </Text>
            <Text
              style={[
                styles.chartTooltipChange,
                { color: activeChange >= 0 ? Colors.up : Colors.down },
              ]}
            >
              {activeChange >= 0 ? '+' : ''}
              {activeChange.toLocaleString(undefined, {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2,
              })}{' '}
              USDT
            </Text>
          </View>
        ) : null}
      </View>

      <View style={styles.axisLabels}>
        {points.map((point) => (
          <Text key={point.date} style={styles.axisText}>{point.label}</Text>
        ))}
      </View>
    </View>
  );
}

export function PnlCalendar({
  data,
  weekdays,
  selectedDate,
  onSelectDate,
}: {
  data: AssetPnlCalendarResponse | null;
  weekdays: string[];
  selectedDate?: string | null;
  onSelectDate?: (date: string) => void;
}) {
  const days = data?.days || [];

  if (!days.length) {
    return (
      <View style={[styles.card, styles.calendarEmpty]}>
        <Text style={styles.emptyText}>--</Text>
      </View>
    );
  }

  const firstDate = new Date(`${days[0].date}T00:00:00`);
  const firstWeekday = Number.isNaN(firstDate.getTime()) ? 0 : firstDate.getDay();
  const cells: Array<
    | { type: 'empty'; key: string }
    | { type: 'day'; key: string; day: typeof days[number] }
  > = [];
  for (let i = 0; i < firstWeekday; i += 1) {
    cells.push({ type: 'empty', key: `empty-${i}` });
  }
  days.forEach((day) => cells.push({ type: 'day', key: day.date, day }));

  return (
    <View style={styles.card}>
      <View style={styles.calendarWeekdays}>
        {weekdays.map((label) => (
          <Text key={label} style={styles.calendarWeekdayText}>
            {label}
          </Text>
        ))}
      </View>

      <View style={styles.calendarGrid}>
        {cells.map((cell) => {
          if (cell.type === 'empty') {
            return <View key={cell.key} style={[styles.calendarCell, styles.calendarCellEmpty]} />;
          }

          const day = cell.day;
          const toneStyle =
            day.net_pnl > 0
              ? styles.calendarCellPositive
              : day.net_pnl < 0
                ? styles.calendarCellNegative
                : styles.calendarCellFlat;

          return (
            <Pressable
              key={cell.key}
              onPress={() => onSelectDate?.(day.date)}
              style={[
                styles.calendarCell,
                toneStyle,
                day.is_today && styles.calendarCellToday,
                selectedDate === day.date && styles.calendarCellSelected,
              ]}
            >
              <Text style={styles.calendarDayNumber}>{day.day}</Text>
              {day.has_data ? (
                <Text
                  style={[
                    styles.calendarDayPnl,
                    { color: day.net_pnl >= 0 ? Colors.up : Colors.down },
                  ]}
                  numberOfLines={1}
                >
                  {day.net_pnl >= 0 ? '+' : ''}
                  {Math.abs(day.net_pnl) >= 1000
                    ? `${(day.net_pnl / 1000).toFixed(1)}k`
                    : day.net_pnl.toFixed(0)}
                </Text>
              ) : null}
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 12,
  },
  barWrap: {
    height: 14,
    borderRadius: 999,
    overflow: 'hidden',
    flexDirection: 'row',
    backgroundColor: Colors.background,
    gap: 2,
  },
  barSegment: {
    height: '100%',
  },
  legendList: {
    gap: 10,
  },
  legendItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  legendDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  legendTextWrap: {
    flex: 1,
    gap: 2,
  },
  legendLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
  },
  legendValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '800',
  },
  legendRatio: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
  },
  chartStage: {
    position: 'relative',
  },
  chartHitArea: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    height: 160,
    cursor: 'pointer',
  },
  chartTooltip: {
    position: 'absolute',
    width: 144,
    backgroundColor: Colors.background,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 10,
    paddingVertical: 8,
    gap: 2,
  },
  chartTooltipLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
  },
  chartTooltipValue: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  chartTooltipChange: {
    fontSize: 12,
    fontWeight: '800',
  },
  axisLabels: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 6,
  },
  axisText: {
    flex: 1,
    color: Colors.textMuted,
    fontSize: 10,
    textAlign: 'center',
  },
  chartEmpty: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 120,
  },
  calendarEmpty: {
    minHeight: 220,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 18,
    fontWeight: '700',
  },
  calendarWeekdays: {
    flexDirection: 'row',
    gap: 8,
  },
  calendarWeekdayText: {
    flex: 1,
    textAlign: 'center',
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
  },
  calendarGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  calendarCell: {
    width: '13.2%',
    minHeight: 58,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.background,
    paddingHorizontal: 8,
    paddingVertical: 6,
    justifyContent: 'space-between',
  },
  calendarCellEmpty: {
    borderColor: 'transparent',
    backgroundColor: 'transparent',
  },
  calendarCellPositive: {
    backgroundColor: Colors.up + '14',
    borderColor: Colors.up + '33',
  },
  calendarCellNegative: {
    backgroundColor: Colors.down + '12',
    borderColor: Colors.down + '33',
  },
  calendarCellFlat: {
    backgroundColor: Colors.background,
    borderColor: Colors.border,
  },
  calendarCellToday: {
    borderColor: Colors.primary,
    shadowColor: Colors.primary,
    shadowOpacity: 0.16,
    shadowRadius: 12,
  },
  calendarCellSelected: {
    borderColor: Colors.primary,
    borderWidth: 1.5,
  },
  calendarDayNumber: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '800',
  },
  calendarDayPnl: {
    fontSize: 11,
    fontWeight: '800',
  },
});
