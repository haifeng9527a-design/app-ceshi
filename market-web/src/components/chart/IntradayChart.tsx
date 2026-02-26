import React, { useEffect, useRef, useCallback } from 'react';
import { createChart, LineStyle, type IChartApi, type ISeriesApi } from 'lightweight-charts';
import { formatTimeChart } from '../../utils/format';
import type { IntradayPoint } from '../../types/chart';

const GREEN = '#22C55E';
const GRID = 'rgba(255,255,255,0.08)';
const BORDER = 'rgba(255,255,255,0.06)';
const TEXT = 'rgba(255,255,255,0.6)';

export function IntradayChart({
  data,
  prevClose,
  height = 560,
  className = '',
}: {
  data: IntradayPoint[];
  prevClose: number;
  height?: number;
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const areaRef = useRef<ISeriesApi<'Area'> | null>(null);
  const pctRef = useRef<ISeriesApi<'Line'> | null>(null);
  const volRef = useRef<ISeriesApi<'Histogram'> | null>(null);

  const onCrosshair = useCallback(
    (param: { time?: unknown; point?: { x: number; y: number }; seriesData: Map<ISeriesApi, unknown> }) => {
      const tip = tooltipRef.current;
      if (!tip || !param.point || !param.time) {
        if (tip) tip.style.display = 'none';
        return;
      }
      const area = areaRef.current;
      const raw = area && param.seriesData.get(area);
      const price = raw && typeof raw === 'object' && 'value' in raw ? (raw as { value: number }).value : null;
      if (price == null) {
        tip.style.display = 'none';
        return;
      }
      const time = param.time as number;
      const pct = prevClose ? ((price - prevClose) / prevClose) * 100 : 0;
      tip.innerHTML = `
        <div style="color:rgba(255,255,255,0.55);font-size:11px">${formatTimeChart(time, 'time')}</div>
        <div style="color:rgba(255,255,255,0.92);font-family:JetBrains Mono">${price.toFixed(2)}</div>
        <div style="color:${pct >= 0 ? GREEN : '#EF4444'};font-size:11px">${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%</div>
      `;
      tip.style.display = 'block';
      tip.style.left = `${param.point.x + 12}px`;
      tip.style.top = `${param.point.y}px`;
    },
    [prevClose]
  );

  useEffect(() => {
    if (!containerRef.current || !data.length) return;

    const chart = createChart(containerRef.current, {
      layout: { background: { color: '#0B0F14' }, textColor: TEXT },
      grid: { vertLines: { color: 'rgba(255,255,255,0.04)' }, horzLines: { color: GRID, style: LineStyle.Dashed } },
      width: containerRef.current.clientWidth,
      height,
      rightPriceScale: { borderColor: BORDER, scaleMargins: { top: 0.1, bottom: 0.25 } },
      timeScale: { borderColor: BORDER, timeVisible: true, secondsVisible: false },
      crosshair: { vertLine: { labelVisible: true }, horzLine: { labelVisible: true } },
    });

    const areaSeries = chart.addAreaSeries({
      priceScaleId: 'left',
      lineColor: GREEN,
      topColor: GREEN + '40',
      bottomColor: GREEN + '00',
      lineWidth: 2,
    });
    const areaData = data.map((d) => ({ time: d.time as any, value: d.price }));
    areaSeries.setData(areaData);
    areaSeries.priceScale().applyOptions({ borderColor: BORDER });

    const pctSeries = chart.addLineSeries({
      priceScaleId: 'right',
      lineColor: 'transparent',
      lineWidth: 0,
      lastValueVisible: false,
      priceLineVisible: false,
    });
    const pctData = data.map((d) => ({
      time: d.time as any,
      value: prevClose ? ((d.price - prevClose) / prevClose) * 100 : 0,
    }));
    pctSeries.setData(pctData);
    pctSeries.priceScale().applyOptions({
      borderColor: BORDER,
      scaleMargins: { top: 0.1, bottom: 0.25 },
      priceFormatter: (v: number) => (v >= 0 ? '+' : '') + v.toFixed(2) + '%',
    });
    pctRef.current = pctSeries;

    const volSeries = chart.addHistogramSeries({
      priceScaleId: 'volume',
      priceFormat: { type: 'volume' },
    });
    volSeries.priceScale().applyOptions({
      scaleMargins: { top: 0.85, bottom: 0 },
      borderVisible: false,
    });
    volSeries.applyOptions({ color: 'rgba(255,255,255,0.15)' });
    const volData = data.map((d) => ({ time: d.time as any, value: d.volume, color: 'rgba(34,197,94,0.4)' }));
    volSeries.setData(volData);

    chartRef.current = chart;
    areaRef.current = areaSeries;
    volRef.current = volSeries;

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
      areaRef.current = null;
      pctRef.current = null;
      volRef.current = null;
    };
  }, [data.length, height, onCrosshair, prevClose]);

  useEffect(() => {
    if (!areaRef.current || !volRef.current || !pctRef.current || !data.length) return;
    const areaData = data.map((d) => ({ time: d.time as any, value: d.price }));
    const pctData = data.map((d) => ({
      time: d.time as any,
      value: prevClose ? ((d.price - prevClose) / prevClose) * 100 : 0,
    }));
    const volData = data.map((d) => ({ time: d.time as any, value: d.volume, color: 'rgba(34,197,94,0.4)' }));
    areaRef.current.setData(areaData);
    pctRef.current.setData(pctData);
    volRef.current.setData(volData);
  }, [data, prevClose]);

  return (
    <div className={`relative ${className}`} style={{ background: '#0B0F14' }}>
      <div ref={containerRef} style={{ width: '100%', height }} />
      <div
        ref={tooltipRef}
        className="pointer-events-none absolute z-10 px-2 py-1.5 rounded shadow-lg border"
        style={{
          display: 'none',
          background: '#0F1722',
          borderColor: BORDER,
          fontSize: 12,
        }}
      />
    </div>
  );
}
