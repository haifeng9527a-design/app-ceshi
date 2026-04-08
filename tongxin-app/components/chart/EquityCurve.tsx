import { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, LayoutChangeEvent, Platform } from 'react-native';
import Svg, { Path, Defs, LinearGradient, Stop, Circle, Line, Text as SvgText, Rect } from 'react-native-svg';
import { Colors } from '../../theme/colors';

type Period = '7D' | '30D' | 'ALL';

interface EquityCurveProps {
  /** Total PnL value used to generate demo curve */
  totalPnl: number;
  /** Total number of trades */
  totalTrades: number;
}

/** Generate mock equity data points based on totalPnl */
function generateEquityData(totalPnl: number, count: number): number[] {
  const points: number[] = [];
  const seed = Math.abs(totalPnl * 137) % 1000;
  const startEquity = Math.max(1000, Math.abs(totalPnl) * 2);
  let value = startEquity;
  const target = startEquity + totalPnl;
  const step = (target - value) / count;

  for (let i = 0; i <= count; i++) {
    const noise = Math.sin(seed + i * 0.7) * (Math.abs(step) * 2 + 20);
    value += step + noise * 0.3;
    points.push(Math.max(value, 50));
  }
  points[points.length - 1] = target;
  return points;
}

function getLabels(period: Period): string[] {
  if (period === '7D') return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (period === '30D') return ['Week 1', 'Week 2', 'Week 3', 'Week 4', 'Today'];
  return ['Jan', 'Mar', 'May', 'Jul', 'Sep', 'Nov'];
}

function getPointCount(period: Period): number {
  if (period === '7D') return 14;
  if (period === '30D') return 30;
  return 60;
}

