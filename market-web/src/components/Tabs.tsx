import React from 'react';

export interface TabItem {
  key: string;
  label: string;
}

interface TabsProps {
  items: TabItem[];
  activeKey: string;
  onChange: (key: string) => void;
  className?: string;
}

/**
 * 分段式 Tabs，选中高亮、未选次要色
 */
export function Tabs({ items, activeKey, onChange, className = '' }: TabsProps) {
  return (
    <div className={`flex gap-1 ${className}`}>
      {items.map((tab) => {
        const active = tab.key === activeKey;
        return (
          <button
            key={tab.key}
            type="button"
            onClick={() => onChange(tab.key)}
            className={`
              px-4 py-2 rounded-btn text-sm font-medium transition-colors
              ${active
                ? 'bg-[rgba(34,197,94,0.12)] text-up'
                : 'text-muted hover:text-white hover:bg-white/5'}
            `}
          >
            {tab.label}
          </button>
        );
      })}
    </div>
  );
}
