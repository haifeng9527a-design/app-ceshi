import React from 'react';
import { Search, Bell, HelpCircle } from 'lucide-react';
import { Tabs, type TabItem } from './Tabs';

const mainTabs: TabItem[] = [
  { key: 'market', label: '行情' },
  { key: 'us', label: '美股' },
  { key: 'forex', label: '外汇' },
  { key: 'crypto', label: '加密货币' },
];

interface NavBarProps {
  activeTab: string;
  onTabChange: (key: string) => void;
  searchValue: string;
  onSearchChange: (v: string) => void;
}

/**
 * 顶部导航栏 64-72px：Logo + Tabs、搜索框、通知 + 头像
 */
export function NavBar({ activeTab, onTabChange, searchValue, onSearchChange }: NavBarProps) {
  return (
    <header
      className="h-[68px] flex items-center px-7 md:px-9 bg-surface border-b border-[rgba(255,255,255,0.06)] shrink-0"
      style={{ paddingLeft: '28px', paddingRight: '36px' }}
    >
      <div className="flex items-center gap-8 mr-6">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-white/10 flex items-center justify-center text-white font-bold text-sm">
            折
          </div>
          <span className="text-white font-semibold text-lg">折买</span>
        </div>
        <Tabs items={mainTabs} activeKey={activeTab} onChange={onTabChange} />
      </div>

      <div className="flex-1 max-w-2xl mx-4">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5" style={{ color: 'rgba(255,255,255,0.5)' }} />
          <input
            type="text"
            placeholder="搜索股票或加密货币..."
            value={searchValue}
            onChange={(e) => onSearchChange(e.target.value)}
            className="w-full h-10 pl-10 pr-4 bg-[#0F1419] border border-[rgba(255,255,255,0.06)] text-white placeholder:opacity-60 focus:outline-none focus:border-up/50"
            style={{ borderRadius: '14px' }}
          />
        </div>
      </div>

      <div className="flex items-center gap-2 ml-4">
        <button
          type="button"
          className="w-10 h-10 rounded-btn flex items-center justify-center text-white/7 hover:bg-white/5 transition-colors"
          aria-label="通知"
        >
          <Bell className="w-5 h-5" style={{ color: 'rgba(255,255,255,0.7)' }} />
        </button>
        <button
          type="button"
          className="w-10 h-10 rounded-btn flex items-center justify-center text-white/7 hover:bg-white/5 transition-colors"
          aria-label="帮助"
        >
          <HelpCircle className="w-5 h-5" style={{ color: 'rgba(255,255,255,0.7)' }} />
        </button>
        <button
          type="button"
          className="w-10 h-10 rounded-full bg-white/10 flex items-center justify-center text-white font-semibold text-sm hover:bg-white/15 transition-colors"
          aria-label="用户"
        >
          F
        </button>
      </div>
    </header>
  );
}
