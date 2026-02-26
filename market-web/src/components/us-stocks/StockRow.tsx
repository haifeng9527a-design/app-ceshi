import React from 'react';
import type { StockRowData } from '../../types/stocks';

const UP = '#22C55E';
const DOWN = '#EF4444';

function volFmt(n: number): string {
  if (n >= 1e9) return (n / 1e9).toFixed(2) + 'B';
  if (n >= 1e6) return (n / 1e6).toFixed(2) + 'M';
  if (n >= 1e4) return (n / 1e4).toFixed(2) + '万';
  return n.toLocaleString();
}

function cell(v: number | null | undefined, color?: string) {
  if (v == null) return '—';
  const s = typeof v === 'number' && (v > 1e4 || (v < 0.01 && v > 0)) ? v.toFixed(4) : v.toLocaleString('en-US', { maximumFractionDigits: 2 });
  return <span style={color ? { color } : undefined}>{s}</span>;
}

export function StockRow({
  data,
  index,
  selected,
  onSelect,
}: {
  data: StockRowData;
  index: number;
  selected: boolean;
  onSelect: () => void;
}) {
  const up = data.changePercent >= 0;
  const color = up ? UP : DOWN;
  return (
    <tr
      onClick={onSelect}
      className={`
        border-b cursor-pointer transition-colors font-mono text-sm
        ${selected ? 'bg-amber-500/10' : 'hover:bg-white/5'}
      `}
      style={{
        borderColor: 'rgba(255,255,255,0.06)',
        fontFamily: 'JetBrains Mono, ui-monospace, monospace',
      }}
    >
      <td className="py-3 px-3 text-white/6 w-12" style={{ color: 'rgba(255,255,255,0.6)' }}>{index}</td>
      <td className="py-3 px-3 text-white font-medium">{data.code}</td>
      <td className="py-3 px-3 text-white">{data.name}</td>
      <td className="py-3 px-3" style={{ color }}>{data.changePercent >= 0 ? '+' : ''}{data.changePercent.toFixed(2)}%</td>
      <td className="py-3 px-3 text-white">{cell(data.price)}</td>
      <td className="py-3 px-3" style={{ color }}>{data.change >= 0 ? '+' : ''}{data.change.toFixed(2)}</td>
      <td className="py-3 px-3 text-white/8">{volFmt(data.volume)}</td>
      <td className="py-3 px-3 text-white/8">{volFmt(data.amount)}</td>
      <td className="py-3 px-3 text-white/8">{cell(data.peTtm)}</td>
      <td className="py-3 px-3 text-white/8">{cell(data.pb)}</td>
      <td className="py-3 px-3 text-white/8">{data.dividendYield != null ? (data.dividendYield * 100).toFixed(2) + '%' : '—'}</td>
    </tr>
  );
}
