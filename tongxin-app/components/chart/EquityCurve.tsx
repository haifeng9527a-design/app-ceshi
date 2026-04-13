import { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, LayoutChangeEvent, Platform, ActivityIndicator } from 'react-native';
import Svg, { Path, Defs, LinearGradient, Stop, Circle, Line, Text as SvgText } from 'react-native-svg';
import { Colors } from '../../theme/colors';
import { getTraderEquity, type EquityPoint } from '../../services/api/traderApi';

type Period = '7D' | '30D' | 'ALL';

interface EquityCurveProps {
  traderUid: string;
}

function formatDollar(n: number): string {
  const abs = Math.abs(n);
  const formatted = abs.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return n < 0 ? `-$${formatted}` : `$${formatted}`;
}

function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return `${d.getMonth() + 1}/${d.getDate()}`;
}

export default function EquityCurve({ traderUid }: EquityCurveProps) {
  const [period, setPeriod] = useState<Period>('30D');
  const [chartWidth, setChartWidth] = useState(600);
  const [hoverIndex, setHoverIndex] = useState<number | null>(null);
  const [data, setData] = useState<EquityPoint[]>([]);
  const [loading, setLoading] = useState(true);
  const chartRef = useRef<View>(null);
  const chartHeight = 220;
  const paddingTop = 20;
  const paddingBottom = 30;
  const paddingLeft = 10;
  const paddingRight = 10;

  const drawWidth = chartWidth - paddingLeft - paddingRight;
  const drawHeight = chartHeight - paddingTop - paddingBottom;

  useEffect(() => {
    if (!traderUid) {
      setLoading(false);
      return;
    }
    let cancelled = false;
    setLoading(true);
    const apiPeriod = period === '7D' ? '7d' : period === '30D' ? '30d' : 'all';
    getTraderEquity(traderUid, apiPeriod)
      .then((points) => {
        if (!cancelled) {
          const arr = Array.isArray(points) ? points : [];
          setData(arr);
        }
      })
      .catch((err) => {
        console.error('[EquityCurve] fetch error:', err);
        if (!cancelled) setData([]);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }, [traderUid, period]);

  // Build chart values from cumulative PNL
  const values = useMemo(() => {
    if (data.length === 0) return [0];
    return data.map((p) => p.cumulative_pnl);
  }, [data]);

  const minVal = Math.min(...values);
  const maxVal = Math.max(...values);
  const range = maxVal - minVal || 1;

  const toX = (i: number) => paddingLeft + (i / Math.max(values.length - 1, 1)) * drawWidth;
  const toY = (v: number) => paddingTop + drawHeight - ((v - minVal) / range) * drawHeight;

  // Build SVG path
  const linePath = values
    .map((v, i) => `${i === 0 ? 'M' : 'L'}${toX(i).toFixed(1)},${toY(v).toFixed(1)}`)
    .join(' ');

  const areaPath = `${linePath} L${toX(values.length - 1).toFixed(1)},${(chartHeight - paddingBottom).toFixed(1)} L${paddingLeft},${(chartHeight - paddingBottom).toFixed(1)} Z`;

  const lastValue = values[values.length - 1];
  const isPositive = lastValue >= 0;
  const lineColor = isPositive ? '#d4af37' : Colors.down;

  const onLayout = (e: LayoutChangeEvent) => {
    const w = e.nativeEvent.layout.width;
    if (w > 0) setChartWidth(w);
  };

  // Active point
  const activeIndex = hoverIndex !== null ? hoverIndex : values.length - 1;
  const activeValue = values[activeIndex] ?? 0;
  const activePoint = data[activeIndex];

  // X-axis labels (pick ~5 evenly spaced dates)
  const xLabels = useMemo(() => {
    if (data.length <= 1) return [];
    const count = Math.min(5, data.length);
    const step = (data.length - 1) / (count - 1);
    return Array.from({ length: count }, (_, i) => {
      const idx = Math.round(i * step);
      return { idx, label: formatDate(data[idx]?.date || '') };
    });
  }, [data]);

  // Web mouse handlers
  const chartCallbackRef = useCallback((node: any) => {
    (chartRef as any).current = node;
    if (Platform.OS !== 'web' || !node) return;
    const domEl: HTMLElement = node;
    if (!domEl.addEventListener) return;

    const prev = (domEl as any).__equityHandlers;
    if (prev) {
      domEl.removeEventListener('mousemove', prev.move);
      domEl.removeEventListener('mouseleave', prev.leave);
    }

    const onMove = (e: MouseEvent) => {
      const rect = domEl.getBoundingClientRect();
      const relX = e.clientX - rect.left - paddingLeft;
      const ratio = relX / (rect.width - paddingLeft - paddingRight);
      const idx = Math.round(ratio * (values.length - 1));
      setHoverIndex(Math.max(0, Math.min(values.length - 1, idx)));
    };
    const onLeave = () => setHoverIndex(null);

    domEl.addEventListener('mousemove', onMove);
    domEl.addEventListener('mouseleave', onLeave);
    (domEl as any).__equityHandlers = { move: onMove, leave: onLeave };
  }, [values.length, paddingLeft, paddingRight]);

  // Tooltip position
  const tooltipX = toX(activeIndex);
  const tooltipY = toY(activeValue);
  const tooltipLeft = Math.max(10, Math.min(tooltipX - 50, chartWidth - 130));
  const tooltipTop = Math.max(0, tooltipY - 65);

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <View>
          <Text style={styles.title}>净值增长 Equity Curve</Text>
          <Text style={styles.subtitle}>
            {period === '7D' ? '近 7 天' : period === '30D' ? '近 30 天' : '全部'} 累计盈亏
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
      {loading ? (
        <View style={styles.loadingBox}>
          <ActivityIndicator color={Colors.primary} />
        </View>
      ) : data.length === 0 ? (
        <View style={styles.loadingBox}>
          <Text style={styles.emptyText}>暂无交易记录</Text>
        </View>
      ) : (
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
            <Path d={areaPath} fill="url(#areaGrad)" />
            <Path d={linePath} fill="none" stroke={lineColor} strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" />

            {/* Zero line */}
            {minVal < 0 && maxVal > 0 && (
              <Line
                x1={paddingLeft}
                y1={toY(0)}
                x2={paddingLeft + drawWidth}
                y2={toY(0)}
                stroke={Colors.textMuted}
                strokeWidth={0.5}
                strokeDasharray="4,4"
                opacity={0.4}
              />
            )}

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

            {/* Active dot */}
            <Circle
              cx={toX(activeIndex)}
              cy={toY(activeValue)}
              r={5}
              fill={lineColor}
              stroke={Colors.surface}
              strokeWidth={2}
            />

            {/* X-axis labels */}
            {xLabels.map(({ idx, label }) => (
              <SvgText
                key={idx}
                x={toX(idx)}
                y={chartHeight - 6}
                fill={Colors.textMuted}
                fontSize={10}
                fontWeight="600"
                textAnchor="middle"
              >
                {label}
              </SvgText>
            ))}

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
            style={[styles.tooltip, { left: tooltipLeft, top: tooltipTop }]}
            pointerEvents="none"
          >
            <Text style={styles.tooltipLabel}>
              {activePoint ? formatDate(activePoint.date) : ''}
            </Text>
            <Text style={styles.tooltipValue}>{formatDollar(activeValue)}</Text>
            {activePoint && (
              <Text style={[styles.tooltipChange, { color: activePoint.daily_pnl >= 0 ? Colors.up : Colors.down }]}>
                当日: {activePoint.daily_pnl >= 0 ? '+' : ''}{formatDollar(activePoint.daily_pnl)}
              </Text>
            )}
          </View>
        </View>
      )}
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
  loadingBox: {
    height: 220,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  tooltip: {
    position: 'absolute',
    backgroundColor: 'rgba(30,30,40,0.95)',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderWidth: 1,
    borderColor: Colors.border,
    minWidth: 110,
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
