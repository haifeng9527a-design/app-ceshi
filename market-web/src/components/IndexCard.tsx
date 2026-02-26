import React from 'react';
import { Sparkline } from './Sparkline';
import { formatPrice, formatPercent } from '@/utils/format';
import { colorByChange } from '@/utils/colors';
import type { IndexQuote } from '@/constants/mock';
import { TrendingUp, TrendingDown } from 'lucide-react';

interface IndexCardProps {
  data: IndexQuote;
  className?: string;
}

/**
 * 指数卡片：名称(ticker)、大数字价格、涨跌幅+箭头、底部 sparkline
 */
export function IndexCard({ data, className = '' }: IndexCardProps) {
  const isUp = data.changePercent >= 0;
  const color = colorByChange(data.changePercent);
  return (
    <div
      className={`
        bg-card rounded-card border border-[rgba(255,255,255,0.06)]
        shadow-[0_4px_16px_-4px_rgba(0,0,0,0.25)]
        p-5 flex flex-col min-w-0
        hover:border-white/10 transition-colors
        ${className}
      `}
    >
      <div className="text-white/60 text-sm mb-1">
        {data.name} ({data.ticker})
      </div>
      <div className="font-mono text-xl font-semibold text-white mb-1">
        {formatPrice(data.price)}
      </div>
      <div className="flex items-center gap-1 mb-3" style={{ color }}>
        {isUp ? <TrendingUp className="w-4 h-4" /> : <TrendingDown className="w-4 h-4" />}
        <span className="font-mono text-sm font-medium">
          {formatPercent(data.changePercent)}
        </span>
      </div>
      <Sparkline
        data={data.sparkline}
        changePercent={data.changePercent}
        width={140}
        height={32}
      />
    </div>
  );
}
