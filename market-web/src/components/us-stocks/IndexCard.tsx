import React from 'react';
import type { IndexCardData } from '../../types/stocks';

const UP = '#22C55E';
const DOWN = '#EF4444';

function Sparkline({ data, up }: { data: number[]; up: boolean }) {
  if (!data.length) return null;
  const color = up ? UP : DOWN;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const w = 80;
  const h = 28;
  const step = data.length > 1 ? w / (data.length - 1) : 0;
  const points = data.map((y, i) => `${i * step},${h - ((y - min) / range) * h}`).join(' ');
  return (
    <svg width={w} height={h} className="shrink-0">
      <polyline fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" points={points} />
    </svg>
  );
}

export function UsIndexCard({ data }: { data: IndexCardData }) {
  const up = data.changePercent >= 0;
  const color = up ? UP : DOWN;
  return (
    <div
      className="rounded-2xl p-4 bg-[#111827] border flex flex-col gap-2 min-w-0"
      style={{ borderColor: 'rgba(255,255,255,0.06)', borderRadius: '16px' }}
    >
      <div className="text-white/6 text-sm" style={{ color: 'rgba(255,255,255,0.6)' }}>
        {data.name} ({data.symbol})
      </div>
      <div className="font-mono text-lg font-semibold text-white" style={{ fontFamily: 'JetBrains Mono, ui-monospace, monospace' }}>
        {data.value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
      </div>
      <div className="flex items-center gap-2" style={{ color }}>
        <span className="font-mono text-sm">
          {data.changePercent >= 0 ? '+' : ''}{data.changePercent.toFixed(2)}%
        </span>
        <Sparkline data={data.sparkline} up={up} />
      </div>
    </div>
  );
}
