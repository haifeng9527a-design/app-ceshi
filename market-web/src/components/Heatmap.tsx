import React from 'react';
import { formatPrice, formatPercent } from '@/utils/format';
import { colorByChange } from '@/utils/colors';
import type { HeatmapItem } from '@/constants/mock';

interface HeatmapProps {
  items: HeatmapItem[];
  className?: string;
}

/**
 * 用 div grid 模拟 treemap：至少 12 块，块内 ticker、价格、涨跌幅；绿红深浅由涨跌幅决定
 */
export function Heatmap({ items, className = '' }: HeatmapProps) {
  const totalWeight = items.reduce((s, i) => s + i.weight, 0);
  return (
    <div
      className={`grid gap-1 grid-cols-4 grid-rows-3 auto-rows-fr ${className}`}
      style={{ gridTemplateColumns: 'repeat(4, 1fr)', gridTemplateRows: 'repeat(3, 1fr)' }}
    >
      {items.slice(0, 12).map((item) => {
        const color = colorByChange(item.changePercent);
        const intensity = Math.min(1, Math.abs(item.changePercent) / 10);
        const bg = item.changePercent >= 0
          ? `rgba(34, 197, 94, ${0.15 + intensity * 0.35})`
          : `rgba(239, 68, 68, ${0.15 + intensity * 0.35})`;
        const size = totalWeight > 0 ? (item.weight / totalWeight) * 100 : 8;
        return (
          <div
            key={item.symbol}
            className="rounded-lg border border-white/10 flex flex-col justify-center p-2 min-h-[64px] hover:border-white/20 transition-colors"
            style={{
              backgroundColor: bg,
              gridColumn: size > 15 ? 'span 1' : undefined,
              gridRow: size > 12 ? 'span 1' : undefined,
            }}
          >
            <div className="font-semibold text-white text-sm">{item.symbol}</div>
            <div className="font-mono text-xs text-white/90">{formatPrice(item.price)}</div>
            <div
              className="font-mono text-xs font-medium"
              style={{ color: item.changePercent >= 0 ? '#22C55E' : '#EF4444' }}
            >
              {formatPercent(item.changePercent)}
            </div>
          </div>
        );
      })}
    </div>
  );
}
