import React from 'react';
import { ChevronLeft } from 'lucide-react';
import { formatPrice, formatChange, formatPercent } from '../../utils/format';

const UP = '#22C55E';
const DOWN = '#EF4444';
const GOLD = '#D6B46A';

export function TopBar({
  symbol,
  price,
  change,
  changePercent,
  activeTab,
  onTabChange,
  onBack,
}: {
  symbol: string;
  price: number;
  change: number;
  changePercent: number;
  activeTab: 'intraday' | 'kline';
  onTabChange: (t: 'intraday' | 'kline') => void;
  onBack: () => void;
}) {
  const up = change >= 0;
  const color = up ? UP : DOWN;

  return (
    <header
      className="h-16 shrink-0 flex items-center justify-between px-6 border-b"
      style={{
        background: '#0B0F14',
        borderColor: 'rgba(255,255,255,0.06)',
        color: 'rgba(255,255,255,0.92)',
      }}
    >
      <div className="flex items-center gap-4">
        <button
          type="button"
          onClick={onBack}
          className="p-2 rounded-lg hover:bg-white/5 text-white/8 hover:text-white transition-colors"
          aria-label="返回"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>
        <span className="font-semibold text-lg font-mono">{symbol}</span>
      </div>

      <nav className="flex gap-1">
        {(
          [
            { id: 'intraday' as const, label: '分时' },
            { id: 'kline' as const, label: 'K线' },
          ]
        ).map(({ id, label }) => (
          <button
            key={id}
            type="button"
            onClick={() => onTabChange(id)}
            className="px-5 py-2.5 text-sm font-medium relative"
            style={{ color: activeTab === id ? 'rgba(255,255,255,0.92)' : 'rgba(255,255,255,0.55)' }}
          >
            {label}
            {activeTab === id && (
              <span
                className="absolute bottom-0 left-1/2 -translate-x-1/2 w-8 h-0.5 rounded-full"
                style={{ backgroundColor: GOLD }}
              />
            )}
          </button>
        ))}
      </nav>

      <div className="flex items-center gap-3 font-mono">
        <span style={{ color: 'rgba(255,255,255,0.92)', fontSize: '1rem' }}>{formatPrice(price)}</span>
        <span style={{ color }}>{formatChange(change)}</span>
        <span style={{ color }}>({formatPercent(changePercent)})</span>
      </div>
    </header>
  );
}
