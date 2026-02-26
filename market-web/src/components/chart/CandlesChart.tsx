import React, { useEffect, useRef, useCallback } from 'react';
import { createChart, LineStyle, type IChartApi, type ISeriesApi } from 'lightweight-charts';
import { formatTimeChart } from '../../utils/format';
import { computeMA, macd } from '../../utils/indicators';
import type { CandlePoint } from '../../types/chart';

const UP = '#22C55E';
const DOWN = '#EF4444';
const GRID = 'rgba(255,255,255,0.08)';
const BORDER = 'rgba(255,255,255,0.06)';
const TEXT = 'rgba(255,255,255,0.6)';
const MA5 = '#D6B46A';
const MA10 = '#5B8DEE';
const MA20 = '#ED6BF5';

export function CandlesChart({
  data,
  height = 560,
  showMA = true,
  className = '',
}: {
  data: CandlePoint[];
  height?: number;
  showMA?: boolean;
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const candleRef = useRef<ISeriesApi<'Candlestick'> | null>(null);
  const volRef = useRef<ISeriesApi<'Histogram'> | null>(null);
  const difRef = useRef<ISeriesApi<'Line'> | null>(null);
  const deaRef = useRef<ISeriesApi<'Line'> | null>(null);
  const macdBarRef = useRef<ISeriesApi<'Histogram'> | null>(null);
  const ma5Ref = useRef<ISeriesApi<'Line'> | null>(null);
  const ma10Ref = useRef<ISeriesApi<'Line'> | null>(null);
  const ma20Ref = useRef<ISeriesApi<'Line'> | null>(null);

  const onCrosshair = useCallback((param: { time?: unknown; point?: { x: number; y: number }; seriesData: Map<ISeriesApi, unknown> }) => {
    const tip = tooltipRef.current;
    if (!tip || !param.point || !param.time) {
      if (tip) tip.style.display = 'none';
      return;
    }
    const candle = data.find((d) => d.time === (param.time as number));
    if (!candle) {
      tip.style.display = 'none';
      return;
    }
    const pct = candle.open ? ((candle.close - candle.open) / candle.open) * 100 : 0;
    tip.innerHTML = `
      <div style="color:rgba(255,255,255,0.55);font-size:11px">${formatTimeChart(candle.time, 'date')} ${formatTimeChart(candle.time, 'time')}</div>
      <div>开 ${candle.open.toFixed(2)} 高 ${candle.high.toFixed(2)} 低 ${candle.low.toFixed(2)} 收 ${candle.close.toFixed(2)}</div>
      <div style="color:${pct >= 0 ? UP : DOWN};font-size:11px">${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%</div>
    `;
    tip.style.display = 'block';
    tip.style.left = `${param.point.x + 12}px`;
    tip.style.top = `${param.point.y}px`;
  }, [data]);

  useEffect(() => {
    if (!containerRef.current || !data.length) return;

    const chart = createChart(containerRef.current, {
      layout: { background: { color: '#0B0F14' }, textColor: TEXT },
      grid: { vertLines: { color: 'rgba(255,255,255,0.04)' }, horzLines: { color: GRID, style: LineStyle.Dashed } },
      width: containerRef.current.clientWidth,
      height,
      rightPriceScale: { borderColor: BORDER, scaleMargins: { top: 0.05, bottom: 0.45 } },
      timeScale: { borderColor: BORDER },
      crosshair: { vertLine: { labelVisible: true }, horzLine: { labelVisible: true } },
    });

    const candleSeries = chart.addCandlestickSeries({
      priceScaleId: 'right',
      upColor: UP,
      downColor: DOWN,
      borderVisible: false,
    });
    const candleData = data.map((d) => ({ time: d.time as any, open: d.open, high: d.high, low: d.low, close: d.close }));
    candleSeries.setData(candleData);
    candleRef.current = candleSeries;

    if (showMA) {
      const maData = computeMA(data);
      const ma5Series = chart.addLineSeries({ priceScaleId: 'right', color: MA5, lineWidth: 1 });
      ma5Series.setData(maData.filter((m) => m.ma5 > 0).map((m) => ({ time: m.time as any, value: m.ma5 })));
      ma5Ref.current = ma5Series;
      const ma10Series = chart.addLineSeries({ priceScaleId: 'right', color: MA10, lineWidth: 1 });
      ma10Series.setData(maData.filter((m) => m.ma10 > 0).map((m) => ({ time: m.time as any, value: m.ma10 })));
      ma10Ref.current = ma10Series;
      const ma20Series = chart.addLineSeries({ priceScaleId: 'right', color: MA20, lineWidth: 1 });
      ma20Series.setData(maData.filter((m) => m.ma20 > 0).map((m) => ({ time: m.time as any, value: m.ma20 })));
      ma20Ref.current = ma20Series;
    }

    const volSeries = chart.addHistogramSeries({ priceScaleId: 'volume' });
    volSeries.priceScale().applyOptions({ scaleMargins: { top: 0.55, bottom: 0.25 }, borderVisible: false });
    volSeries.applyOptions({ priceFormat: { type: 'volume' } });
    const volData = data.map((d) => ({
      time: d.time as any,
      value: d.volume,
      color: d.close >= d.open ? 'rgba(34,197,94,0.5)' : 'rgba(239,68,68,0.5)',
    }));
    volSeries.setData(volData);
    volRef.current = volSeries;

    const { dif, dea, bar } = macd(data.map((c) => c.close));
    const difSeries = chart.addLineSeries({ priceScaleId: 'macd', color: MA5, lineWidth: 1 });
    difSeries.priceScale().applyOptions({ scaleMargins: { top: 0.8, bottom: 0.05 }, borderVisible: false });
    difSeries.setData(
      data.map((c, i) => ({ time: c.time as any, value: dif[i] ?? 0 })).filter((d) => d.value != null && Number.isFinite(d.value))
    );
    difRef.current = difSeries;
    const deaSeries = chart.addLineSeries({ priceScaleId: 'macd', color: MA10, lineWidth: 1 });
    deaSeries.setData(
      data.map((c, i) => ({ time: c.time as any, value: dea[i] ?? 0 })).filter((d) => d.value != null && Number.isFinite(d.value))
    );
    deaRef.current = deaSeries;
    const macdBarSeries = chart.addHistogramSeries({ priceScaleId: 'macd' });
    macdBarSeries.setData(
      data.map((c, i) => ({
        time: c.time as any,
        value: bar[i] ?? 0,
        color: (bar[i] ?? 0) >= 0 ? 'rgba(34,197,94,0.4)' : 'rgba(239,68,68,0.4)',
      }))
    );
    macdBarRef.current = macdBarSeries;

    chartRef.current = chart;
    const unsub = chart.subscribeCrosshairMove(onCrosshair);
    const ro = new ResizeObserver((entries) => {
      if (entries[0]) chart.applyOptions({ width: entries[0].contentRect.width });
    });
    ro.observe(containerRef.current);

    return () => {
      unsub();
      ro.disconnect();
      chart.remove();
      chartRef.current = null;
      candleRef.current = null;
      volRef.current = null;
      difRef.current = null;
      deaRef.current = null;
      macdBarRef.current = null;
      ma5Ref.current = null;
      ma10Ref.current = null;
      ma20Ref.current = null;
    };
  }, [data.length, height, showMA, onCrosshair]);

  useEffect(() => {
    if (!data.length) return;
    const candleData = data.map((d) => ({ time: d.time as any, open: d.open, high: d.high, low: d.low, close: d.close }));
    candleRef.current?.setData(candleData);
    const volData = data.map((d) => ({
      time: d.time as any,
      value: d.volume,
      color: d.close >= d.open ? 'rgba(34,197,94,0.5)' : 'rgba(239,68,68,0.5)',
    }));
    volRef.current?.setData(volData);
    const maData = computeMA(data);
    ma5Ref.current?.setData(maData.filter((m) => m.ma5 > 0).map((m) => ({ time: m.time as any, value: m.ma5 })));
    ma10Ref.current?.setData(maData.filter((m) => m.ma10 > 0).map((m) => ({ time: m.time as any, value: m.ma10 })));
    ma20Ref.current?.setData(maData.filter((m) => m.ma20 > 0).map((m) => ({ time: m.time as any, value: m.ma20 })));
    const { dif, dea, bar } = macd(data.map((c) => c.close));
    difRef.current?.setData(
      data.map((c, i) => ({ time: c.time as any, value: dif[i] ?? 0 })).filter((d) => d.value != null && Number.isFinite(d.value))
    );
    deaRef.current?.setData(
      data.map((c, i) => ({ time: c.time as any, value: dea[i] ?? 0 })).filter((d) => d.value != null && Number.isFinite(d.value))
    );
    macdBarRef.current?.setData(
      data.map((c, i) => ({
        time: c.time as any,
        value: bar[i] ?? 0,
        color: (bar[i] ?? 0) >= 0 ? 'rgba(34,197,94,0.4)' : 'rgba(239,68,68,0.4)',
      }))
    );
  }, [data]);

  return (
    <div className={`relative ${className}`} style={{ background: '#0B0F14' }}>
      <div ref={containerRef} style={{ width: '100%', height }} />
      <div
        ref={tooltipRef}
        className="pointer-events-none absolute z-10 px-2 py-1.5 rounded shadow-lg border font-mono text-xs"
        style={{ display: 'none', background: '#0F1722', borderColor: BORDER }}
      />
    </div>
  );
}
