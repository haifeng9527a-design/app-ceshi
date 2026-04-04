import { useEffect, useRef } from 'react';
import { View, Text, StyleSheet, Platform } from 'react-native';
import { Colors } from '../../theme/colors';
import type { DrawingTool } from './DrawingToolsSidebar';
import type { IndicatorType } from './indicators';

/* ═══════════════════════════════════════════
   Types
   ═══════════════════════════════════════════ */

interface KlineData {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume?: number;
}

export type ChartType = 'candle' | 'hollowCandle' | 'ohlc' | 'line' | 'area';

export interface ActiveIndicator {
  type: IndicatorType;
  params: Record<string, number>;
}

export interface CrosshairData {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
  change: number;
  changePct: number;
  ma5: number | null;
  ma10: number | null;
  ma30: number | null;
}

export const MA_COLORS = {
  ma5: '#F5C842',
  ma10: '#26A69A',
  ma30: '#AB47BC',
};

interface TradingViewChartProps {
  klines: KlineData[];
  symbol: string;
  chartType?: ChartType;
  activeIndicators?: ActiveIndicator[];
  drawingTool?: DrawingTool;
  onCrosshairData?: (data: CrosshairData | null) => void;
  onDrawingComplete?: () => void;
  onClearDrawings?: boolean;
  realtimePrice?: number;
}

/* ═══════════════════════════════════════════
   KLineChart candle type mapping
   ═══════════════════════════════════════════ */

const CANDLE_TYPE_MAP: Record<ChartType, string> = {
  candle: 'candle_solid',
  hollowCandle: 'candle_stroke',
  ohlc: 'ohlc',
  line: 'area',
  area: 'area',
};

// Indicators that belong on the main candle pane (overlays)
const OVERLAY_INDICATORS = new Set<string>(['MA', 'EMA', 'SMA', 'BOLL', 'SAR']);

/* ═══════════════════════════════════════════
   Dark Theme
   ═══════════════════════════════════════════ */

const DARK_THEME: Record<string, any> = {
  grid: {
    show: true,
    horizontal: { show: true, size: 1, color: 'rgba(255,255,255,0.06)', style: 'dashed', dashedValue: [2, 2] },
    vertical: { show: false },
  },
  candle: {
    type: 'candle_solid',
    bar: {
      upColor: '#26A69A',
      downColor: '#EF5350',
      noChangeColor: '#888888',
      upBorderColor: '#26A69A',
      downBorderColor: '#EF5350',
      noChangeBorderColor: '#888888',
      upWickColor: '#26A69A',
      downWickColor: '#EF5350',
      noChangeWickColor: '#888888',
    },
    area: {
      lineSize: 2,
      lineColor: '#2196F3',
      smooth: false,
      value: 'close',
      backgroundColor: [
        { offset: 0, color: 'rgba(33,150,243,0.15)' },
        { offset: 1, color: 'rgba(33,150,243,0)' },
      ],
    },
    priceMark: {
      show: true,
      high: { show: true, color: '#D9D9D9', textSize: 10 },
      low: { show: true, color: '#D9D9D9', textSize: 10 },
      last: {
        show: true,
        upColor: '#26A69A',
        downColor: '#EF5350',
        noChangeColor: '#888888',
        line: { show: true, style: 'dashed', dashedValue: [4, 4], size: 1 },
        text: {
          show: true,
          style: 'fill',
          size: 11,
          paddingLeft: 4,
          paddingRight: 4,
          paddingTop: 2,
          paddingBottom: 2,
          borderRadius: 2,
          color: '#FFFFFF',
        },
      },
    },
    tooltip: {
      showRule: 'always',
      showType: 'standard',
    },
  },
  indicator: {
    bars: [{
      upColor: 'rgba(38,166,154,0.65)',
      downColor: 'rgba(239,83,80,0.65)',
      noChangeColor: '#888888',
    }],
    lines: [
      { size: 1, color: '#FF9600' },
      { size: 1, color: '#9D65C9' },
      { size: 1, color: '#2196F3' },
      { size: 1, color: '#E040FB' },
      { size: 1, color: '#00BCD4' },
    ],
    tooltip: {
      showRule: 'always',
      showType: 'standard',
    },
  },
  xAxis: {
    show: true,
    axisLine: { show: true, color: '#222222', size: 1 },
    tickText: { show: true, color: '#888888', size: 10 },
    tickLine: { show: true, color: '#333333', size: 1 },
  },
  yAxis: {
    show: true,
    position: 'right',
    axisLine: { show: true, color: '#222222', size: 1 },
    tickText: { show: true, color: '#888888', size: 10 },
    tickLine: { show: true, color: '#333333', size: 1 },
  },
  separator: {
    size: 1,
    color: '#222222',
    fill: true,
    activeBackgroundColor: 'rgba(242,202,80,0.15)',
  },
  crosshair: {
    show: true,
    horizontal: {
      show: true,
      line: { show: true, style: 'dashed', dashedValue: [4, 2], size: 1, color: '#888888' },
      text: {
        show: true,
        style: 'fill',
        color: '#FFFFFF',
        size: 11,
        borderRadius: 2,
        paddingLeft: 4,
        paddingRight: 4,
        paddingTop: 2,
        paddingBottom: 2,
        backgroundColor: '#373737',
      },
    },
    vertical: {
      show: true,
      line: { show: true, style: 'dashed', dashedValue: [4, 2], size: 1, color: '#888888' },
      text: {
        show: true,
        style: 'fill',
        color: '#FFFFFF',
        size: 11,
        borderRadius: 2,
        paddingLeft: 4,
        paddingRight: 4,
        paddingTop: 2,
        paddingBottom: 2,
        backgroundColor: '#373737',
      },
    },
  },
  overlay: {
    point: {
      color: '#1677FF',
      borderColor: 'rgba(22,119,255,0.35)',
      borderSize: 1,
      radius: 5,
      activeColor: '#1677FF',
      activeBorderColor: 'rgba(22,119,255,0.35)',
      activeBorderSize: 3,
      activeRadius: 5,
    },
    line: { color: '#1677FF', size: 1 },
    rect: {
      style: 'fill',
      color: 'rgba(22,119,255,0.25)',
      borderColor: '#1677FF',
      borderSize: 1,
    },
    text: {
      color: '#FFFFFF',
      size: 12,
      backgroundColor: '#1677FF',
      borderRadius: 2,
      paddingLeft: 4,
      paddingRight: 4,
      paddingTop: 3,
      paddingBottom: 3,
    },
  },
};

