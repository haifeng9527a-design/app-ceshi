import React from 'react';
import { Home, TrendingUp, Star, MessageCircle, BarChart3, User, Settings } from 'lucide-react';

const NAV_ITEMS = [
  { key: 'home', icon: Home, label: '首页' },
  { key: 'market', icon: TrendingUp, label: '行情' },
  { key: 'watchlist', icon: Star, label: '自选' },
  { key: 'messages', icon: MessageCircle, label: '消息' },
  { key: 'data', icon: BarChart3, label: '数据' },
  { key: 'user', icon: User, label: '用户' },
];

export function Sidebar() {
  const [active, setActive] = React.useState('market');
  return (
    <aside
      className="w-[72px] flex flex-col items-center py-4 bg-[#0B0F14] border-r border-white/5 shrink-0"
      style={{ borderColor: 'rgba(255,255,255,0.06)' }}
    >
      <div className="mb-6 text-amber-400">
        <TrendingUp className="w-8 h-8" strokeWidth={2} />
      </div>
      <nav className="flex flex-col gap-1">
        {NAV_ITEMS.map(({ key, icon: Icon, label }) => (
          <button
            key={key}
            type="button"
            onClick={() => setActive(key)}
            className={`
              w-12 h-12 rounded-xl flex items-center justify-center transition-colors
              ${active === key ? 'bg-amber-500/20 text-amber-400 border-l-2 border-amber-400' : 'text-white/60 hover:bg-white/5 hover:text-white'}
            `}
            style={active === key ? { borderLeftColor: 'rgba(234,179,8,0.8)' } : undefined}
            title={label}
          >
            <Icon className="w-5 h-5" />
          </button>
        ))}
      </nav>
      <div className="mt-auto pt-4">
        <button
          type="button"
          className="w-12 h-12 rounded-xl flex items-center justify-center text-white/50 hover:bg-white/5 hover:text-white transition-colors"
          title="设置"
        >
          <Settings className="w-5 h-5" />
        </button>
      </div>
    </aside>
  );
}
