import React from 'react';
import { Bell, Search } from 'lucide-react';

const TABS = [
  { key: 'market', label: '行情' },
  { key: 'us', label: '美股' },
  { key: 'forex', label: '外汇' },
  { key: 'crypto', label: '加密货币' },
];

export function TopNavbar() {
  const [active, setActive] = React.useState('us');
  return (
    <header
      className="h-14 flex items-center px-6 bg-[#0B0F14] border-b shrink-0"
      style={{ borderColor: 'rgba(255,255,255,0.06)' }}
    >
      <div className="flex items-center gap-6">
        <div className="flex items-center gap-2 text-white font-semibold">
          <div className="w-8 h-8 rounded-lg bg-amber-500/20 flex items-center justify-center text-amber-400">L</div>
          <span>LOGO</span>
        </div>
        <nav className="flex gap-1">
          {TABS.map(({ key, label }) => (
            <button
              key={key}
              type="button"
              onClick={() => setActive(key)}
              className={`
                px-4 py-2 rounded-lg text-sm font-medium transition-colors
                ${active === key ? 'bg-amber-500/15 text-amber-400 border-b-2 border-amber-400' : 'text-white/70 hover:text-white hover:bg-white/5'}
              `}
            >
              {label}
            </button>
          ))}
        </nav>
      </div>
      <div className="ml-auto flex items-center gap-4">
        <button type="button" className="p-2 rounded-lg text-white/6 hover:bg-white/5" aria-label="搜索">
          <Search className="w-5 h-5" style={{ color: 'rgba(255,255,255,0.6)' }} />
        </button>
        <button type="button" className="p-2 rounded-lg text-white/6 hover:bg-white/5" aria-label="通知">
          <Bell className="w-5 h-5" style={{ color: 'rgba(255,255,255,0.6)' }} />
        </button>
        <div className="w-9 h-9 rounded-full bg-white/10 flex items-center justify-center text-white font-semibold text-sm">
          F
        </div>
      </div>
    </header>
  );
}
