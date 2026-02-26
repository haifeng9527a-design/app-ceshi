import React from 'react';
import { formatPrice, formatChange, formatPercent, formatVol, formatPct } from '../../utils/format';
import type { ChartStats } from '../../types/chart';

const UP = '#22C55E';
const DOWN = '#EF4444';
const LABEL = 'rgba(255,255,255,0.55)';
const VALUE = 'rgba(255,255,255,0.92)';

function Cell({
  label,
  value,
  color,
}: {
  label: string;
  value: string;
  color?: string;
}) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-xs" style={{ color: LABEL }}>{label}</span>
      <span className="font-mono text-sm font-medium" style={{ color: color ?? VALUE }}>{value}</span>
    </div>
  );
}

export function StatsBar({ stats, symbol, price, change, changePercent }: {
  stats: ChartStats;
  symbol: string;
  price: number;
  change: number;
  changePercent: number;
}) {
  const up = stats.change >= 0;
  const color = up ? UP : DOWN;

  return (
    <footer
      className="shrink-0 p-4 border-t"
      style={{
        background: '#0B0F14',
        borderColor: 'rgba(255,255,255,0.06)',
      }}
    >
      <div
        className="rounded-2xl border p-4"
        style={{
          background: '#0F1722',
          borderColor: 'rgba(255,255,255,0.06)',
          borderRadius: 16,
        }}
      >
        <div className="text-center mb-4 font-mono text-sm" style={{ color: VALUE }}>
          <span className="font-semibold">{symbol}</span>
          <span className="mx-2">{formatPrice(price)}</span>
          <span style={{ color }}>{formatChange(change)} ({formatPercent(changePercent)})</span>
        </div>
        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-[repeat(13,minmax(0,1fr))] gap-x-6 gap-y-3">
          <Cell label="开" value={formatPrice(stats.open)} />
          <Cell label="高" value={formatPrice(stats.high)} />
          <Cell label="低" value={formatPrice(stats.low)} />
          <Cell label="收" value={formatPrice(stats.close)} />
          <Cell label="昨收" value={formatPrice(stats.prevClose)} />
          <Cell label="涨跌" value={formatChange(stats.change)} color={color} />
          <Cell label="涨跌幅" value={formatPercent(stats.changePercent)} color={color} />
          <Cell label="振幅" value={formatPct(stats.amplitude)} />
          <Cell label="均价" value={formatPrice(stats.avgPrice)} />
          <Cell label="成交量" value={formatVol(stats.volume)} />
          <Cell label="成交额" value={formatVol(stats.turnover)} />
          <Cell label="换手率" value={formatPct(stats.turnoverRate)} />
          <Cell label="市盈率TTM" value={stats.peTtm != null ? stats.peTtm.toFixed(2) : '--'} />
        </div>
      </div>
    </footer>
  );
}
