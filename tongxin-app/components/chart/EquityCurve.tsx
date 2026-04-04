import { useState, useMemo } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, LayoutChangeEvent } from 'react-native';
import Svg, { Path, Defs, LinearGradient, Stop, Circle, Line, Text as SvgText } from 'react-native-svg';
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
  let value = 1000; // starting equity
  const target = 1000 + totalPnl;
  const step = (target - value) / count;

  for (let i = 0; i <= count; i++) {
    // Add some deterministic "randomness" based on seed
    const noise = Math.sin(seed + i * 0.7) * (Math.abs(step) * 2 + 20);
    value += step + noise * 0.3;
    // Ensure we don't go negative
    points.push(Math.max(value, 50));
  }
  // Make last point match total
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

export default function EquityCurve({ totalPnl, totalTrades }: EquityCurveProps) {
  const [period, setPeriod] = useState<Period>('30D');
  const [chartWidth, setChartWidth] = useState(600);
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
  const changePercent = ((lastValue - firstValue) / firstValue * 100).toFixed(1);
  const isPositive = totalPnl >= 0;
  const lineColor = isPositive ? '#d4af37' : Colors.down;

  const onLayout = (e: LayoutChangeEvent) => {
    const w = e.nativeEvent.layout.width;
    if (w > 0) setChartWidth(w);
  };

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
      <View style={styles.chartArea} onLayout={onLayout}>
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
          {/* Endpoint dot */}
          <Circle cx={toX(data.length - 1)} cy={toY(lastValue)} r={4} fill={lineColor} />
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

        {/* Tooltip overlay - last point */}
        <View
          style={[
            styles.tooltip,
            {
              left: Math.min(toX(data.length - 1) - 40, chartWidth - 110),
              top: toY(lastValue) - 60,
            },
          ]}
        >
          <Text style={styles.tooltipValue}>
            Equity: ${lastValue.toFixed(0)}
          </Text>
          <Text style={[styles.tooltipChange, { color: isPositive ? Colors.up : Colors.down }]}>
            {isPositive ? '+' : ''}{changePercent}%
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
  },
  tooltip: {
    position: 'absolute',
    backgroundColor: 'rgba(30,30,40,0.9)',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  tooltipValue: {
    color: '#d4af37',
    fontSize: 12,
    fontWeight: '700',
  },
  tooltipChange: {
    fontSize: 11,
    fontWeight: '600',
    marginTop: 2,
  },
});
