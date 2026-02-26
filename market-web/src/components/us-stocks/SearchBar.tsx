import React from 'react';
import { Search, Star } from 'lucide-react';

interface SearchBarProps {
  value: string;
  onChange: (v: string) => void;
}

export function SearchBar({ value, onChange }: SearchBarProps) {
  return (
    <div className="flex items-center gap-4 px-4 py-3 bg-[#0B0F14] border-b" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
      <div className="flex-1 flex items-center gap-3 px-4 py-2.5 rounded-xl bg-[#111827] border" style={{ borderColor: 'rgba(255,255,255,0.06)' }}>
        <Search className="w-5 h-5 text-white/5" style={{ color: 'rgba(255,255,255,0.5)' }} />
        <input
          type="text"
          placeholder="搜索股票代码或名称"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="flex-1 bg-transparent text-white placeholder:text-white/4 outline-none text-sm font-mono"
          style={{ fontFamily: 'JetBrains Mono, ui-monospace, monospace' }}
        />
      </div>
      <button
        type="button"
        className="flex items-center gap-2 px-4 py-2.5 rounded-xl text-amber-400 hover:bg-white/5 text-sm font-medium"
      >
        <Star className="w-4 h-4" />
        自选
      </button>
    </div>
  );
}
