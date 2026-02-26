import React from 'react';

const GOLD = '#D6B46A';

const TIMEFRAMES = [
  { id: '1m', label: '1m' },
  { id: '5m', label: '5m' },
  { id: '15m', label: '15m' },
  { id: '1h', label: '1h' },
  { id: '1D', label: '1D' },
] as const;

export type TimeframeId = (typeof TIMEFRAMES)[number]['id'];

export function TimeframeBar({
  value,
  onChange,
  className = '',
}: {
  value: TimeframeId;
  onChange: (v: TimeframeId) => void;
  className?: string;
}) {
  return (
    <div
      className={`flex items-center gap-1 p-1.5 rounded-xl border ${className}`}
      style={{
        background: 'rgba(15, 23, 34, 0.9)',
        borderColor: 'rgba(255,255,255,0.06)',
        borderRadius: 12,
      }}
    >
      {TIMEFRAMES.map(({ id, label }) => (
        <button
          key={id}
          type="button"
          onClick={() => onChange(id)}
          className="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
          style={
            value === id
              ? { background: GOLD, color: '#0B0F14' }
              : { color: 'rgba(255,255,255,0.8)', border: '1px solid transparent' }
          }
        >
          {label}
        </button>
      ))}
    </div>
  );
}

export { TIMEFRAMES };