/* ═══════════════════════════════════════════
   Component
   ═══════════════════════════════════════════ */

export default function TradingViewChart({
  klines,
  symbol,
  chartType = 'candle',
  activeIndicators = [],
  drawingTool = 'cursor',
  onCrosshairData,
  onDrawingComplete,
  onClearDrawings,
  realtimePrice,
}: TradingViewChartProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<any>(null);
  const kcRef = useRef<any>(null); // klinecharts module
  const prevIndicatorsRef = useRef<Set<string>>(new Set());
  const indicatorPaneMapRef = useRef<Map<string, string>>(new Map());
  const drawingToolRef = useRef(drawingTool);
  const onDrawingCompleteRef = useRef(onDrawingComplete);

  // Keep refs in sync
  drawingToolRef.current = drawingTool;
  onDrawingCompleteRef.current = onDrawingComplete;

  /* ─── Initialize chart ─── */
  useEffect(() => {
    if (Platform.OS !== 'web' || !containerRef.current) return;

    const kc = require('klinecharts');
    kcRef.current = kc;

    const chart = kc.init(containerRef.current, {
      styles: DARK_THEME,
    });
    chartRef.current = chart;

    // Default volume sub-pane
    chart.createIndicator('VOL', false, { id: 'vol_pane', height: 60 });

    return () => {
      kc.dispose(containerRef.current);
      chartRef.current = null;
      kcRef.current = null;
      prevIndicatorsRef.current = new Set();
      indicatorPaneMapRef.current = new Map();
    };
  }, []);

  /* ─── Apply kline data ─── */
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !klines.length) return;

    const data = klines.map((k) => ({
      timestamp: k.time * 1000,
      open: k.open,
      high: k.high,
      low: k.low,
      close: k.close,
      volume: k.volume || 0,
    }));

    chart.applyNewData(data);
  }, [klines]);

  /* ─── Real-time price update (last bar) ─── */
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !realtimePrice || !klines.length) return;

    const last = klines[klines.length - 1];
    chart.updateData({
      timestamp: last.time * 1000,
      open: last.open,
      high: Math.max(last.high, realtimePrice),
      low: Math.min(last.low, realtimePrice),
      close: realtimePrice,
      volume: last.volume || 0,
    });
  }, [realtimePrice]);

  /* ─── Chart type ─── */
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart) return;

    if (chartType === 'line') {
      chart.setStyles({
        candle: {
          type: 'area',
          area: {
            lineSize: 2,
            lineColor: '#2196F3',
            backgroundColor: [
              { offset: 0, color: 'transparent' },
              { offset: 1, color: 'transparent' },
            ],
          },
        },
      });
    } else if (chartType === 'area') {
      chart.setStyles({
        candle: {
          type: 'area',
          area: {
            lineSize: 2,
            lineColor: '#2196F3',
            backgroundColor: [
              { offset: 0, color: 'rgba(33,150,243,0.15)' },
              { offset: 1, color: 'rgba(33,150,243,0)' },
            ],
          },
        },
      });
    } else {
      chart.setStyles({
        candle: { type: CANDLE_TYPE_MAP[chartType] || 'candle_solid' },
      });
    }
  }, [chartType]);

  /* ─── Manage indicators ─── */
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart) return;

    const newTypes = new Set(activeIndicators.map((i) => i.type));
    const prevTypes = prevIndicatorsRef.current;

    // Remove indicators no longer active
    for (const type of prevTypes) {
      if (!newTypes.has(type as IndicatorType)) {
        const paneId = indicatorPaneMapRef.current.get(type);
        if (paneId) {
          try { chart.removeIndicator(paneId, type); } catch (_) {}
          indicatorPaneMapRef.current.delete(type);
        }
      }
    }

    // Add new indicators
    for (const ind of activeIndicators) {
      if (!prevTypes.has(ind.type)) {
        try {
          if (OVERLAY_INDICATORS.has(ind.type)) {
            // Overlay on main candle pane
            chart.createIndicator(ind.type, false, { id: 'candle_pane' });
            indicatorPaneMapRef.current.set(ind.type, 'candle_pane');
          } else {
            // New sub-pane
            const paneId = chart.createIndicator(ind.type, false, { height: 80 });
            if (paneId) {
              indicatorPaneMapRef.current.set(ind.type, paneId);
            }
          }
        } catch (e) {
          console.warn(`Failed to add indicator ${ind.type}:`, e);
        }
      }
    }

    prevIndicatorsRef.current = new Set(newTypes) as Set<string>;
  }, [activeIndicators]);

  /* ─── Drawing tool ─── */
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart) return;

    // Non-drawing tools: do nothing
    if (drawingTool === 'cursor' || drawingTool === 'crosshair' || drawingTool === 'eraser') {
      return;
    }

    // Create an overlay — KLineChart enters drawing mode and handles all interaction
    chart.createOverlay({
      name: drawingTool,
      mode: 'weak_magnet',
      onDrawEnd: (_event: any) => {
        // Reset tool to cursor after drawing is placed
        onDrawingCompleteRef.current?.();
        return false;
      },
    });
  }, [drawingTool]);

  /* ─── Clear all drawings ─── */
  useEffect(() => {
    if (!onClearDrawings) return;
    try { chartRef.current?.removeOverlay(); } catch (_) {}
  }, [onClearDrawings]);

  /* ─── Crosshair data callback ─── */
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !onCrosshairData) return;

    const handler = (data: any) => {
      const k = data?.klineData;
      if (k) {
        const change = k.close - k.open;
        const changePct = k.open ? (change / k.open) * 100 : 0;
        onCrosshairData({
          time: k.timestamp / 1000,
          open: k.open,
          high: k.high,
          low: k.low,
          close: k.close,
          volume: k.volume || 0,
          change,
          changePct,
          ma5: null,  // KLineChart shows MA values in its own tooltip
          ma10: null,
          ma30: null,
        });
      } else {
        onCrosshairData(null);
      }
    };

    chart.subscribeAction('onCrosshairChange', handler);
    return () => {
      try { chart.unsubscribeAction('onCrosshairChange', handler); } catch (_) {}
    };
  }, [onCrosshairData]);

  /* ─── Resize handling ─── */
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || Platform.OS !== 'web') return;

    const handleResize = () => chart.resize();
    window.addEventListener('resize', handleResize);

    // Delayed initial resize to ensure container is laid out
    const timer = setTimeout(() => chart.resize(), 100);

    // Also observe container size changes
    let ro: ResizeObserver | null = null;
    if (containerRef.current && typeof ResizeObserver !== 'undefined') {
      ro = new ResizeObserver(() => chart.resize());
      ro.observe(containerRef.current);
    }

    return () => {
      window.removeEventListener('resize', handleResize);
      clearTimeout(timer);
      ro?.disconnect();
    };
  }, []);

  /* ─── Native fallback ─── */
  if (Platform.OS !== 'web') {
    return (
      <View style={styles.placeholder}>
        <Text style={styles.placeholderText}>K线图表 (Native 版本待实现)</Text>
        <Text style={styles.placeholderSub}>{symbol}</Text>
      </View>
    );
  }

  /* ─── Web render ─── */
  return (
    <div
      ref={containerRef}
      style={{
        width: '100%',
        height: '100%',
        backgroundColor: '#0a0a0a',
      }}
    />
  );
}

/* ═══════════════════════════════════════════
   Styles
   ═══════════════════════════════════════════ */

const styles = StyleSheet.create({
  placeholder: {
    flex: 1,
    backgroundColor: '#0a0a0a',
    justifyContent: 'center',
    alignItems: 'center',
  },
  placeholderText: {
    color: Colors.textMuted,
    fontSize: 16,
  },
  placeholderSub: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
  },
});