function formatDollar(n: number): string {
  return n.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

export default function EquityCurve({ totalPnl, totalTrades }: EquityCurveProps) {
  const [period, setPeriod] = useState<Period>('30D');
  const [chartWidth, setChartWidth] = useState(600);
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);
  const chartRef = useRef<View>(null);
  const chartHeight = 220;
  const paddingTop = 20;
  const paddingBottom = 30;
  const paddingLeft = 10;
  const paddingRight = 10;

  const drawWidth = chartWidth - paddingLeft - paddingRight;
  const drawHeight = chartHeight - paddingTop - paddingBottom;

  const data = useMemo(
    () => generateEquityData(totalPnl, getPointCount(period)),
    [totalPnl, period],
  );

  const labels = getLabels(period);

  const minVal = Math.min(...data);
  const maxVal = Math.max(...data);
  const range = maxVal - minVal || 1;

  const toX = (i: number) => paddingLeft + (i / (data.length - 1)) * drawWidth;
  const toY = (v: number) => paddingTop + drawHeight - ((v - minVal) / range) * drawHeight;

  // Build SVG path
  const linePath = data
    .map((v, i) => `${i === 0 ? 'M' : 'L'}${toX(i).toFixed(1)},${toY(v).toFixed(1)}`)
    .join(' ');

  // Area path (fill under curve)
  const areaPath = `${linePath} L${toX(data.length - 1).toFixed(1)},${(chartHeight - paddingBottom).toFixed(1)} L${paddingLeft},${(chartHeight - paddingBottom).toFixed(1)} Z`;

  const lastValue = data[data.length - 1];
  const firstValue = data[0];
  const isPositive = totalPnl >= 0;
  const lineColor = isPositive ? '#d4af37' : Colors.down;

  const onLayout = (e: LayoutChangeEvent) => {
    const w = e.nativeEvent.layout.width;
    if (w > 0) setChartWidth(w);
  };

  // Determine which index to show tooltip for
  const activeIndex = hoverIndex !== null ? hoverIndex : data.length - 1;
  const activeValue = data[activeIndex];
  const activeChange = ((activeValue - firstValue) / Math.abs(firstValue) * 100).toFixed(1);
  const activeIsPositive = activeValue >= firstValue;

  // Date label for hovered point
  const getPointLabel = (idx: number): string => {
    if (period === '7D') {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const dayIdx = Math.round((idx / (data.length - 1)) * 6);
      return days[dayIdx] || '';
    }
    if (period === '30D') {
      const day = Math.round((idx / (data.length - 1)) * 29) + 1;
      return `Day ${day}`;
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const mIdx = Math.round((idx / (data.length - 1)) * 11);
    return months[mIdx] || '';
  };

  // Web mouse handlers via native DOM listeners (RN Web View doesn't support onMouseMove prop)
  const chartCallbackRef = useCallback((node: any) => {
    // Store for onLayout ref
    (chartRef as any).current = node;
    if (Platform.OS !== 'web' || !node) return;
    // In RN Web, ref gives us the DOM element directly
    const domEl: HTMLElement = node;
    if (!domEl.addEventListener) return;

    // Clean up previous listeners if any
    const prev = (domEl as any).__equityHandlers;
    if (prev) {
      domEl.removeEventListener('mousemove', prev.move);
      domEl.removeEventListener('mouseleave', prev.leave);
    }

    const onMove = (e: MouseEvent) => {
      const rect = domEl.getBoundingClientRect();
      const relX = e.clientX - rect.left - paddingLeft;
      const ratio = relX / (rect.width - paddingLeft - paddingRight);
      const idx = Math.round(ratio * (data.length - 1));
      setHoverIndex(Math.max(0, Math.min(data.length - 1, idx)));
    };
    const onLeave = () => setHoverIndex(null);

    domEl.addEventListener('mousemove', onMove);
    domEl.addEventListener('mouseleave', onLeave);
    (domEl as any).__equityHandlers = { move: onMove, leave: onLeave };
  }, [data.length, paddingLeft, paddingRight]);

  // Tooltip position clamping
  const tooltipX = toX(activeIndex);
  const tooltipY = toY(activeValue);
  const tooltipLeft = Math.max(10, Math.min(tooltipX - 50, chartWidth - 120));
  const tooltipTop = Math.max(0, tooltipY - 65);

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <View>
          <Text style={styles.title}>净值增长 Equity Curve</Text>
          <Text style={styles.subtitle}>
            {period === '7D' ? 'Past 7 Days' : period === '30D' ? 'Past 30 Days' : 'All Time'} Growth Trend
          </Text>
        </View>
        <View style={styles.periodTabs}>
          {(['7D', '30D', 'ALL'] as Period[]).map((p) => (
            <TouchableOpacity
              key={p}
              style={[styles.periodTab, period === p && styles.periodTabActive]}
              onPress={() => setPeriod(p)}
            >
              <Text style={[styles.periodTabText, period === p && styles.periodTabTextActive]}>{p}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      {/* Chart */}
      <View
        ref={chartCallbackRef}
        style={styles.chartArea}
        onLayout={onLayout}
      >
        <Svg width={chartWidth} height={chartHeight}>
          <Defs>
            <LinearGradient id="areaGrad" x1="0" y1="0" x2="0" y2="1">
              <Stop offset="0" stopColor={lineColor} stopOpacity={0.3} />
              <Stop offset="1" stopColor={lineColor} stopOpacity={0} />
            </LinearGradient>
          </Defs>
          {/* Area fill */}
          <Path d={areaPath} fill="url(#areaGrad)" />
          {/* Line */}
          <Path d={linePath} fill="none" stroke={lineColor} strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" />

          {/* Hover vertical line */}
          {hoverIndex !== null && (
            <Line
              x1={toX(hoverIndex)}
              y1={paddingTop}
              x2={toX(hoverIndex)}
              y2={chartHeight - paddingBottom}
              stroke={Colors.textMuted}
              strokeWidth={1}
              strokeDasharray="4,3"
              opacity={0.6}
            />
          )}

          {/* Active point dot */}
          <Circle
            cx={toX(activeIndex)}
            cy={toY(activeValue)}
            r={5}
            fill={lineColor}
            stroke={Colors.surface}
            strokeWidth={2}
          />

          {/* X-axis labels */}
          {labels.map((label, i) => {
            const x = paddingLeft + (i / (labels.length - 1)) * drawWidth;
            return (
              <SvgText
                key={i}
                x={x}
                y={chartHeight - 6}
                fill={Colors.textMuted}
                fontSize={10}
                fontWeight="600"
                textAnchor="middle"
                letterSpacing={1}
              >
                {label.toUpperCase()}
              </SvgText>
            );
          })}
          {/* Grid lines */}
          {[0.25, 0.5, 0.75].map((pct) => {
            const y = paddingTop + drawHeight * (1 - pct);
            return (
              <Line
                key={pct}
                x1={paddingLeft}
                y1={y}
                x2={paddingLeft + drawWidth}
                y2={y}
                stroke={Colors.border}
                strokeWidth={0.5}
                strokeDasharray="4,4"
              />
            );
          })}
        </Svg>

        {/* Tooltip */}
        <View
          style={[
            styles.tooltip,
            {
              left: tooltipLeft,
              top: tooltipTop,
            },
          ]}
          pointerEvents="none"
        >
          <Text style={styles.tooltipLabel}>{getPointLabel(activeIndex)}</Text>
          <Text style={styles.tooltipValue}>
            ${formatDollar(activeValue)}
          </Text>
          <Text style={[styles.tooltipChange, { color: activeIsPositive ? Colors.up : Colors.down }]}>
            {activeIsPositive ? '+' : ''}{activeChange}%
          </Text>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: 20,
    marginBottom: 16,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 20,
  },
  title: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
    marginBottom: 4,
  },
  subtitle: {
    color: Colors.textMuted,
    fontSize: 12,
  },
  periodTabs: {
    flexDirection: 'row',
    backgroundColor: Colors.background,
    borderRadius: 8,
    padding: 2,
  },
  periodTab: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 6,
  },
  periodTabActive: {
    backgroundColor: Colors.surfaceAlt,
  },
  periodTabText: {
    color: Colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
  },
  periodTabTextActive: {
    color: Colors.textActive,
  },
  chartArea: {
    position: 'relative',
    // @ts-ignore web cursor
    cursor: 'crosshair',
  },
  tooltip: {
    position: 'absolute',
    backgroundColor: 'rgba(30,30,40,0.95)',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderWidth: 1,
    borderColor: Colors.border,
    minWidth: 100,
  },
  tooltipLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 0.5,
    marginBottom: 2,
  },
  tooltipValue: {
    color: '#d4af37',
    fontSize: 14,
    fontWeight: '700',
  },
  tooltipChange: {
    fontSize: 11,
    fontWeight: '600',
    marginTop: 2,
  },
});
