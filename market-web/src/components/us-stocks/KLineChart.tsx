import React, { useEffect, useRef } from 'react';
import { createChart, type IChartApi, type ISeriesApi } from 'lightweight-charts';
import type { KLinePoint } from '../../types/stocks';

const PERIODS = ['1D', '5D', '1M', '3M', '1Y'];

export function KLineChart({
  data,
  period,
  onPeriodChange,
}: {
  data: KLinePoint[];
  period: string;
  onPeriodChange: (p: string) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const seriesRef = useRef<ISeriesApi<'Candlestick'> | null>(null);

  useEffect(() => {
    if (!containerRef.current || !data.length) return;
    const chart = createChart(containerRef.current, {
      layout: { background: { color: '#111827' }, textColor: 'rgba(255,255,255,0.6)' },
      grid: { vertLines: { color: 'rgba(255,255,255,0.06)' }, horzLines: { color: 'rgba(255,255,255,0.06)' } },
      width: containerRef.current.clientWidth,
      height: 280,
      rightPriceScale: { borderColor: 'rgba(255,255,255,0.06)' },
      timeScale: { borderColor: 'rgba(255,255,255,0.06)' },
    });
    const candlestick = chart.addCandlestickSeries({
      upColor: '#22C55E',
      downColor: '#EF4444',
      borderVisible: false,
    });
    const seriesData = data.map(({ time, open, high, low, close }) => ({ time: time as any, open, high, low, close }));
    candlestick.setData(seriesData);
    chartRef.current = chart;
    seriesRef.current = candlestick;
    return () => {
      chart.remove();
      chartRef.current = null;
      seriesRef.current = null;
    };
  }, [data.length]);

  useEffect(() => {
    if (!seriesRef.current || !data.length) return;
    const seriesData = data.map(({ time, open, high, low, close }) => ({ time: time as any, open, high, low, close }));
    seriesRef.current.setData(seriesData);
  }, [data]);

  return (
    <div className="rounded-2xl border overflow-hidden bg-[#111827]" style={{ borderColor: 'rgba(255,255,255,0.06)', borderRadius: '16px' }}>
      <div className="flex gap-2 p-2 border-b" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
        {PERIODS.map((p) => (
          <button
            key={p}
            type="button"
            onClick={() => onPeriodChange(p)}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium ${period === p ? 'bg-amber-500/20 text-amber-400' : 'text-white/6 hover:text-white'}`}
          >
            {p}
          </button>
        ))}
      </div>
      <div ref={containerRef} className="w-full" style={{ height: 280 }} />
    </div>
  );
}
