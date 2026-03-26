import React, { useState } from 'react';
import { Settings } from 'lucide-react';
import { KLineChart } from './KLineChart';
import { OrderBook } from './OrderBook';
import type { StockRowData } from '../../types/stocks';
import type { KLinePoint, OrderBookLevel } from '../../types/stocks';
import { klineMock, orderBookMock } from '../../constants/stocksMock';

const UP = '#22C55E';
const DOWN = '#EF4444';

export function StockDetailPanel({ stock }: { stock: StockRowData | null }) {
  const [klinePeriod, setKlinePeriod] = useState('1D');
  const klineData = React.useMemo(() => (stock ? klineMock(stock.code) : []), [stock?.code]);
  const orderBook = React.useMemo(() => (stock ? orderBookMock(stock.price) : { bids: [], asks: [] }), [stock?.price]);

  if (!stock) {
    return (
      <div
        className="w-[380px] flex flex-col items-center justify-center text-white/5 bg-[#0B0F14] border-l shrink-0"
        style={{ borderColor: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.4)' }}
      >
        <p className="text-sm">点击左侧股票查看详情</p>
      </div>
    );
  }

  const up = stock.changePercent >= 0;
  const color = up ? UP : DOWN;

  return (
    <div
      className="w-[380px] flex flex-col overflow-auto bg-[#0B0F14] border-l shrink-0 p-4 gap-4"
      style={{ borderColor: 'rgba(255,255,255,0.06)' }}
    >
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-white font-semibold text-lg">{stock.name}</h2>
            <button type="button" className="p-1 rounded text-white/5 hover:bg-white/5">
              <Settings className="w-4 h-4" />
            </button>
          </div>
          <p className="text-white/6 text-sm mt-0.5" style={{ color: 'rgba(255,255,255,0.6)' }}>{stock.code}</p>
        </div>
      </div>
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-2xl font-semibold text-white" style={{ fontFamily: 'JetBrains Mono, ui-monospace, monospace' }}>
          {stock.price.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
        </span>
        <span style={{ color }} className="font-mono text-sm">
          {stock.change >= 0 ? '+' : ''}{stock.change.toFixed(2)} {stock.changePercent >= 0 ? '+' : ''}{stock.changePercent.toFixed(2)}%
        </span>
      </div>
      <p className="text-xs text-white/5" style={{ color: 'rgba(255,255,255,0.5)' }}>收盘 ET 02/23 16:00:00 (美东)</p>

      <div className="flex gap-2 border-b pb-2" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
        {['评说', '详情', '分析', '资讯'].map((label, i) => (
          <button
            key={label}
            type="button"
            className={`px-3 py-1.5 rounded-lg text-sm ${i === 0 ? 'bg-amber-500/15 text-amber-400' : 'text-white/6 hover:text-white'}`}
          >
            {label}
          </button>
        ))}
      </div>

      <KLineChart data={klineData} period={klinePeriod} onPeriodChange={setKlinePeriod} />
      <OrderBook bids={orderBook.bids} asks={orderBook.asks} />
    </div>
  );
}
