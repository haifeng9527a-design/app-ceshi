import React from 'react';
import type { OrderBookLevel } from '../../types/stocks';

const UP = '#22C55E';
const DOWN = '#EF4444';

export function OrderBook({ bids, asks }: { bids: OrderBookLevel[]; asks: OrderBookLevel[] }) {
  return (
    <div className="rounded-2xl border overflow-hidden bg-[#111827]" style={{ borderColor: 'rgba(255,255,255,0.06)', borderRadius: '16px' }}>
      <div className="flex border-b" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
        <button type="button" className="flex-1 py-2 text-sm font-medium text-amber-400 border-b-2 border-amber-400">买盘</button>
        <button type="button" className="flex-1 py-2 text-sm font-medium text-white/6 hover:text-white">卖盘</button>
      </div>
      <div className="grid grid-cols-3 gap-2 p-3 text-xs font-mono" style={{ fontFamily: 'JetBrains Mono, ui-monospace, monospace' }}>
        <div style={{ color: 'rgba(255,255,255,0.5)' }}>档位</div>
        <div style={{ color: 'rgba(255,255,255,0.5)' }}>价格</div>
        <div style={{ color: 'rgba(255,255,255,0.5)' }}>数量</div>
        {bids.slice(0, 5).map((b, i) => (
          <React.Fragment key={i}>
            <div className="text-white/7">买{i + 1}</div>
            <div style={{ color: UP }}>{b.price.toFixed(2)}</div>
            <div className="text-white/8">{b.quantity.toLocaleString()}</div>
          </React.Fragment>
        ))}
        {asks.slice(0, 5).map((a, i) => (
          <React.Fragment key={i}>
            <div className="text-white/7">卖{i + 1}</div>
            <div style={{ color: DOWN }}>{a.price.toFixed(2)}</div>
            <div className="text-white/8">{a.quantity.toLocaleString()}</div>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}
