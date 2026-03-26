import React from 'react';

const GOLD = '#D6B46A';
const BORDER = 'rgba(255,255,255,0.06)';

export function IndicatorsPanel({
  maType,
  onMaTypeChange,
  className = '',
}: {
  maType: 'MA' | 'EMA';
  onMaTypeChange: (t: 'MA' | 'EMA') => void;
  className?: string;
}) {
  return (
    <div
      className={`rounded-2xl border ${className}`}
      style={{
        background: '#0F1722',
        borderColor: BORDER,
        borderRadius: 16,
      }}
    >
      <div className="border-b px-4 py-3" style={{ borderColor: BORDER }}>
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-sm" style={{ color: 'rgba(255,255,255,0.55)' }}>指标</span>
          <div className="flex rounded-xl overflow-hidden border" style={{ borderColor: BORDER }}>
            {(['MA', 'EMA'] as const).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => onMaTypeChange(t)}
                className="px-4 py-2 text-sm font-medium transition-colors"
                style={
                  maType === t
                    ? { background: GOLD, color: '#0B0F14' }
                    : { color: 'rgba(255,255,255,0.7)' }
                }
              >
                {t}
              </button>
            ))}
          </div>
        </div>
      </div>
      <div className="px-4 py-3 grid grid-cols-1 gap-2 text-sm" style={{ color: 'rgba(255,255,255,0.55)' }}>
        <div className="flex items-center gap-2">
          <span>MA</span>
          <span className="font-mono text-xs">MA5 MA10 MA20（主图均线）</span>
        </div>
        <div className="flex items-center gap-2">
          <span>VOL</span>
          <span className="font-mono text-xs">成交量柱状 + 量均线（可选）</span>
        </div>
        <div className="flex items-center gap-2">
          <span>MACD</span>
          <span className="font-mono text-xs">DIF / DEA / 柱状</span>
        </div>
      </div>
    </div>
  );
}
