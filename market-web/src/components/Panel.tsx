import React from 'react';

interface PanelProps {
  title: string;
  right?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}

/**
 * 卡片面板：深灰背景、圆角 16、细边框、内边距 18-22
 */
export function Panel({ title, right, children, className = '' }: PanelProps) {
  return (
    <div
      className={`
        bg-card rounded-card border border-[rgba(255,255,255,0.06)]
        shadow-[0_4px_16px_-4px_rgba(0,0,0,0.25)]
        p-5 min-h-0 flex flex-col
        hover:border-white/10 transition-colors
        ${className}
      `}
    >
      <div className="flex items-center justify-between mb-4 shrink-0">
        <h3 className="text-white font-semibold text-[15px]">{title}</h3>
        {right}
      </div>
      <div className="flex-1 min-h-0">{children}</div>
    </div>
  );
}
